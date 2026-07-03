<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { extractPdfPages } from '../../lib/pdfText'
import { useAuth } from '../../composables/useAuth'
import * as XLSX from 'xlsx'

type VorschlagStatus = 'offen' | 'angenommen' | 'abgelehnt'
type ActionType =
  | 'update_lager'
  | 'insert_programmblock'
  | 'update_programmblock'
  | 'delete_programmblock'
  | 'insert_tn'
  | 'update_tn'
  | 'insert_leiter'
  | 'update_leiter'
  | 'assign_leiter_aemtli'
  | 'create_lager_todo'
  | 'update_lager_todo'
  | 'create_gruppe'
  | 'assign_gruppenmitglied'

interface GeminiVorschlag {
  id: string
  titel: string
  beschreibung: string | null
  action_type: ActionType
  payload: Record<string, unknown>
  status: VorschlagStatus
  last_error: string | null
  created_at: string
  bearbeitet_at: string | null
}

const props = defineProps<{
  lagerId: string
  organisationId: string | null
  lagerName: string
  lagerJahr: number
  lagerStatus: string
  startDatum: string | null
  endDatum: string | null
  ort: string | null
}>()
const emit = defineEmits<{ applied: [actionType: ActionType] }>()

const eingabe = ref('')
const dateien = ref<File[]>([])
const analysiere = ref(false)
const ladeListe = ref(false)
const fehler = ref('')
const info = ref('')
const vorschlaege = ref<GeminiVorschlag[]>([])
const { session } = useAuth()

const payloadEdit = ref<Record<string, string>>({})
const imEditModus = ref<Record<string, boolean>>({})
const aktionLade = ref<Record<string, boolean>>({})
const dragAktiv = ref(false)
const zuletztAngenommenId = ref<string | null>(null)

const offene = computed(() => vorschlaege.value.filter((v) => v.status === 'offen'))
const kannAnalysieren = computed(() => !!eingabe.value.trim() || dateien.value.length > 0)

function prettyAction(action: ActionType) {
  const map: Record<ActionType, string> = {
    update_lager: 'Lagerdaten aktualisieren',
    insert_programmblock: 'Programmblock erstellen',
    update_programmblock: 'Programmblock aktualisieren',
    delete_programmblock: 'Programmblock löschen',
    insert_tn: 'TN-Anmeldung erfassen',
    update_tn: 'TN-Anmeldung aktualisieren',
    insert_leiter: 'Leiter-Anmeldung erfassen',
    update_leiter: 'Leiter-Anmeldung aktualisieren',
    assign_leiter_aemtli: 'Leiter-Ämtli zuweisen',
    create_lager_todo: 'Todo erstellen',
    update_lager_todo: 'Todo aktualisieren',
    create_gruppe: 'Gruppe erstellen',
    assign_gruppenmitglied: 'Gruppenmitglied zuweisen/übertragen',
  }
  return map[action]
}

function dateienSetzen(files: File[]) {
  dateien.value = files
}

function onDateien(event: Event) {
  const target = event.target as HTMLInputElement
  dateienSetzen(Array.from(target.files ?? []))
}

function onDragOver(event: DragEvent) {
  event.preventDefault()
  dragAktiv.value = true
}

function onDragLeave(event: DragEvent) {
  event.preventDefault()
  dragAktiv.value = false
}

function onDrop(event: DragEvent) {
  event.preventDefault()
  dragAktiv.value = false
  dateienSetzen(Array.from(event.dataTransfer?.files ?? []))
}

async function fileToBase64(file: File): Promise<string> {
  const buffer = await file.arrayBuffer()
  const bytes = new Uint8Array(buffer)
  let binary = ''
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk))
  }
  return btoa(binary)
}

async function dokumenteVorbereiten() {
  const docs: Array<{ name: string; mimeType: string; text?: string; base64?: string }> = []
  for (const f of dateien.value) {
    const isPdf = f.type === 'application/pdf' || f.name.toLowerCase().endsWith('.pdf')
    const isCsv = f.type === 'text/csv' || f.name.toLowerCase().endsWith('.csv')
    const isExcel = /\.(xlsx|xls)$/i.test(f.name)
    if (isPdf) {
      const seiten = await extractPdfPages(f)
      docs.push({
        name: f.name,
        mimeType: 'application/pdf',
        text: seiten.join('\n\n').slice(0, 70000),
      })
      continue
    }
    if (isCsv) {
      const text = await f.text()
      docs.push({ name: f.name, mimeType: 'text/csv', text: text.slice(0, 70000) })
      continue
    }
    if (isExcel) {
      const buffer = await f.arrayBuffer()
      const workbook = XLSX.read(buffer, { type: 'array' })
      const sheets = workbook.SheetNames.slice(0, 3).map((sheetName) => {
        const sheet = workbook.Sheets[sheetName]
        const csv = XLSX.utils.sheet_to_csv(sheet)
        return `--- Sheet: ${sheetName} ---\n${csv}`
      })
      docs.push({
        name: f.name,
        mimeType: f.type || 'application/vnd.ms-excel',
        text: sheets.join('\n\n').slice(0, 70000),
      })
      continue
    }
    if (f.type.startsWith('image/')) {
      docs.push({
        name: f.name,
        mimeType: f.type,
        base64: await fileToBase64(f),
      })
      continue
    }
    const text = await f.text()
    docs.push({ name: f.name, mimeType: f.type || 'text/plain', text: text.slice(0, 70000) })
  }
  return docs
}

async function laden() {
  ladeListe.value = true
  const { data, error } = await supabase
    .from('lager_ai_vorschlaege')
    .select('id, titel, beschreibung, action_type, payload, status, last_error, created_at, bearbeitet_at')
    .eq('lager_id', props.lagerId)
    .order('created_at', { ascending: false })
  ladeListe.value = false
  if (error) {
    fehler.value = error.message
    return
  }
  vorschlaege.value = (data ?? []) as GeminiVorschlag[]
  payloadEdit.value = {}
  imEditModus.value = {}
  for (const v of vorschlaege.value) {
    payloadEdit.value[v.id] = JSON.stringify(v.payload ?? {}, null, 2)
  }
}

async function analysieren() {
  if (!kannAnalysieren.value) return
  analysiere.value = true
  fehler.value = ''
  info.value = ''

  const docs = await dokumenteVorbereiten()
  const prompt = eingabe.value.trim() || 'Analysiere die Anhänge und erstelle präzise, kleine umsetzbare Vorschläge.'
  const body = {
    prompt,
    lager: {
      id: props.lagerId,
      name: props.lagerName,
      jahr: props.lagerJahr,
      status: props.lagerStatus,
      start_datum: props.startDatum,
      end_datum: props.endDatum,
      ort: props.ort,
    },
    docs,
  }

  const { data, error } = await supabase.functions.invoke('lager-gemini-assistant', { body })
  if (error) {
    analysiere.value = false
    fehler.value = error.message
    return
  }

  const proposals = (data?.proposals ?? []) as Array<{
    title: string
    description: string | null
    action_type: ActionType
    payload: Record<string, unknown>
  }>
  if (!proposals.length) {
    analysiere.value = false
    info.value = 'Keine konkreten Vorschläge erkannt.'
    return
  }

  const quelleDokumente = docs.map((d) => ({ name: d.name, mimeType: d.mimeType }))
  const userId = session.value?.user.id
  if (!userId) {
    analysiere.value = false
    fehler.value = 'Session fehlt. Bitte neu einloggen.'
    return
  }
  const { error: insErr } = await supabase.from('lager_ai_vorschlaege').insert(
    proposals.map((p) => ({
      lager_id: props.lagerId,
      organisation_id: props.organisationId,
      erstellt_von: userId,
      quelle_prompt: prompt,
      quelle_dokumente: quelleDokumente,
      titel: p.title,
      beschreibung: p.description,
      action_type: p.action_type,
      payload: p.payload,
      status: 'offen',
    })),
  )

  analysiere.value = false
  if (insErr) {
    fehler.value = insErr.message
    return
  }
  info.value = data?.summary ?? `${proposals.length} Vorschläge erstellt.`
  await laden()
}

function istLeerWert(v: unknown) {
  return v == null || (typeof v === 'string' && v.trim() === '')
}

function fehlendePflichtfelder(action: ActionType, payload: Record<string, unknown>): string[] {
  const fehlt = (key: string) => istLeerWert(payload[key])
  if (action === 'insert_tn') {
    return ['vorname', 'nachname', 'geburtsdatum', 'notfallkontakt', 'eltern_email'].filter(fehlt)
  }
  if (action === 'insert_leiter') {
    return ['vorname', 'nachname'].filter(fehlt)
  }
  if (action === 'update_programmblock' || action === 'delete_programmblock' || action === 'update_tn' || action === 'update_leiter' || action === 'update_lager_todo') {
    return ['id'].filter(fehlt)
  }
  if (action === 'assign_leiter_aemtli') {
    const missing = ['anmeldung_leiter_id'].filter(fehlt)
    if (fehlt('aemtli_id') && fehlt('aemtli_name')) missing.push('aemtli_id|aemtli_name')
    return missing
  }
  if (action === 'assign_gruppenmitglied') {
    return ['lagergruppe_id', 'typ', 'anmeldung_id'].filter(fehlt)
  }
  return []
}

async function annehmen(v: GeminiVorschlag) {
  fehler.value = ''
  info.value = ''
  aktionLade.value[v.id] = true
  let payload: Record<string, unknown> | null = null
  try {
    payload = JSON.parse(payloadEdit.value[v.id] ?? '{}')
  } catch {
    aktionLade.value[v.id] = false
    fehler.value = 'Payload-JSON ist ungültig.'
    return
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    aktionLade.value[v.id] = false
    fehler.value = 'Payload muss ein JSON-Objekt sein.'
    return
  }
  const missing = fehlendePflichtfelder(v.action_type, payload)
  if (missing.length) {
    aktionLade.value[v.id] = false
    fehler.value = `Unvollständiger Vorschlag (${v.action_type}): ${missing.join(', ')} fehlt. Bitte Payload bearbeiten oder ablehnen.`
    return
  }
  const { error } = await supabase.rpc('lager_ai_vorschlag_annehmen', {
    p_vorschlag_id: v.id,
    p_payload_override: payload,
  })
  aktionLade.value[v.id] = false
  if (error) {
    fehler.value = `${error.message} (Tipp: Payload prüfen/ergänzen, dann erneut annehmen.)`
    return
  }
  const idx = vorschlaege.value.findIndex((x) => x.id === v.id)
  if (idx >= 0) vorschlaege.value[idx].status = 'angenommen'
  zuletztAngenommenId.value = v.id
  setTimeout(() => {
    if (zuletztAngenommenId.value === v.id) zuletztAngenommenId.value = null
  }, 2200)
  info.value = 'Vorschlag angenommen und angewendet.'
  emit('applied', v.action_type)
  await laden()
}

async function ablehnen(v: GeminiVorschlag) {
  fehler.value = ''
  info.value = ''
  aktionLade.value[v.id] = true
  const { error } = await supabase.rpc('lager_ai_vorschlag_ablehnen', {
    p_vorschlag_id: v.id,
    p_notiz: null,
  })
  aktionLade.value[v.id] = false
  if (error) {
    fehler.value = error.message
    return
  }
  info.value = 'Vorschlag abgelehnt.'
  await laden()
}

onMounted(laden)
</script>

<template>
  <section>
    <h2>Gemini Assistant (Lalei)</h2>
    <p class="hint">
      Der Assistant erstellt Vorschläge und kann nach Bestätigung Aktionen ausführen
      (z.B. Programm, TN/Leiter, Gruppen, Todos). Nichts passiert ohne Bestätigung pro Karte.
    </p>

    <div class="karte">
      <label>
        Eingabe
        <textarea
          v-model="eingabe"
          rows="5"
          placeholder="z.B. 'Übernimm aus PDF das Grobprogramm und erstelle 5 Programmblöcke'"
        />
      </label>
      <label>Dateien (PDF/Bilder/Text/Excel)</label>
      <div
        class="dropzone"
        :class="{ aktiv: dragAktiv }"
        @dragover="onDragOver"
        @dragenter.prevent="dragAktiv = true"
        @dragleave="onDragLeave"
        @drop="onDrop"
      >
        <p>Dateien hierhin ziehen oder auswählen</p>
        <input type="file" multiple accept=".pdf,image/*,.txt,.md,.csv,.xlsx,.xls" @change="onDateien" />
      </div>
      <p v-if="dateien.length" class="hint">Anhänge: {{ dateien.map((f) => f.name).join(', ') }}</p>
      <button :disabled="analysiere || !kannAnalysieren" @click="analysieren">
        {{ analysiere ? 'Analysiere…' : 'Mit Gemini analysieren' }}
      </button>
    </div>

    <div class="kopf">
      <h3>Vorschläge ({{ offene.length }} offen / {{ vorschlaege.length }} total)</h3>
      <button class="secondary klein" :disabled="ladeListe" @click="laden">{{ ladeListe ? 'Lade…' : 'Aktualisieren' }}</button>
    </div>

    <article
      v-for="v in vorschlaege"
      :key="v.id"
      class="vorschlag-karte"
      :class="[v.status, { 'frisch-angenommen': zuletztAngenommenId === v.id }]"
    >
      <header class="vorschlag-kopf">
        <div>
          <strong>{{ v.titel }}</strong>
          <p class="meta">
            {{ prettyAction(v.action_type) }} · {{ v.status }} · {{ new Date(v.created_at).toLocaleString('de-CH') }}
            <span v-if="v.status === 'angenommen'" class="ok-chip">✓ bestätigt</span>
          </p>
        </div>
        <div class="aktionen">
          <button v-if="v.status === 'offen'" :disabled="aktionLade[v.id]" @click="annehmen(v)">
            {{ aktionLade[v.id] ? '...' : 'Annehmen' }}
          </button>
          <button v-if="v.status === 'offen'" class="secondary" :disabled="aktionLade[v.id]" @click="ablehnen(v)">
            Ablehnen
          </button>
          <button v-if="v.status === 'offen'" class="secondary" @click="imEditModus[v.id] = !imEditModus[v.id]">
            {{ imEditModus[v.id] ? 'Fertig' : 'Bearbeiten' }}
          </button>
        </div>
      </header>

      <p v-if="v.beschreibung" class="beschreibung">{{ v.beschreibung }}</p>
      <p v-if="v.last_error" class="error">{{ v.last_error }}</p>

      <textarea
        v-model="payloadEdit[v.id]"
        rows="10"
        class="payload"
        :readonly="v.status !== 'offen' || !imEditModus[v.id]"
      />
    </article>

    <p v-if="!vorschlaege.length && !ladeListe" class="hint">Noch keine Vorschläge vorhanden.</p>
    <p v-if="info" class="ok">{{ info }}</p>
    <p v-if="fehler" class="error">{{ fehler }}</p>
  </section>
</template>

<style scoped>
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.karte {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 0.9rem 1rem;
  margin: 0.8rem 0 1rem;
}
label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.84rem; color: var(--color-text-muted); margin-bottom: 0.65rem; }
textarea.payload { width: 100%; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.78rem; }
.dropzone {
  border: 1px dashed var(--color-border);
  border-radius: var(--radius-md);
  padding: 0.7rem 0.8rem;
  background: var(--color-surface);
}
.dropzone.aktiv {
  border-color: var(--color-accent);
  background: var(--color-surface-muted);
}
.dropzone p { margin: 0 0 0.4rem; font-size: 0.82rem; color: var(--color-text-muted); }
.kopf { display: flex; justify-content: space-between; align-items: center; gap: 0.6rem; margin-top: 0.9rem; }
.vorschlag-karte {
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 0.75rem 0.9rem;
  margin-top: 0.7rem;
  background: var(--color-surface);
}
.vorschlag-karte.angenommen { border-color: #2e7d32; }
.vorschlag-karte.abgelehnt { border-color: #9e9e9e; opacity: 0.85; }
.vorschlag-karte.frisch-angenommen { animation: akzeptiert 1s ease-out 1; }
.vorschlag-kopf { display: flex; justify-content: space-between; gap: 0.6rem; align-items: flex-start; }
.meta { margin: 0.2rem 0 0; font-size: 0.78rem; color: var(--color-text-muted); }
.ok-chip {
  display: inline-flex;
  align-items: center;
  margin-left: 0.4rem;
  background: rgba(46, 125, 50, 0.14);
  color: #2e7d32;
  border-radius: var(--radius-pill);
  padding: 0.08rem 0.42rem;
  font-size: 0.72rem;
}
.aktionen { display: flex; gap: 0.45rem; flex-wrap: wrap; }
.beschreibung { margin: 0.55rem 0; font-size: 0.88rem; }
.ok { color: #2e7d32; margin-top: 0.8rem; }
.error { color: var(--color-danger); margin-top: 0.8rem; }
button.klein { font-size: 0.8rem; padding: 0.3rem 0.55rem; }

@keyframes akzeptiert {
  0% { box-shadow: 0 0 0 rgba(46, 125, 50, 0); }
  20% { box-shadow: 0 0 0 4px rgba(46, 125, 50, 0.18); }
  100% { box-shadow: 0 0 0 rgba(46, 125, 50, 0); }
}
</style>
