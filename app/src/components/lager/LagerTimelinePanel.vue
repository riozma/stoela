<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../supabaseClient'
import {
  JAHRES_MEILENSTEINE,
  featureAktiv,
  lagerPhase,
  meilensteinStatus,
  monateVorLager,
  naechsteTodos,
  phaseLabel,
  tageBisLager,
} from '../../lib/lagerTimeline'
import { faelligStatus, formatFaelligkeit, type LagerTodo } from '../../lib/workflowUtils'

const props = defineProps<{
  lagerId: string
  startDatum: string | null
  endDatum: string | null
  isLeitung: boolean
}>()

const emit = defineEmits<{ fahrplan: [] }>()

const router = useRouter()
const todos = ref<LagerTodo[]>([])
const laden = ref(true)

const phase = computed(() => lagerPhase(props.startDatum, props.endDatum))
const phaseText = computed(() => phaseLabel(props.startDatum, props.endDatum))
const monate = computed(() => monateVorLager(props.startDatum))
const tage = computed(() => tageBisLager(props.startDatum))
const naechste = computed(() => naechsteTodos(todos.value, 5))
const fortschritt = computed(() => {
  if (!todos.value.length) return 0
  return Math.round((todos.value.filter((t) => t.erledigt).length / todos.value.length) * 100)
})

const aktiveFeatures = computed(() => {
  const list: { name: string; aktiv: boolean }[] = [
    { name: 'Kiosk', aktiv: featureAktiv('kiosk', props.startDatum, props.endDatum) },
    { name: 'Mörderli', aktiv: featureAktiv('moerderli', props.startDatum, props.endDatum) },
    { name: 'Werbung', aktiv: featureAktiv('werbung', props.startDatum, props.endDatum) },
    { name: 'Sponsoring', aktiv: featureAktiv('sponsoring', props.startDatum, props.endDatum) },
    { name: 'Kuchenstand', aktiv: featureAktiv('kuchenstand', props.startDatum, props.endDatum) },
    { name: 'Motto', aktiv: featureAktiv('motto', props.startDatum, props.endDatum) },
  ]
  return list
})

async function ladenTodos() {
  laden.value = true
  const { data } = await supabase
    .from('lager_todos')
    .select('id, titel, beschreibung, kategorie, zustaendig, aemtli_name, faellig_am, erledigt, sortierung')
    .eq('lager_id', props.lagerId)
    .order('sortierung')
  todos.value = data ?? []

  if (!todos.value.length && props.isLeitung && props.startDatum) {
    await supabase.rpc('lager_todos_generieren', { p_lager_id: props.lagerId })
    const { data: neu } = await supabase
      .from('lager_todos')
      .select('id, titel, beschreibung, kategorie, zustaendig, aemtli_name, faellig_am, erledigt, sortierung')
      .eq('lager_id', props.lagerId)
      .order('sortierung')
    todos.value = neu ?? []
  }
  laden.value = false
}

onMounted(ladenTodos)

function todoLink(t: LagerTodo) {
  if (t.titel.includes('Elterninfo')) return `/lager/${props.lagerId}/elterninfo`
  if (t.kategorie === 'vorweekend') return `/lager/${props.lagerId}/vorweekend`
  if (t.aemtli_name) {
    const slug = t.aemtli_name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '')
    return `/lager/${props.lagerId}/aemtli/${slug}`
  }
  if (t.kategorie === 'team') return `/lager/${props.lagerId}/leiter`
  return `/lager/${props.lagerId}/fahrplan`
}

function zuTodo(t: LagerTodo) {
  router.push(todoLink(t))
}
</script>

<template>
  <section class="timeline-panel">
    <header class="panel-kopf">
      <div>
        <h3>Jahres-Fahrplan</h3>
        <p class="phase-badge">{{ phaseText }}</p>
        <p v-if="monate !== null && phase !== 'im_lager' && phase !== 'nachlager'" class="countdown">
          <template v-if="tage !== null && tage > 0">Noch {{ tage }} Tage bis Lagerstart</template>
          <template v-else-if="tage !== null && tage <= 0">Lagerstart naht!</template>
          <span class="klein"> (ca. {{ monate.toFixed(1) }} Monate)</span>
        </p>
      </div>
      <div class="kopf-rechts">
        <div v-if="todos.length" class="mini-fortschritt">
          <div class="balken"><div class="fill" :style="{ width: fortschritt + '%' }" /></div>
          <span>{{ fortschritt }}% erledigt</span>
        </div>
        <button type="button" class="secondary" @click="emit('fahrplan')">Ganzer Fahrplan →</button>
      </div>
    </header>

    <div v-if="!startDatum" class="warn-box">
      Bitte Lagerstart in <strong>Einstellungen</strong> setzen – dann werden alle Fälligkeiten automatisch berechnet.
    </div>

    <div v-if="naechste.length" class="naechste-block">
      <h4>Als Nächstes</h4>
      <ul class="naechste-liste">
        <li v-for="t in naechste" :key="t.id" :class="faelligStatus(t.faellig_am, t.erledigt)">
          <button type="button" class="todo-btn" @click="zuTodo(t)">
            <strong>{{ t.titel }}</strong>
            <span v-if="t.faellig_am" class="datum">{{ formatFaelligkeit(t.faellig_am) }}</span>
          </button>
        </li>
      </ul>
    </div>
    <p v-else-if="!laden && startDatum" class="hint">Keine offenen Aufgaben – super!</p>
    <p v-else-if="laden" class="hint">Lade Fahrplan…</p>

    <div class="meilensteine">
      <h4>Jahresübersicht</h4>
      <div class="ms-rail">
        <div
          v-for="(m, i) in JAHRES_MEILENSTEINE"
          :key="i"
          class="ms-punkt"
          :class="meilensteinStatus(m.monate, startDatum)"
          :title="m.titel"
        >
          <span class="ms-kurz">{{ m.kurz }}</span>
        </div>
      </div>
    </div>

    <div class="features">
      <span v-for="f in aktiveFeatures" :key="f.name" class="feature-pill" :class="{ aktiv: f.aktiv }">
        {{ f.name }}{{ f.aktiv ? ' ✓' : '' }}
      </span>
    </div>
  </section>
</template>

<style scoped>
.timeline-panel {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 1rem 1.15rem;
  margin-bottom: 1.25rem;
}
.panel-kopf { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 0.75rem; margin-bottom: 0.75rem; }
.panel-kopf h3 { margin: 0 0 0.25rem; font-size: 1.05rem; }
.phase-badge {
  display: inline-block; margin: 0;
  padding: 0.2rem 0.55rem; border-radius: var(--radius-pill);
  background: var(--color-accent); color: #fdfbf3; font-size: 0.82rem; font-weight: 600;
}
.countdown { margin: 0.35rem 0 0; font-size: 0.88rem; color: var(--color-text-muted); }
.klein { font-size: 0.78rem; }
.kopf-rechts { display: flex; flex-direction: column; align-items: flex-end; gap: 0.4rem; }
.mini-fortschritt { text-align: right; font-size: 0.78rem; color: var(--color-text-muted); }
.balken { width: 120px; height: 6px; background: var(--color-surface-muted); border-radius: var(--radius-pill); overflow: hidden; margin-bottom: 0.15rem; }
.fill { height: 100%; background: var(--color-accent); }
.warn-box { background: #fdf8f0; border: 1px solid #c98a3f; border-radius: var(--radius-md); padding: 0.6rem 0.85rem; font-size: 0.88rem; margin-bottom: 0.75rem; }
.naechste-block h4, .meilensteine h4 { margin: 0.75rem 0 0.4rem; font-size: 0.85rem; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.04em; }
.naechste-liste { list-style: none; padding: 0; margin: 0; }
.naechste-liste li { margin-bottom: 0.3rem; border-radius: var(--radius-sm); }
.naechste-liste li.ueberfaellig { background: #fdf6f4; }
.naechste-liste li.bald { background: #fdf8f0; }
.todo-btn {
  display: flex; justify-content: space-between; align-items: center; gap: 0.5rem;
  width: 100%; padding: 0.45rem 0.65rem; border: none; background: transparent;
  text-align: left; cursor: pointer; border-radius: var(--radius-sm); color: var(--color-text);
}
.todo-btn:hover { background: var(--color-surface-muted); }
.datum { font-size: 0.78rem; color: var(--color-text-muted); flex-shrink: 0; }
.ms-rail { display: flex; flex-wrap: wrap; gap: 0.35rem; }
.ms-punkt {
  padding: 0.25rem 0.45rem; border-radius: var(--radius-pill); font-size: 0.72rem;
  background: var(--color-surface-muted); color: var(--color-text-muted); border: 1px solid var(--color-border);
}
.ms-punkt.aktuell { background: var(--color-accent); color: #fdfbf3; border-color: var(--color-accent); font-weight: 700; }
.ms-punkt.erledigt { opacity: 0.45; text-decoration: line-through; }
.features { display: flex; flex-wrap: wrap; gap: 0.35rem; margin-top: 0.75rem; }
.feature-pill {
  font-size: 0.72rem; padding: 0.15rem 0.45rem; border-radius: var(--radius-pill);
  background: var(--color-surface-muted); color: var(--color-text-muted); opacity: 0.5;
}
.feature-pill.aktiv { opacity: 1; background: var(--color-pill-bg); color: var(--color-text); font-weight: 600; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
