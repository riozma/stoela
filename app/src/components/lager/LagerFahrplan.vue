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
  organisationId?: string | null
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

const neuAufgabeOffen = ref(false)
const neuForm = ref({ titel: '', beschreibung: '', kategorie: 'lager', zustaendig: 'lalei', monate_vor_lager: 3 })
const bearbeitenId = ref<string | null>(null)
const bearbeitenForm = ref({ titel: '', beschreibung: '', kategorie: 'lager', zustaendig: 'lalei', monate_vor_lager: 0 })

/** Nachbildet public.lager_faelligkeit() clientseitig für sofortiges Feedback. */
function berechneFaelligkeit(startIso: string, monateVor: number): string {
  const start = new Date(startIso + 'T00:00:00')
  const ganzeMonate = Math.trunc(monateVor)
  const rest = monateVor - ganzeMonate
  const d = new Date(start)
  d.setMonth(d.getMonth() - ganzeMonate)
  d.setDate(d.getDate() - Math.round(rest * 30.4368))
  return d.toISOString().slice(0, 10)
}

function monateVorAusFaelligkeit(startIso: string, faelligIso: string | null): number {
  if (!faelligIso) return 0
  const start = new Date(startIso + 'T00:00:00')
  const faellig = new Date(faelligIso + 'T00:00:00')
  const tage = (start.getTime() - faellig.getTime()) / (1000 * 60 * 60 * 24)
  return Math.round((tage / 30.4368) * 10) / 10
}

async function aufgabeHinzufuegen() {
  if (!neuForm.value.titel.trim()) return
  fehler.value = ''
  let vorlageId: string | null = null

  if (props.organisationId) {
    const { data: vorlage, error: vErr } = await supabase
      .from('org_todo_vorlagen')
      .insert({
        organisation_id: props.organisationId,
        titel: neuForm.value.titel.trim(),
        beschreibung: neuForm.value.beschreibung.trim() || null,
        ebene: 'lager',
        monate_vor_lager: neuForm.value.monate_vor_lager,
        kategorie: neuForm.value.kategorie,
        zustaendig: neuForm.value.zustaendig,
        sortierung: todos.value.length,
      })
      .select('id')
      .single()
    if (vErr) { fehler.value = vErr.message; return }
    vorlageId = vorlage?.id ?? null
  }

  const faelligAm = props.startDatum ? berechneFaelligkeit(props.startDatum, neuForm.value.monate_vor_lager) : null
  const { error } = await supabase.from('lager_todos').insert({
    lager_id: props.lagerId,
    vorlage_id: vorlageId,
    titel: neuForm.value.titel.trim(),
    beschreibung: neuForm.value.beschreibung.trim() || null,
    kategorie: neuForm.value.kategorie,
    zustaendig: neuForm.value.zustaendig,
    faellig_am: faelligAm,
    sortierung: todos.value.length,
  })
  if (error) { fehler.value = error.message; return }

  neuForm.value = { titel: '', beschreibung: '', kategorie: 'lager', zustaendig: 'lalei', monate_vor_lager: 3 }
  neuAufgabeOffen.value = false
  nachricht.value = vorlageId
    ? 'Aufgabe hinzugefügt – wird nächstes Jahr automatisch wieder vorgeschlagen.'
    : 'Aufgabe hinzugefügt.'
  await ladenTodos()
}

function bearbeitenStarten(todo: LagerTodo) {
  bearbeitenId.value = todo.id
  bearbeitenForm.value = {
    titel: todo.titel,
    beschreibung: todo.beschreibung ?? '',
    kategorie: todo.kategorie,
    zustaendig: todo.zustaendig,
    monate_vor_lager: props.startDatum ? monateVorAusFaelligkeit(props.startDatum, todo.faellig_am) : 0,
  }
}

async function bearbeitenSpeichern(todo: LagerTodo & { vorlage_id?: string | null }) {
  fehler.value = ''
  const faelligAm = props.startDatum ? berechneFaelligkeit(props.startDatum, bearbeitenForm.value.monate_vor_lager) : todo.faellig_am

  const { error } = await supabase.from('lager_todos').update({
    titel: bearbeitenForm.value.titel.trim(),
    beschreibung: bearbeitenForm.value.beschreibung.trim() || null,
    kategorie: bearbeitenForm.value.kategorie,
    zustaendig: bearbeitenForm.value.zustaendig,
    faellig_am: faelligAm,
  }).eq('id', todo.id)
  if (error) { fehler.value = error.message; return }

  if (todo.vorlage_id) {
    await supabase.from('org_todo_vorlagen').update({
      titel: bearbeitenForm.value.titel.trim(),
      beschreibung: bearbeitenForm.value.beschreibung.trim() || null,
      kategorie: bearbeitenForm.value.kategorie,
      zustaendig: bearbeitenForm.value.zustaendig,
      monate_vor_lager: bearbeitenForm.value.monate_vor_lager,
    }).eq('id', todo.vorlage_id)
    nachricht.value = 'Gespeichert – Änderung gilt auch für nächstes Jahr.'
  } else {
    nachricht.value = 'Gespeichert.'
  }
  bearbeitenId.value = null
  await ladenTodos()
}

async function aufgabeLoeschen(todo: LagerTodo) {
  if (!confirm(`«${todo.titel}» wirklich löschen? (Nur dieses Lager – die Vorlage für nächstes Jahr bleibt bestehen)`)) return
  await supabase.from('lager_todos').delete().eq('id', todo.id)
  await ladenTodos()
}

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
    .select('id, titel, beschreibung, kategorie, zustaendig, aemtli_name, faellig_am, erledigt, sortierung, vorlage_id')
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
        <button type="button" class="secondary" @click="neuAufgabeOffen = !neuAufgabeOffen">
          + Aufgabe
        </button>
      </div>
    </header>

    <form v-if="neuAufgabeOffen" class="neu-aufgabe-form" @submit.prevent="aufgabeHinzufuegen">
      <label>Titel <input v-model="neuForm.titel" required placeholder="z.B. Sponsoring-Anfragen verschicken" /></label>
      <label>Beschreibung <input v-model="neuForm.beschreibung" placeholder="Optional" /></label>
      <label>Kategorie
        <select v-model="neuForm.kategorie">
          <option v-for="(label, key) in KATEGORIE_LABELS" :key="key" :value="key">{{ label }}</option>
        </select>
      </label>
      <label>Zuständig
        <select v-model="neuForm.zustaendig">
          <option v-for="(label, key) in ZUSTAENDIG_LABELS" :key="key" :value="key">{{ label }}</option>
        </select>
      </label>
      <label>Monate vor Lager <input v-model.number="neuForm.monate_vor_lager" type="number" step="0.5" /></label>
      <p class="hint klein">Wird auch als Vorlage gespeichert – erscheint nächstes Jahr automatisch wieder.</p>
      <div class="inline-aktionen">
        <button type="submit">Hinzufügen</button>
        <button type="button" class="secondary" @click="neuAufgabeOffen = false">Abbrechen</button>
      </div>
    </form>

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
            <span v-if="isLeitung" class="todo-admin-aktionen">
              <button type="button" class="stift-btn" title="Bearbeiten" @click.prevent="bearbeitenStarten(t)">✏️</button>
              <button type="button" class="stift-btn" title="Löschen" @click.prevent="aufgabeLoeschen(t)">✕</button>
            </span>
          </label>

          <div v-if="bearbeitenId === t.id" class="bearbeiten-zeile">
            <label>Titel <input v-model="bearbeitenForm.titel" required /></label>
            <label>Beschreibung <input v-model="bearbeitenForm.beschreibung" /></label>
            <label>Kategorie
              <select v-model="bearbeitenForm.kategorie">
                <option v-for="(label, key) in KATEGORIE_LABELS" :key="key" :value="key">{{ label }}</option>
              </select>
            </label>
            <label>Zuständig
              <select v-model="bearbeitenForm.zustaendig">
                <option v-for="(label, key) in ZUSTAENDIG_LABELS" :key="key" :value="key">{{ label }}</option>
              </select>
            </label>
            <label>Monate vor Lager <input v-model.number="bearbeitenForm.monate_vor_lager" type="number" step="0.5" /></label>
            <p v-if="t.vorlage_id" class="hint klein">Änderung gilt auch für die Vorlage (nächstes Jahr).</p>
            <div class="inline-aktionen">
              <button type="button" @click="bearbeitenSpeichern(t)">Speichern</button>
              <button type="button" class="secondary" @click="bearbeitenId = null">Abbrechen</button>
            </div>
          </div>

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
.hint.klein { font-size: 0.78rem; margin: 0.25rem 0; }
.ok { color: var(--color-accent); font-size: 0.88rem; }
.error { color: var(--color-danger); }
.neu-aufgabe-form, .bearbeiten-zeile {
  display: flex; flex-direction: column; gap: 0.6rem; margin-bottom: 1rem;
  padding: 0.85rem; background: var(--color-surface-muted); border: 1px solid var(--color-border); border-radius: var(--radius-md);
}
.neu-aufgabe-form label, .bearbeiten-zeile label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.85rem; color: var(--color-text-muted); }
.inline-aktionen { display: flex; gap: 0.5rem; }
.todo-admin-aktionen { display: flex; gap: 0.2rem; flex-shrink: 0; }
.stift-btn { background: none; border: none; cursor: pointer; font-size: 0.85rem; padding: 0.1rem 0.25rem; }
</style>
