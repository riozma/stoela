<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { downloadIcs } from '../../lib/ics'
import {
  TERMIN_TYP_LABELS,
  KALENDER_READONLY_TYPEN,
  KALENDER_READONLY_HINTS,
  KALENDER_FORM_TYPEN,
  KALENDER_SINGLETON_TYPEN,
  kannKalenderTerminLoeschen,
  formatTerminDatum,
  formatTerminZeit,
  type LagerTermin,
  type LagerTerminTyp,
} from '../../lib/lagerTermine'

const props = defineProps<{
  lagerId: string
  lagerName: string
  organisationId: string | null
  organisationName: string
  isLeitung: boolean
}>()

const termine = ref<LagerTermin[]>([])
const kalenderToken = ref('')
const kalenderTitel = ref('')
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
  nurEinTag: true,
})

const einTagTypen: LagerTerminTyp[] = ['elternabend', 'kennenlernabend', 'diashow']
const istEinTagTyp = computed(() => einTagTypen.includes(form.value.typ))

const orgKalenderBereit = computed(() => Boolean(props.organisationId && kalenderToken.value))

const webcalUrl = computed(() => {
  if (!orgKalenderBereit.value) return ''
  const base = String(import.meta.env.VITE_SUPABASE_URL ?? '').replace(/\/$/, '')
  const httpsUrl = `${base}/functions/v1/lager-kalender-ics?organisation_id=${props.organisationId}&token=${kalenderToken.value}`
  return httpsUrl.replace(/^https:\/\//, 'webcal://')
})

const httpsKalenderUrl = computed(() => {
  if (!orgKalenderBereit.value) return ''
  const base = String(import.meta.env.VITE_SUPABASE_URL ?? '').replace(/\/$/, '')
  return `${base}/functions/v1/lager-kalender-ics?organisation_id=${props.organisationId}&token=${kalenderToken.value}`
})

function istReadonly(t: LagerTermin) {
  return KALENDER_READONLY_TYPEN.includes(t.typ)
}

function readonlyHinweis(t: LagerTermin) {
  return KALENDER_READONLY_HINTS[t.typ] ?? null
}

async function ladenKalenderTitel() {
  if (!props.organisationId) {
    kalenderTitel.value = props.organisationName || props.lagerName
    return
  }
  const { data } = await supabase.rpc('org_kalender_titel', { p_organisation_id: props.organisationId })
  kalenderTitel.value = (data as string) ?? props.organisationName
}

async function laden() {
  fehler.value = ''
  const orgQuery = props.organisationId
    ? supabase.from('organisation').select('kalender_token, name').eq('id', props.organisationId).single()
    : Promise.resolve({ data: null })

  const [{ data: t }, { data: org }] = await Promise.all([
    supabase
      .from('lager_termine')
      .select('*')
      .eq('lager_id', props.lagerId)
      .order('start_datum', { ascending: true, nullsFirst: false })
      .order('sortierung'),
    orgQuery,
  ])
  termine.value = (t ?? []) as LagerTermin[]
  kalenderToken.value = org?.kalender_token ?? ''
  if (org?.name) kalenderTitel.value = org.name

  await supabase.rpc('lager_termine_sync', { p_lager_id: props.lagerId })
  const { data: t2 } = await supabase
    .from('lager_termine')
    .select('*')
    .eq('lager_id', props.lagerId)
    .order('start_datum', { ascending: true, nullsFirst: false })
  termine.value = (t2 ?? []) as LagerTermin[]
  await ladenKalenderTitel()
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
    nurEinTag: true,
  }
}

function bearbeitenStart(t: LagerTermin) {
  if (istReadonly(t)) return
  bearbeitenId.value = t.id
  const einTag = !t.end_datum || t.end_datum === t.start_datum
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
    nurEinTag: einTagTypen.includes(t.typ) ? einTag : false,
  }
}

async function speichernHandler() {
  if (!props.isLeitung) return
  if (KALENDER_READONLY_TYPEN.includes(form.value.typ)) {
    fehler.value = 'Dieser Termintyp wird an anderer Stelle gepflegt.'
    return
  }

  speichern.value = true
  fehler.value = ''

  let zielId = bearbeitenId.value
  if (!zielId && KALENDER_SINGLETON_TYPEN.includes(form.value.typ)) {
    const vorhanden = termine.value.find((t) => t.typ === form.value.typ)
    if (vorhanden) zielId = vorhanden.id
  }

  const endDatum = form.value.nurEinTag || !form.value.end_datum
    ? form.value.start_datum || null
    : form.value.end_datum || null
  const payload = {
    lager_id: props.lagerId,
    typ: form.value.typ,
    titel: form.value.titel.trim() || TERMIN_TYP_LABELS[form.value.typ],
    start_datum: form.value.start_datum || null,
    end_datum: endDatum,
    start_zeit: form.value.start_zeit || null,
    end_zeit: form.value.end_zeit || null,
    ort: form.value.ort || null,
    beschreibung: form.value.beschreibung || null,
    oeffentlich: form.value.oeffentlich,
    updated_at: new Date().toISOString(),
  }

  const { error } = zielId
    ? await supabase.from('lager_termine').update(payload).eq('id', zielId)
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
  const t = termine.value.find((x) => x.id === id)
  if (!t || !kannKalenderTerminLoeschen(t.typ)) return
  await supabase.from('lager_termine').delete().eq('id', id)
  await laden()
}

async function icsDownload() {
  if (!props.organisationId) {
    fehler.value = 'Keine Organisation verknüpft.'
    return
  }
  const { data, error } = await supabase.rpc('get_org_kalender_ics', {
    p_organisation_id: props.organisationId,
  })
  if (error || !data) {
    fehler.value = error?.message ?? 'ICS konnte nicht erzeugt werden.'
    return
  }
  downloadIcs(`${(kalenderTitel.value || props.organisationName).replace(/\s+/g, '_')}_kalender.ics`, data as string)
}

async function linkKopieren(text: string) {
  try {
    await navigator.clipboard.writeText(text)
    fehler.value = ''
  } catch {
    fehler.value = 'Link konnte nicht kopiert werden – bitte manuell markieren.'
  }
}
</script>

<template>
  <section class="kalender">
    <header class="kopf">
      <div>
        <h3>Lager-Kalender</h3>
        <p class="hint">
          Termine dieses Lagers. Der Abo-Link gilt <strong>vereinsweit</strong> – alle Lager laden auf dieselbe URL.
          Der Lager-Termin ist mit den Einstellungen verknüpft (ein Eintrag, kein Duplikat).
          Elternabend/Kennenlernabend/Diashow unter Elterninfo. Skiweekend, Höck und Sonstiges hier löschbar.
        </p>
      </div>
      <div class="aktionen">
        <button type="button" :disabled="!orgKalenderBereit" @click="icsDownload">Vereinskalender (.ics)</button>
      </div>
    </header>

    <p v-if="kalenderTitel" class="kalender-name">
      Kalender-Name beim Abonnieren: <strong>{{ kalenderTitel }}</strong>
      <span class="hint-inline">(gleich für alle Lager im Verein)</span>
    </p>

    <details class="anleitung">
      <summary>Kalender abonnieren – Anleitung</summary>
      <div class="anleitung-inhalt">
        <p><strong>Google Kalender</strong></p>
        <ol>
          <li>Links «Andere Kalender» → «Von URL»</li>
          <li>HTTPS-Link einfügen (unten) → «Kalender hinzufügen»</li>
        </ol>
        <p><strong>Apple Kalender (iPhone/Mac)</strong></p>
        <ol>
          <li>Einstellungen → Kalender → Accounts → «Kalenderabo hinzufügen»</li>
          <li>webcal-Link einfügen oder ICS-Datei öffnen</li>
        </ol>
        <p><strong>Outlook</strong></p>
        <ol>
          <li>«Kalender hinzufügen» → «Aus dem Internet»</li>
          <li>HTTPS-Link einfügen</li>
        </ol>
        <p><strong>Alternativ:</strong> «Vereinskalender (.ics)» herunterladen und Datei per Doppelklick importieren.</p>
      </div>
    </details>

    <p v-if="orgKalenderBereit" class="abo-hinweis">
      Abo-Link (webcal): <code>{{ webcalUrl }}</code>
      <button type="button" class="secondary klein" @click="linkKopieren(webcalUrl)">Kopieren</button><br />
      HTTPS: <code>{{ httpsKalenderUrl }}</code>
      <button type="button" class="secondary klein" @click="linkKopieren(httpsKalenderUrl)">Kopieren</button>
    </p>

    <ul v-if="termine.length" class="termin-liste">
      <li v-for="t in termine" :key="t.id" class="termin-zeile" :class="{ readonly: istReadonly(t) }">
        <span class="typ">{{ TERMIN_TYP_LABELS[t.typ] }}</span>
        <strong>{{ t.titel }}</strong>
        <span>{{ formatTerminDatum(t) }}</span>
        <span v-if="formatTerminZeit(t)">{{ formatTerminZeit(t) }}</span>
        <span v-if="t.ort" class="ort">{{ t.ort }}</span>
        <span v-if="t.oeffentlich" class="badge">öffentlich</span>
        <span v-if="readonlyHinweis(t)" class="readonly-hint">{{ readonlyHinweis(t) }}</span>
        <div v-if="isLeitung && (!istReadonly(t) || kannKalenderTerminLoeschen(t.typ))" class="inline">
          <button v-if="!istReadonly(t)" type="button" class="secondary klein" @click="bearbeitenStart(t)">Bearbeiten</button>
          <button v-if="kannKalenderTerminLoeschen(t.typ)" type="button" class="secondary klein" title="Löschen" @click="loeschen(t.id)">×</button>
        </div>
      </li>
    </ul>
    <p v-else class="hint">Noch keine Termine – werden aus Lagerdaten synchronisiert.</p>

    <form v-if="isLeitung" class="termin-form" @submit.prevent="speichernHandler">
      <h4>{{ bearbeitenId ? 'Termin bearbeiten' : 'Termin hinzufügen' }}</h4>
      <label>Typ
        <select v-model="form.typ">
          <option v-for="typ in KALENDER_FORM_TYPEN" :key="typ" :value="typ">{{ TERMIN_TYP_LABELS[typ] }}</option>
        </select>
      </label>
      <label>Titel <input v-model="form.titel" /></label>
      <label>Start <input v-model="form.start_datum" type="date" /></label>
      <label>Ende <input v-model="form.end_datum" type="date" /></label>
      <label>Von <input v-model="form.start_zeit" type="time" /></label>
      <label>Bis <input v-model="form.end_zeit" type="time" /></label>
      <label>Ort <input v-model="form.ort" /></label>
      <label>Beschreibung <input v-model="form.beschreibung" /></label>
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
.hint-inline { color: var(--color-text-muted); font-size: 0.82rem; margin-left: 0.35rem; }
.abo-hinweis { font-size: 0.82rem; background: var(--color-surface-muted); padding: 0.5rem 0.65rem; border-radius: var(--radius-md); word-break: break-all; }
.termin-liste { list-style: none; padding: 0; margin: 0 0 1rem; }
.termin-zeile {
  display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem 0.75rem;
  padding: 0.5rem 0; border-bottom: 1px solid var(--color-border); font-size: 0.88rem;
}
.termin-zeile.readonly { opacity: 0.92; }
.typ { font-size: 0.72rem; background: var(--color-surface-muted); padding: 0.1rem 0.4rem; border-radius: 999px; }
.ort { color: var(--color-text-muted); }
.badge { font-size: 0.7rem; color: #2e7d32; }
.readonly-hint { font-size: 0.75rem; color: var(--color-text-muted); font-style: italic; }
.termin-form {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 0.65rem;
  border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.85rem;
}
.termin-form h4 { grid-column: 1 / -1; margin: 0; }
label { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.82rem; color: var(--color-text-muted); }
.inline { display: flex; gap: 0.4rem; flex-wrap: wrap; }
button.klein { font-size: 0.78rem; padding: 0.2rem 0.45rem; }
.kalender-name { font-size: 0.9rem; margin: 0 0 0.75rem; }
.anleitung { margin: 0 0 1rem; border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.5rem 0.75rem; }
.anleitung summary { cursor: pointer; font-weight: 600; }
.anleitung-inhalt { margin-top: 0.65rem; font-size: 0.85rem; color: var(--color-text-muted); }
.anleitung-inhalt ol { margin: 0.25rem 0 0.75rem 1.2rem; padding: 0; }
.error { color: var(--color-danger); }
</style>
