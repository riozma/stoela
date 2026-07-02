<script setup lang="ts">
import { computed, ref, type Ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
import { extractPdfPages } from '../lib/pdfText'
import { synchronisiereProgrammZuordnungen } from '../lib/programmZuordnung'

interface Programmabschnitt {
  zeit: string | null
  programm: string
  verantwortlich: string | null
}
interface MaterialItem {
  name: string
  wer: string | null
}
interface Block {
  code: 'LP' | 'LS' | 'LA' | 'ES'
  nummer: string | null
  titel: string
  tag: string | null
  start_zeit: string | null
  end_zeit: string | null
  ort: string | null
  verantwortlich: string | null
  geschichte: string | null
  sicherheitsueberlegungen: string | null
  programmabschnitt: Programmabschnitt[]
  material: MaterialItem[]
  notizen: string | null
}
interface LagerMeta {
  name: string
  jahr: number
  ort?: string
  start_datum?: string
  end_datum?: string
}
interface Extraktion {
  lager: LagerMeta
  bloecke: Block[]
}
class GeminiFehler extends Error {
  code?: string
  constructor(message: string, code?: string) {
    super(message)
    this.code = code
  }
}

const SEITEN_PRO_HAPPEN = 8
const GLEICHZEITIGE_ANFRAGEN = 2

const router = useRouter()
const { session } = useAuth()

const status = ref<'idle' | 'verarbeite' | 'bereit' | 'importiere' | 'fertig'>('idle')
const fortschritt = ref({ phase: '', aktuell: 0, total: 0 })
const error = ref('')
const ergebnis = ref<Extraktion | null>(null)
const offenerBlock = ref<number | null>(null)

const balkenBreite = computed(() =>
  fortschritt.value.total ? Math.round((fortschritt.value.aktuell / fortschritt.value.total) * 100) : 0,
)

const statistik = computed(() => {
  if (!ergebnis.value) return null
  const bloecke = ergebnis.value.bloecke
  return {
    bloecke: bloecke.length,
    mitMaterial: bloecke.filter((b) => b.material?.length).length,
    materialZeilen: bloecke.reduce((s, b) => s + (b.material?.length ?? 0), 0),
    mitAbschnitten: bloecke.filter((b) => b.programmabschnitt?.length).length,
    mitVerantwortlich: bloecke.filter((b) => b.verantwortlich?.trim()).length,
  }
})

async function rufeGeminiAuf(text: string): Promise<Extraktion> {
  const { data, error: fnError } = await supabase.functions.invoke('parse-lager-pdf', { body: { text } })

  if (fnError) {
    let message = fnError.message ?? 'Unbekannter Fehler bei der Analyse.'
    let code: string | undefined
    try {
      const body = await (fnError as any).context?.json()
      if (body?.error) message = body.error
      if (body?.code) code = body.code
    } catch { /* ignore */ }
    throw new GeminiFehler(message, code)
  }
  if (data?.error) throw new GeminiFehler(data.error, data.code)

  return data as Extraktion
}

function dedupliziereBloecke(bloecke: Block[]): Block[] {
  const seen = new Set<string>()
  const result: Block[] = []
  for (const b of bloecke) {
    const key = [b.code, b.nummer, b.titel, b.tag, b.start_zeit].join('|')
    if (seen.has(key)) continue
    seen.add(key)
    result.push(b)
  }
  return result
}

async function analysiereHaeppchenweise(
  seitenGruppen: string[][],
  titelseite: string,
  gesamtSeiten: number,
  fortschrittRef: Ref<{ phase: string; aktuell: number; total: number }>,
): Promise<{ lager: LagerMeta | null; bloecke: Block[] }> {
  let lager: LagerMeta | null = null
  const bloecke: Block[] = []
  let verarbeiteteSeiten = 0

  const queue = [...seitenGruppen]

  async function worker() {
    while (queue.length) {
      const gruppe = queue.shift()
      if (!gruppe) return
      try {
        const teil = await rufeGeminiAuf(titelseite + '\n\n' + gruppe.join('\n\n'))
        if (!lager && teil.lager?.jahr) lager = teil.lager
        bloecke.push(...(teil.bloecke ?? []))
        verarbeiteteSeiten += gruppe.length
        fortschrittRef.value = {
          phase: `Analysiere Programm (${verarbeiteteSeiten} von ${gesamtSeiten} Seiten)...`,
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

  return { lager, bloecke: dedupliziereBloecke(bloecke) }
}

async function dateiGewaehlt(e: Event) {
  error.value = ''
  ergebnis.value = null
  offenerBlock.value = null
  const file = (e.target as HTMLInputElement).files?.[0]
  if (!file) return

  try {
    status.value = 'verarbeite'
    fortschritt.value = { phase: 'Lese PDF...', aktuell: 0, total: 0 }

    const seiten = await extractPdfPages(file, (seite, total) => {
      fortschritt.value = { phase: `Lese PDF (Seite ${seite}/${total})...`, aktuell: seite, total }
    })

    const titelseite = seiten[0] ?? ''
    const detailIdx = seiten.findIndex((s) => s.includes('Detailprogramm'))
    const relevanteSeiten = detailIdx >= 0 ? seiten.slice(detailIdx) : seiten

    const gruppen: string[][] = []
    for (let i = 0; i < relevanteSeiten.length; i += SEITEN_PRO_HAPPEN) {
      gruppen.push(relevanteSeiten.slice(i, i + SEITEN_PRO_HAPPEN))
    }
    if (gruppen.length === 0) gruppen.push([])

    const { lager, bloecke } = await analysiereHaeppchenweise(
      gruppen,
      titelseite,
      relevanteSeiten.length,
      fortschritt,
    )

    fortschritt.value = { phase: 'Analyse abgeschlossen.', aktuell: relevanteSeiten.length, total: relevanteSeiten.length }

    if (!lager) throw new Error('Lager-Titelseite konnte nicht erkannt werden.')
    ergebnis.value = { lager, bloecke }
    status.value = 'bereit'
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'PDF konnte nicht verarbeitet werden.'
    status.value = 'idle'
  }
}

function toggleBlock(i: number) {
  offenerBlock.value = offenerBlock.value === i ? null : i
}

async function importieren() {
  if (!ergebnis.value || !session.value) return
  error.value = ''
  status.value = 'importiere'

  const { lager, bloecke } = ergebnis.value

  const { data: neuesLager, error: lagerError } = await supabase
    .from('lager')
    .insert({
      name: lager.name,
      jahr: lager.jahr,
      ort: lager.ort ?? null,
      start_datum: lager.start_datum ?? null,
      end_datum: lager.end_datum ?? null,
      status: 'anmeldung_offen',
      created_by: session.value.user.id,
    })
    .select('id')
    .single()

  if (lagerError || !neuesLager) {
    error.value = lagerError?.message ?? 'Lager konnte nicht erstellt werden.'
    status.value = 'bereit'
    return
  }

  await supabase.from('lager_leiter').insert({
    lager_id: neuesLager.id,
    profile_id: session.value.user.id,
    rolle: 'lagerleitung',
    status: 'bestaetigt',
  })

  if (bloecke.length) {
    const rows = bloecke.map((b) => ({
      lager_id: neuesLager.id,
      code: b.code,
      nummer: b.nummer,
      titel: b.titel,
      tag: b.tag,
      start_zeit: b.start_zeit,
      end_zeit: b.end_zeit,
      ort: b.ort,
      verantwortlich: b.verantwortlich,
      geschichte: b.geschichte,
      sicherheitsueberlegungen: b.sicherheitsueberlegungen,
      programmabschnitt: b.programmabschnitt ?? [],
      material: b.material ?? [],
      notizen: b.notizen,
      verantwortlich_zuordnungen: [],
      quelle: 'ecamp_pdf',
    }))
    const { error: bloeckeError } = await supabase.from('programmbloecke').insert(rows)
    if (bloeckeError) {
      error.value = `Lager wurde erstellt, aber Blöcke konnten nicht gespeichert werden: ${bloeckeError.message}`
      status.value = 'bereit'
      return
    }

    await synchronisiereProgrammZuordnungen(neuesLager.id)
  }

  status.value = 'fertig'
  router.push(`/lager/${neuesLager.id}`)
}
</script>

<template>
  <main>
    <h1>Lager aus eCamp-PDF importieren</h1>
    <p class="hint">
      In eCamp: Admin → Drucken → Layout 2 → PDF exportieren. Gemini extrahiert Titel, Ort,
      Verantwortliche, Sicherheitsüberlegungen, Programmabschnitte, Material und Notizen je Block.
    </p>

    <input type="file" accept="application/pdf" @change="dateiGewaehlt" :disabled="status === 'verarbeite'" />

    <div v-if="status === 'verarbeite'" class="fortschritt">
      <p>{{ fortschritt.phase }}</p>
      <div class="balken">
        <div class="balken-fuellung" :style="{ width: balkenBreite + '%' }"></div>
      </div>
    </div>

    <p v-if="error" class="error">{{ error }}</p>

    <section v-if="ergebnis">
      <h2>{{ ergebnis.lager.name }}</h2>
      <ul class="lager-info">
        <li>Jahr: {{ ergebnis.lager.jahr }}</li>
        <li v-if="ergebnis.lager.ort">Ort: {{ ergebnis.lager.ort }}</li>
        <li v-if="ergebnis.lager.start_datum">
          {{ ergebnis.lager.start_datum }} – {{ ergebnis.lager.end_datum }}
        </li>
      </ul>

      <div v-if="statistik" class="stats">
        <span>{{ statistik.bloecke }} Blöcke</span>
        <span>{{ statistik.materialZeilen }} Materialzeilen</span>
        <span>{{ statistik.mitAbschnitten }} mit Programmabschnitten</span>
      </div>

      <p class="hint zuordnung-hinweis">
        Nach dem Import werden Verantwortliche und Material «wer» automatisch mit Leitern und Ämtli
        abgeglichen, sobald diese im Lager erfasst sind. Nicht zuordenbare Namen bleiben unzugeordnet.
      </p>

      <div class="bloecke-liste">
        <article v-for="(b, i) in ergebnis.bloecke" :key="i" class="block-karte">
          <header @click="toggleBlock(i)">
            <strong>{{ b.code }}{{ b.nummer ? ' ' + b.nummer : '' }}</strong>
            {{ b.titel }}
            <span class="datum">{{ b.tag }}</span>
            <span class="toggle">{{ offenerBlock === i ? '▾' : '▸' }}</span>
          </header>

          <div v-if="offenerBlock === i" class="block-detail">
            <p v-if="b.ort"><strong>Ort:</strong> {{ b.ort }}</p>
            <p v-if="b.verantwortlich"><strong>Verantwortlich:</strong> {{ b.verantwortlich }}</p>
            <p v-if="b.sicherheitsueberlegungen"><strong>Sicherheitsüberlegungen:</strong> {{ b.sicherheitsueberlegungen }}</p>
            <p v-if="b.geschichte"><strong>Geschichte:</strong> {{ b.geschichte }}</p>

            <div v-if="b.programmabschnitt?.length">
              <strong>Programmabschnitt</strong>
              <table class="mini-tabelle">
                <tbody>
                  <tr v-for="(a, j) in b.programmabschnitt" :key="j">
                    <td>{{ a.zeit ?? '–' }}</td>
                    <td>{{ a.programm }}</td>
                    <td>{{ a.verantwortlich ?? '–' }}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div v-if="b.material?.length">
              <strong>Material ({{ b.material.length }})</strong>
              <ul>
                <li v-for="(m, j) in b.material" :key="j">
                  {{ m.name }}<span v-if="m.wer"> – {{ m.wer }}</span>
                </li>
              </ul>
            </div>

            <p v-if="b.notizen"><strong>Notizen:</strong> {{ b.notizen }}</p>
          </div>
        </article>
      </div>

      <button @click="importieren" :disabled="status === 'importiere'">
        {{ status === 'importiere' ? 'Importiere...' : 'Lager erstellen und Blöcke importieren' }}
      </button>
    </section>
  </main>
</template>

<style scoped>
main { max-width: 720px; margin: 2rem auto; padding: 0 1rem; }
.hint { color: var(--color-text-muted); font-size: 0.9rem; }
.zuordnung-hinweis { margin: 0.75rem 0 1rem; padding: 0.65rem 0.85rem; background: var(--color-surface-muted); border-radius: var(--radius-md); }
.fortschritt { margin: 1rem 0; }
.fortschritt p { font-size: 0.9rem; color: var(--color-text-muted); margin-bottom: 0.4rem; }
.balken { width: 100%; height: 8px; background: var(--color-surface-muted); border-radius: var(--radius-pill); overflow: hidden; }
.balken-fuellung { height: 100%; background: var(--color-accent); transition: width 0.2s ease; }
.lager-info { list-style: none; padding: 0; color: var(--color-text-muted); }
.stats { display: flex; flex-wrap: wrap; gap: 0.75rem; font-size: 0.85rem; margin: 0.75rem 0; }
.stats span { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-pill); padding: 0.2rem 0.65rem; }
.bloecke-liste { max-height: 480px; overflow-y: auto; margin: 1rem 0; }
.block-karte { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); margin-bottom: 0.5rem; overflow: hidden; }
.block-karte header { display: flex; flex-wrap: wrap; align-items: center; gap: 0.4rem; padding: 0.55rem 0.85rem; cursor: pointer; font-size: 0.9rem; }
.block-karte header:hover { background: var(--color-surface-muted); }
.datum { color: var(--color-text-muted); font-size: 0.82rem; margin-left: auto; }
.toggle { color: var(--color-text-muted); }
.block-detail { padding: 0.65rem 0.85rem 0.85rem; font-size: 0.88rem; border-top: 1px solid var(--color-border); background: var(--color-surface-muted); }
.block-detail p { margin: 0.35rem 0; }
.mini-tabelle { width: 100%; border-collapse: collapse; font-size: 0.82rem; margin: 0.4rem 0; }
.mini-tabelle td { padding: 0.25rem 0.5rem 0.25rem 0; border-bottom: 1px solid var(--color-border); vertical-align: top; }
.block-detail ul { margin: 0.35rem 0; padding-left: 1.2rem; }
.error { color: var(--color-danger); }
</style>
