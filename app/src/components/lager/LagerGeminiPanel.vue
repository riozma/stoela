<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { extractPdfPages } from '../../lib/pdfText'
import { useAuth } from '../../composables/useAuth'

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

const offene = computed(() => vorschlaege.value.filter((v) => v.status === 'offen'))

function onDateien(event: Event) {
  const target = event.target as HTMLInputElement
  dateien.value = Array.from(target.files ?? [])
}

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
  }
  return map[action]
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
    if (isPdf) {
      const seiten = await extractPdfPages(f)
      docs.push({
        name: f.name,
        mimeType: 'application/pdf',
        text: seiten.join('\n\n').slice(0, 70000),
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
  if (!eingabe.value.trim()) return
  analysiere.value = true
  fehler.value = ''
  info.value = ''

  const docs = await dokumenteVorbereiten()
  const body = {
    prompt: eingabe.value.trim(),
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
      quelle_prompt: eingabe.value.trim(),
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
  const { error } = await supabase.rpc('lager_ai_vorschlag_annehmen', {
    p_vorschlag_id: v.id,
    p_payload_override: payload,
  })
  aktionLade.value[v.id] = false
  if (error) {
    fehler.value = error.message
    return
  }
  info.value = 'Vorschlag angenommen und angewendet.'
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
    <h2>Gemini Assistent (Lalei)</h2>
    <p class="hint">
      Gib Text, PDFs oder Bilder ein. Gemini erstellt nur Vorschläge – jede Änderung muss unten
      einzeln angenommen, abgelehnt oder bearbeitet werden.
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
      <label>
        Dateien (PDF/Bilder/Text)
        <input type="file" multiple accept=".pdf,image/*,.txt,.md" @change="onDateien" />
      </label>
      <p v-if="dateien.length" class="hint">Anhänge: {{ dateien.map((f) => f.name).join(', ') }}</p>
      <button :disabled="analysiere || !eingabe.trim()" @click="analysieren">
        {{ analysiere ? 'Analysiere…' : 'Mit Gemini analysieren' }}
      </button>
    </div>

    <div class="kopf">
      <h3>Vorschläge ({{ offene.length }} offen / {{ vorschlaege.length }} total)</h3>
      <button class="secondary klein" :disabled="ladeListe" @click="laden">{{ ladeListe ? 'Lade…' : 'Aktualisieren' }}</button>
    </div>

    <article v-for="v in vorschlaege" :key="v.id" class="vorschlag-karte" :class="v.status">
      <header class="vorschlag-kopf">
        <div>
          <strong>{{ v.titel }}</strong>
          <p class="meta">{{ prettyAction(v.action_type) }} · {{ v.status }} · {{ new Date(v.created_at).toLocaleString('de-CH') }}</p>
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
.vorschlag-kopf { display: flex; justify-content: space-between; gap: 0.6rem; align-items: flex-start; }
.meta { margin: 0.2rem 0 0; font-size: 0.78rem; color: var(--color-text-muted); }
.aktionen { display: flex; gap: 0.45rem; flex-wrap: wrap; }
.beschreibung { margin: 0.55rem 0; font-size: 0.88rem; }
.ok { color: #2e7d32; margin-top: 0.8rem; }
.error { color: var(--color-danger); margin-top: 0.8rem; }
button.klein { font-size: 0.8rem; padding: 0.3rem 0.55rem; }
</style>
