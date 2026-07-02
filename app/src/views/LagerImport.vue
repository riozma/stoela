<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
import { extractPdfPages } from '../lib/pdfText'

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

// Grösse der Text-Häppchen, die pro Gemini-Aufruf verarbeitet werden. Bei zu
// grossen PDFs (viele Blöcke mit viel Text) würde eine einzige Anfrage die
// Antwortlänge sprengen und mit abgeschnittenem/kaputtem JSON zurückkommen.
const SEITEN_PRO_HAPPEN = 6

const router = useRouter()
const { session } = useAuth()

const status = ref<'idle' | 'verarbeite' | 'bereit' | 'importiere' | 'fertig'>('idle')
const fortschritt = ref({ phase: '', aktuell: 0, total: 0 })
const error = ref('')
const ergebnis = ref<Extraktion | null>(null)

const balkenBreite = computed(() =>
  fortschritt.value.total ? Math.round((fortschritt.value.aktuell / fortschritt.value.total) * 100) : 0,
)

async function dateiGewaehlt(e: Event) {
  error.value = ''
  ergebnis.value = null
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

    const happen: string[] = []
    for (let i = 0; i < relevanteSeiten.length; i += SEITEN_PRO_HAPPEN) {
      happen.push(titelseite + '\n\n' + relevanteSeiten.slice(i, i + SEITEN_PRO_HAPPEN).join('\n\n'))
    }
    if (happen.length === 0) happen.push(titelseite)

    let lager: LagerMeta | null = null
    const bloecke: Block[] = []

    for (let i = 0; i < happen.length; i++) {
      fortschritt.value = {
        phase: `Analysiere Programm (Teil ${i + 1} von ${happen.length})...`,
        aktuell: i,
        total: happen.length,
      }
      const { data, error: fnError } = await supabase.functions.invoke('parse-lager-pdf', {
        body: { text: happen[i] },
      })
      if (fnError) throw fnError
      if (data?.error) throw new Error(`Teil ${i + 1}/${happen.length}: ${data.error}`)

      const teil = data as Extraktion
      if (!lager && teil.lager?.jahr) lager = teil.lager
      bloecke.push(...(teil.bloecke ?? []))
    }

    fortschritt.value = { phase: 'Analyse abgeschlossen.', aktuell: happen.length, total: happen.length }

    if (!lager) throw new Error('Lager-Titelseite konnte nicht erkannt werden.')
    ergebnis.value = { lager, bloecke }
    status.value = 'bereit'
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'PDF konnte nicht verarbeitet werden.'
    status.value = 'idle'
  }
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
      quelle: 'ecamp_pdf',
    }))
    const { error: bloeckeError } = await supabase.from('programmbloecke').insert(rows)
    if (bloeckeError) {
      error.value = `Lager wurde erstellt, aber Blöcke konnten nicht gespeichert werden: ${bloeckeError.message}`
      status.value = 'bereit'
      return
    }
  }

  status.value = 'fertig'
  router.push('/lager')
}
</script>

<template>
  <main>
    <h1>Lager aus eCamp-PDF importieren</h1>
    <p class="hint">
      In eCamp: Admin → Drucken → Layout 2 → PDF exportieren. Diese Datei hier hochladen.
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
      <p>{{ ergebnis.bloecke.length }} Programmblöcke gefunden:</p>
      <ul class="bloecke-liste">
        <li v-for="(b, i) in ergebnis.bloecke" :key="i">
          <strong>{{ b.code }}{{ b.nummer ? ' ' + b.nummer : '' }}</strong>
          {{ b.titel }}
          <span class="datum">{{ b.tag }}</span>
        </li>
      </ul>
      <button @click="importieren" :disabled="status === 'importiere'">
        {{ status === 'importiere' ? 'Importiere...' : 'Lager erstellen und Blöcke importieren' }}
      </button>
    </section>
  </main>
</template>

<style scoped>
main {
  max-width: 640px;
  margin: 2rem auto;
  font-family: system-ui, sans-serif;
  padding: 0 1rem;
}
.hint {
  color: #666;
  font-size: 0.9rem;
}
.fortschritt {
  margin: 1rem 0;
}
.fortschritt p {
  font-size: 0.9rem;
  color: #444;
  margin-bottom: 0.4rem;
}
.balken {
  width: 100%;
  height: 8px;
  background: #e5e5e5;
  border-radius: 4px;
  overflow: hidden;
}
.balken-fuellung {
  height: 100%;
  background: #333;
  transition: width 0.2s ease;
}
.lager-info {
  list-style: none;
  padding: 0;
  color: #444;
}
.bloecke-liste {
  max-height: 320px;
  overflow-y: auto;
  border: 1px solid #ddd;
  padding: 0.5rem 1rem;
  margin: 1rem 0;
}
.bloecke-liste li {
  padding: 0.2rem 0;
}
.datum {
  color: #888;
  font-size: 0.85rem;
}
button {
  padding: 0.6rem 1rem;
  font-size: 1rem;
  cursor: pointer;
}
.error {
  color: #b00020;
}
</style>
