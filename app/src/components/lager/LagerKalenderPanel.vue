<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { downloadIcs } from '../../lib/ics'
import {
  TERMIN_TYP_LABELS,
  formatTerminDatum,
  formatTerminZeit,
  type LagerTermin,
  type LagerTerminTyp,
} from '../../lib/lagerTermine'

const props = defineProps<{
  lagerId: string
  lagerName: string
  isLeitung: boolean
}>()

const termine = ref<LagerTermin[]>([])
const kalenderToken = ref('')
const fehler = ref('')
const speichern = ref(false)
const bearbeitenId = ref<string | null>(null)

const form = ref({
  typ: 'sonstiges' as LagerTerminTyp,
  titel: '',
  start_datum: '',
  end_datum: '',
  start_zeit: '',
  end_zeit: '',
  ort: '',
  beschreibung: '',
  oeffentlich: false,
})

const webcalUrl = computed(() => {
  if (!kalenderToken.value) return ''
  const base = String(import.meta.env.VITE_SUPABASE_URL ?? '').replace(/\/$/, '')
  const httpsUrl = `${base}/functions/v1/lager-kalender-ics?lager_id=${props.lagerId}&token=${kalenderToken.value}`
  return httpsUrl.replace(/^https:\/\//, 'webcal://')
})

const httpsKalenderUrl = computed(() => {
  if (!kalenderToken.value) return ''
  const base = String(import.meta.env.VITE_SUPABASE_URL ?? '').replace(/\/$/, '')
  return `${base}/functions/v1/lager-kalender-ics?lager_id=${props.lagerId}&token=${kalenderToken.value}`
})

async function laden() {
  fehler.value = ''
  const [{ data: t }, { data: lager }] = await Promise.all([
    supabase
      .from('lager_termine')
      .select('*')
      .eq('lager_id', props.lagerId)
      .order('start_datum', { ascending: true, nullsFirst: false })
      .order('sortierung'),
    supabase.from('lager').select('kalender_token').eq('id', props.lagerId).single(),
  ])
  termine.value = (t ?? []) as LagerTermin[]
  kalenderToken.value = lager?.kalender_token ?? ''
  await supabase.rpc('lager_termine_sync', { p_lager_id: props.lagerId })
  const { data: t2 } = await supabase
    .from('lager_termine')
    .select('*')
    .eq('lager_id', props.lagerId)
    .order('start_datum', { ascending: true, nullsFirst: false })
  termine.value = (t2 ?? []) as LagerTermin[]
}

onMounted(laden)

function resetForm() {
  bearbeitenId.value = null
  form.value = {
    typ: 'sonstiges',
    titel: '',
    start_datum: '',
    end_datum: '',
    start_zeit: '',
    end_zeit: '',
    ort: '',
    beschreibung: '',
    oeffentlich: false,
  }
}

function bearbeitenStart(t: LagerTermin) {
  bearbeitenId.value = t.id
  form.value = {
    typ: t.typ,
    titel: t.titel,
    start_datum: t.start_datum ?? '',
    end_datum: t.end_datum ?? '',
    start_zeit: t.start_zeit ?? '',
    end_zeit: t.end_zeit ?? '',
    ort: t.ort ?? '',
    beschreibung: t.beschreibung ?? '',
    oeffentlich: t.oeffentlich,
  }
}

async function speichernHandler() {
  if (!props.isLeitung) return
  speichern.value = true
  fehler.value = ''
  const payload = {
    lager_id: props.lagerId,
    typ: form.value.typ,
    titel: form.value.titel.trim() || TERMIN_TYP_LABELS[form.value.typ],
    start_datum: form.value.start_datum || null,
    end_datum: form.value.end_datum || null,
    start_zeit: form.value.start_zeit || null,
    end_zeit: form.value.end_zeit || null,
    ort: form.value.ort || null,
    beschreibung: form.value.beschreibung || null,
    oeffentlich: form.value.oeffentlich,
    updated_at: new Date().toISOString(),
  }
  const { error } = bearbeitenId.value
    ? await supabase.from('lager_termine').update(payload).eq('id', bearbeitenId.value)
    : await supabase.from('lager_termine').insert(payload)
  speichern.value = false
  if (error) {
    fehler.value = error.message
    return
  }
  resetForm()
  await laden()
}

async function loeschen(id: string) {
  if (!props.isLeitung || !window.confirm('Termin löschen?')) return
  await supabase.from('lager_termine').delete().eq('id', id)
  await laden()
}

async function icsDownload() {
  const { data, error } = await supabase.rpc('get_lager_kalender_ics', { p_lager_id: props.lagerId })
  if (error || !data) {
    fehler.value = error?.message ?? 'ICS konnte nicht erzeugt werden.'
    return
  }
  downloadIcs(`${props.lagerName.replace(/\s+/g, '_')}_kalender.ics`, data as string)
}

const oeffentlicheTypen: LagerTerminTyp[] = ['elternabend', 'kennenlernabend', 'diashow']
</script>

<template>
  <section class="kalender">
    <header class="kopf">
      <div>
        <h3>Lager-Kalender</h3>
        <p class="hint">
          Zentral für Leiter: Lager, Elternabend, Kennenlernabend, Diashow, Vorweekend, Skiweekend, Höck etc.
          Öffentliche Termine fliessen in TN-Anmeldung und Elterninfo ein.
        </p>
      </div>
      <div class="aktionen">
        <button type="button" @click="icsDownload">ICS herunterladen</button>
      </div>
    </header>

    <p v-if="kalenderToken" class="abo-hinweis">
      Kalender abonnieren (Google/Apple/Outlook):<br />
      <code>{{ webcalUrl }}</code><br />
      <span class="klein">HTTPS: {{ httpsKalenderUrl }}</span>
    </p>

    <ul v-if="termine.length" class="termin-liste">
      <li v-for="t in termine" :key="t.id" class="termin-zeile">
        <span class="typ">{{ TERMIN_TYP_LABELS[t.typ] }}</span>
        <strong>{{ t.titel }}</strong>
        <span>{{ formatTerminDatum(t) }}</span>
        <span v-if="formatTerminZeit(t)">{{ formatTerminZeit(t) }}</span>
        <span v-if="t.ort" class="ort">{{ t.ort }}</span>
        <span v-if="t.oeffentlich" class="badge">öffentlich</span>
        <div v-if="isLeitung" class="inline">
          <button type="button" class="secondary klein" @click="bearbeitenStart(t)">Bearbeiten</button>
          <button v-if="t.typ === 'sonstiges' || t.typ === 'hoeck'" type="button" class="secondary klein" @click="loeschen(t.id)">×</button>
        </div>
      </li>
    </ul>
    <p v-else class="hint">Noch keine Termine – werden aus Lagerdaten synchronisiert.</p>

    <form v-if="isLeitung" class="termin-form" @submit.prevent="speichernHandler">
      <h4>{{ bearbeitenId ? 'Termin bearbeiten' : 'Termin hinzufügen' }}</h4>
      <label>Typ
        <select v-model="form.typ">
          <option v-for="(label, key) in TERMIN_TYP_LABELS" :key="key" :value="key">{{ label }}</option>
        </select>
      </label>
      <label>Titel <input v-model="form.titel" /></label>
      <label>Start <input v-model="form.start_datum" type="date" /></label>
      <label>Ende <input v-model="form.end_datum" type="date" /></label>
      <label>Von <input v-model="form.start_zeit" type="time" /></label>
      <label>Bis <input v-model="form.end_zeit" type="time" /></label>
      <label>Ort <input v-model="form.ort" /></label>
      <label>Beschreibung <input v-model="form.beschreibung" /></label>
      <label v-if="oeffentlicheTypen.includes(form.typ)" class="checkbox">
        <input v-model="form.oeffentlich" type="checkbox" />
        In TN-Anmeldung / Elterninfo anzeigen
      </label>
      <div class="inline">
        <button type="submit" :disabled="speichern">{{ speichern ? 'Speichere…' : 'Speichern' }}</button>
        <button v-if="bearbeitenId" type="button" class="secondary" @click="resetForm">Abbrechen</button>
      </div>
    </form>
    <p v-if="fehler" class="error">{{ fehler }}</p>
  </section>
</template>

<style scoped>
.kalender { margin: 1rem 0; }
.kopf { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 0.75rem; margin-bottom: 0.75rem; }
.kopf h3 { margin: 0 0 0.25rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.abo-hinweis { font-size: 0.82rem; background: var(--color-surface-muted); padding: 0.5rem 0.65rem; border-radius: var(--radius-md); word-break: break-all; }
.termin-liste { list-style: none; padding: 0; margin: 0 0 1rem; }
.termin-zeile {
  display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem 0.75rem;
  padding: 0.5rem 0; border-bottom: 1px solid var(--color-border); font-size: 0.88rem;
}
.typ { font-size: 0.72rem; background: var(--color-surface-muted); padding: 0.1rem 0.4rem; border-radius: 999px; }
.ort { color: var(--color-text-muted); }
.badge { font-size: 0.7rem; color: #2e7d32; }
.termin-form {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 0.65rem;
  border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.85rem;
}
.termin-form h4 { grid-column: 1 / -1; margin: 0; }
label { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.82rem; color: var(--color-text-muted); }
.checkbox { flex-direction: row !important; align-items: center; color: var(--color-text) !important; }
.inline { display: flex; gap: 0.4rem; flex-wrap: wrap; }
button.klein { font-size: 0.78rem; padding: 0.2rem 0.45rem; }
.klein { font-size: 0.78rem; color: var(--color-text-muted); display: block; margin-top: 0.35rem; }
</style>
