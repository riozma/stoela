<script setup lang="ts">
import { computed, ref, type Ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { extractPdfPages } from '../../lib/pdfText'
import { synchronisiereProgrammZuordnungen } from '../../lib/programmZuordnung'

interface Block {
  code: 'LP' | 'LS' | 'LA' | 'ES'
  nummer: string | null
  titel: string
  tag: string | null
  start_zeit: string | null
  end_zeit: string | null
  ort: string | null
  verantwortlich: string | null
}

interface Extraktion {
  bloecke: Block[]
}

class GeminiFehler extends Error {
  code?: string
  constructor(message: string, code?: string) {
    super(message)
    this.code = code
  }
}

const props = defineProps<{ lagerId: string }>()
const emit = defineEmits<{ imported: [] }>()

const SEITEN_PRO_HAPPEN = 8
const GLEICHZEITIGE_ANFRAGEN = 2

const status = ref<'idle' | 'analysiere' | 'bereit' | 'importiere'>('idle')
const fehler = ref('')
const info = ref('')
const fortschritt = ref({ phase: '', aktuell: 0, total: 0 })
const kandidaten = ref<Block[]>([])
const neueBloecke = ref<Block[]>([])
const doppelteAnzahl = ref(0)

const balkenBreite = computed(() =>
  fortschritt.value.total
    ? Math.min(100, Math.round((fortschritt.value.aktuell / fortschritt.value.total) * 100))
    : 0,
)
// ES (Essen) bewusst ausgeschlossen – Mahlzeiten trägt die Küche selbst ein (Menüplaner).
const ERLAUBTE_CODES = new Set(['LP', 'LS', 'LA'])

function zeitSignatur(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  if (!Number.isNaN(d.getTime())) return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
  const match = iso.match(/(\d{2}:\d{2})/)
  return match?.[1] ?? iso
}

function blockSignatur(b: Pick<Block, 'code' | 'nummer' | 'titel' | 'tag' | 'start_zeit'>): string {
  return [
    b.code,
    (b.nummer ?? '').trim().toLowerCase(),
    b.titel.trim().toLowerCase(),
    b.tag ?? '',
    zeitSignatur(b.start_zeit),
  ].join('|')
}

function dedupliziereLokal(bloecke: Block[]): Block[] {
  const seen = new Set<string>()
  const result: Block[] = []
  for (const b of bloecke) {
    const key = blockSignatur(b)
    if (seen.has(key)) continue
    seen.add(key)
    result.push(b)
  }
  return result
}

async function rufeGeminiAuf(text: string): Promise<Extraktion> {
  const { data, error: fnError } = await supabase.functions.invoke('parse-lager-pdf', {
    body: { text, modus: 'grob' },
  })

  if (fnError) {
    let message = fnError.message ?? 'Analyse fehlgeschlagen.'
    let code: string | undefined
    try {
      const body = await (fnError as any).context?.json()
      if (body?.error) message = body.error
      if (body?.code) code = body.code
    } catch {
      // ignore
    }
    throw new GeminiFehler(message, code)
  }
  if (data?.error) throw new GeminiFehler(data.error, data.code)
  return data as Extraktion
}

async function analysiereHaeppchenweise(
  seitenGruppen: string[][],
  titelseite: string,
  gesamtSeiten: number,
  fortschrittRef: Ref<{ phase: string; aktuell: number; total: number }>,
): Promise<Block[]> {
  const bloecke: Block[] = []
  let verarbeiteteSeiten = 0
  const queue = [...seitenGruppen]

  async function worker() {
    while (queue.length) {
      const gruppe = queue.shift()
      if (!gruppe) return
      try {
        const teil = await rufeGeminiAuf(titelseite + '\n\n' + gruppe.join('\n\n'))
        bloecke.push(...(teil.bloecke ?? []))
        verarbeiteteSeiten += gruppe.length
        fortschrittRef.value = {
          phase: `Analysiere Grobprogramm (${verarbeiteteSeiten}/${gesamtSeiten})...`,
          aktuell: verarbeiteteSeiten,
          total: gesamtSeiten,
        }
      } catch (e) {
        if (e instanceof GeminiFehler && e.code === 'MAX_TOKENS' && gruppe.length > 1) {
          const mitte = Math.ceil(gruppe.length / 2)
          queue.unshift(gruppe.slice(mitte))
          queue.unshift(gruppe.slice(0, mitte))
          continue
        }
        throw e
      }
    }
  }

  await Promise.all(Array.from({ length: GLEICHZEITIGE_ANFRAGEN }, worker))
  return dedupliziereLokal(bloecke)
}

async function bereitsVorhandeneSignaturen(): Promise<Set<string>> {
  const { data } = await supabase
    .from('programmbloecke')
    .select('code, nummer, titel, tag, start_zeit')
    .eq('lager_id', props.lagerId)

  const set = new Set<string>()
  for (const row of data ?? []) {
    set.add(blockSignatur(row as Pick<Block, 'code' | 'nummer' | 'titel' | 'tag' | 'start_zeit'>))
  }
  return set
}

async function dateiGewaehlt(event: Event) {
  fehler.value = ''
  info.value = ''
  kandidaten.value = []
  neueBloecke.value = []
  doppelteAnzahl.value = 0
  const file = (event.target as HTMLInputElement).files?.[0]
  if (!file) return

  try {
    status.value = 'analysiere'
    fortschritt.value = { phase: 'Lese PDF...', aktuell: 0, total: 0 }
    const seiten = await extractPdfPages(file, (seite, total) => {
      fortschritt.value = { phase: `Lese PDF (${seite}/${total})...`, aktuell: seite, total }
    })

    const titelseite = seiten[0] ?? ''
    const detailIdx = seiten.findIndex((s) => s.includes('Detailprogramm'))
    const relevanteSeiten = detailIdx >= 0 ? seiten.slice(detailIdx) : seiten
    const gruppen: string[][] = []
    for (let i = 0; i < relevanteSeiten.length; i += SEITEN_PRO_HAPPEN) {
      gruppen.push(relevanteSeiten.slice(i, i + SEITEN_PRO_HAPPEN))
    }
    if (gruppen.length === 0) gruppen.push([])

    kandidaten.value = (await analysiereHaeppchenweise(gruppen, titelseite, relevanteSeiten.length, fortschritt))
      .filter((b) => ERLAUBTE_CODES.has(b.code) && b.titel?.trim())
    const vorhanden = await bereitsVorhandeneSignaturen()

    neueBloecke.value = kandidaten.value.filter((b) => !vorhanden.has(blockSignatur(b)))
    doppelteAnzahl.value = kandidaten.value.length - neueBloecke.value.length
    status.value = 'bereit'
    info.value = `${kandidaten.value.length} Blöcke erkannt · ${neueBloecke.value.length} neu · ${doppelteAnzahl.value} bereits vorhanden`
  } catch (e) {
    fehler.value = e instanceof Error ? e.message : 'PDF konnte nicht verarbeitet werden.'
    status.value = 'idle'
  }
}

async function importieren() {
  if (!neueBloecke.value.length) {
    info.value = 'Keine neuen Blöcke zum Importieren.'
    return
  }
  status.value = 'importiere'
  fehler.value = ''

  const rows = neueBloecke.value.map((b) => ({
    lager_id: props.lagerId,
    code: b.code,
    nummer: b.nummer,
    titel: b.titel,
    tag: b.tag,
    start_zeit: b.start_zeit,
    end_zeit: b.end_zeit,
    ort: b.ort,
    verantwortlich: b.verantwortlich,
    geschichte: null,
    sicherheitsueberlegungen: null,
    programmabschnitt: [],
    material: [],
    notizen: null,
    verantwortlich_zuordnungen: [],
    quelle: 'ecamp_pdf',
  }))

  const { error } = await supabase.from('programmbloecke').insert(rows)
  if (error) {
    status.value = 'bereit'
    fehler.value = error.message
    return
  }

  await synchronisiereProgrammZuordnungen(props.lagerId)
  info.value = `${rows.length} neue Blöcke importiert.`
  status.value = 'idle'
  kandidaten.value = []
  neueBloecke.value = []
  doppelteAnzahl.value = 0
  emit('imported')
}
</script>

<template>
  <section class="import-panel">
    <h4>Grobprogramm aus eCamp importieren</h4>
    <p class="hint">
      Wenn noch kein Programm geladen ist, kannst du hier das eCamp-PDF hochladen.
      Bereits vorhandene Blöcke werden automatisch erkannt und nicht doppelt importiert.
    </p>
    <input
      type="file"
      accept="application/pdf"
      :disabled="status === 'analysiere' || status === 'importiere'"
      @change="dateiGewaehlt"
    />

    <div v-if="status === 'analysiere'" class="fortschritt">
      <p>{{ fortschritt.phase }}</p>
      <div class="balken">
        <div class="balken-fuellung" :style="{ width: `${balkenBreite}%` }" />
      </div>
    </div>

    <p v-if="info" class="ok">{{ info }}</p>
    <p v-if="fehler" class="error">{{ fehler }}</p>

    <button
      v-if="status === 'bereit'"
      type="button"
      :disabled="!neueBloecke.length"
      @click="importieren"
    >
      {{ `Neue Blöcke importieren (${neueBloecke.length})` }}
    </button>
  </section>
</template>

<style scoped>
.import-panel {
  margin-bottom: 1rem;
  padding: 0.9rem 1rem;
  border: 1px dashed var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface);
}
.import-panel h4 { margin: 0 0 0.35rem; }
.hint { color: var(--color-text-muted); font-size: 0.85rem; margin: 0 0 0.6rem; }
.fortschritt { margin: 0.75rem 0; }
.balken { width: 100%; height: 8px; background: var(--color-surface-muted); border-radius: var(--radius-pill); overflow: hidden; }
.balken-fuellung { height: 100%; background: var(--color-accent); }
.ok { color: #2e7d32; margin: 0.5rem 0; }
.error { color: var(--color-danger); margin: 0.5rem 0; }
</style>
