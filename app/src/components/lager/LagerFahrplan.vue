<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../../supabaseClient'
import {
  KATEGORIE_LABELS,
  ZUSTAENDIG_LABELS,
  faelligStatus,
  formatFaelligkeit,
  gruppiereTodos,
  type LagerTodo,
} from '../../lib/workflowUtils'

const props = defineProps<{
  lagerId: string
  startDatum: string | null
  isLeitung: boolean
  vorLagerId?: string | null
}>()

const router = useRouter()
const todos = ref<LagerTodo[]>([])
const laden = ref(true)
const nachricht = ref('')
const fehler = ref('')
const generiereLade = ref(false)
const uebernahmeLade = ref(false)

const gruppen = computed(() => gruppiereTodos(todos.value))
const offen = computed(() => todos.value.filter((t) => !t.erledigt).length)
const erledigt = computed(() => todos.value.filter((t) => t.erledigt).length)
const fortschritt = computed(() =>
  todos.value.length ? Math.round((erledigt.value / todos.value.length) * 100) : 0,
)

async function ladenTodos() {
  laden.value = true
  const { data } = await supabase
    .from('lager_todos')
    .select('id, titel, beschreibung, kategorie, zustaendig, aemtli_name, faellig_am, erledigt, sortierung')
    .eq('lager_id', props.lagerId)
    .order('sortierung')
  todos.value = data ?? []
  laden.value = false
}

onMounted(ladenTodos)

async function toggleTodo(todo: LagerTodo) {
  const erledigtNeu = !todo.erledigt
  await supabase
    .from('lager_todos')
    .update({ erledigt: erledigtNeu, erledigt_am: erledigtNeu ? new Date().toISOString() : null })
    .eq('id', todo.id)
  todo.erledigt = erledigtNeu
}

async function fahrplanGenerieren() {
  generiereLade.value = true
  fehler.value = ''
  nachricht.value = ''
  const { data, error } = await supabase.rpc('lager_todos_generieren', { p_lager_id: props.lagerId })
  generiereLade.value = false
  if (error) { fehler.value = error.message; return }
  nachricht.value = `${data ?? 0} Aufgaben aus Vorlagen erstellt.`
  await ladenTodos()
}

async function leiterUebernehmen() {
  if (!props.vorLagerId) {
    fehler.value = 'Kein Vorjahres-Lager verknüpft. In Einstellungen vor_lager_id setzen oder unten wählen.'
    return
  }
  uebernahmeLade.value = true
  fehler.value = ''
  const { data, error } = await supabase.rpc('lager_leiter_von_vorjahr', {
    p_lager_id: props.lagerId,
    p_vor_lager_id: props.vorLagerId,
  })
  uebernahmeLade.value = false
  if (error) { fehler.value = error.message; return }
  nachricht.value = `${data ?? 0} Leiter/innen provisorisch vom Vorjahr übernommen.`
}

function linkFuerTodo(todo: LagerTodo) {
  if (todo.titel.includes('Elterninfo')) return `/lager/${props.lagerId}/elterninfo`
  if (todo.kategorie === 'vorweekend') return `/lager/${props.lagerId}/vorweekend`
  if (todo.aemtli_name) {
    const slug = todo.aemtli_name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '')
    return `/lager/${props.lagerId}/aemtli/${slug}`
  }
  if (todo.kategorie === 'programm') return `/lager/${props.lagerId}/programm`
  if (todo.kategorie === 'team') return `/lager/${props.lagerId}/leiter`
  return null
}
</script>

<template>
  <section class="fahrplan">
    <header class="fahrplan-kopf">
      <div>
        <h3>Lager-Fahrplan</h3>
        <p class="hint">Checkliste von 9 Monate vor Lager bis Nachbereitung – aus dem Vereins-Wissensspeicher.</p>
      </div>
      <div v-if="isLeitung" class="fahrplan-aktionen">
        <button type="button" :disabled="generiereLade" @click="fahrplanGenerieren">
          {{ generiereLade ? 'Erstelle...' : 'Fahrplan laden' }}
        </button>
        <button type="button" class="secondary" :disabled="uebernahmeLade" @click="leiterUebernehmen">
          {{ uebernahmeLade ? 'Übernehme...' : 'Leiter vom Vorjahr' }}
        </button>
      </div>
    </header>

    <div v-if="todos.length" class="fortschritt-balken">
      <div class="balken"><div class="fill" :style="{ width: fortschritt + '%' }" /></div>
      <span class="stat">{{ erledigt }}/{{ todos.length }} erledigt ({{ fortschritt }}%)</span>
    </div>

    <p v-if="nachricht" class="ok">{{ nachricht }}</p>
    <p v-if="fehler" class="error">{{ fehler }}</p>
    <p v-if="laden">Lade Fahrplan...</p>
    <p v-else-if="!todos.length" class="hint">
      Noch kein Fahrplan. Als Lagerleitung «Fahrplan laden» klicken – Aufgaben werden aus Vorlagen mit Fälligkeitsdaten erstellt.
    </p>

    <div v-for="g in gruppen" :key="g.kategorie" class="kategorie-block">
      <h4>{{ KATEGORIE_LABELS[g.kategorie] ?? g.kategorie }}</h4>
      <ul class="todo-liste">
        <li v-for="t in g.items" :key="t.id" :class="faelligStatus(t.faellig_am, t.erledigt)">
          <label class="todo-zeile">
            <input type="checkbox" :checked="t.erledigt" @change="toggleTodo(t)" />
            <span class="todo-text" :class="{ durch: t.erledigt }">
              <strong>{{ t.titel }}</strong>
              <span v-if="t.beschreibung" class="beschreibung">{{ t.beschreibung }}</span>
            </span>
            <span class="meta">
              <span class="badge">{{ ZUSTAENDIG_LABELS[t.zustaendig] ?? t.zustaendig }}</span>
              <span v-if="t.faellig_am" class="datum">{{ formatFaelligkeit(t.faellig_am) }}</span>
            </span>
          </label>
          <router-link v-if="linkFuerTodo(t)" :to="linkFuerTodo(t)!" class="link-klein">Öffnen →</router-link>
        </li>
      </ul>
    </div>
  </section>
</template>

<style scoped>
.fahrplan-kopf { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 0.75rem; margin-bottom: 1rem; }
.fahrplan-kopf h3 { margin: 0 0 0.25rem; }
.fahrplan-aktionen { display: flex; flex-wrap: wrap; gap: 0.5rem; }
.fortschritt-balken { margin-bottom: 1.25rem; }
.balken { height: 8px; background: var(--color-surface-muted); border-radius: var(--radius-pill); overflow: hidden; }
.fill { height: 100%; background: var(--color-accent); transition: width 0.2s; }
.stat { font-size: 0.82rem; color: var(--color-text-muted); }
.kategorie-block { margin-bottom: 1.5rem; }
.kategorie-block h4 { margin: 0 0 0.5rem; font-size: 0.95rem; color: var(--color-text-muted); text-transform: uppercase; letter-spacing: 0.04em; }
.todo-liste { list-style: none; padding: 0; margin: 0; }
.todo-liste li {
  padding: 0.55rem 0.75rem; margin-bottom: 0.35rem;
  background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md);
}
.todo-liste li.ueberfaellig { border-color: var(--color-danger); background: #fdf6f4; }
.todo-liste li.bald { border-color: #c98a3f; }
.todo-zeile { display: flex; align-items: flex-start; gap: 0.6rem; cursor: pointer; }
.todo-text { flex: 1; min-width: 0; }
.todo-text.durch { opacity: 0.55; text-decoration: line-through; }
.beschreibung { display: block; font-size: 0.82rem; color: var(--color-text-muted); font-weight: 400; margin-top: 0.15rem; }
.meta { display: flex; flex-direction: column; align-items: flex-end; gap: 0.15rem; flex-shrink: 0; }
.badge { font-size: 0.7rem; padding: 0.1rem 0.4rem; border-radius: var(--radius-pill); background: var(--color-pill-bg); }
.datum { font-size: 0.75rem; color: var(--color-text-muted); font-variant-numeric: tabular-nums; }
.link-klein { display: inline-block; margin-top: 0.35rem; margin-left: 1.6rem; font-size: 0.78rem; color: var(--color-accent); }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.ok { color: var(--color-accent); font-size: 0.88rem; }
.error { color: var(--color-danger); }
</style>
