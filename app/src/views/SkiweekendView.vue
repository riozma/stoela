<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { formatProgrammTag } from '../lib/programmUtils'
import AppHeader from '../components/AppHeader.vue'

const props = defineProps<{ lagerId: string }>()

const router = useRouter()

interface SkiWochenende {
  id: string
  jahr: number
  ort: string | null
  start_datum: string | null
  end_datum: string | null
  budget: number | null
}

interface ProgEintrag {
  id: string
  tag: string
  start_zeit: string | null
  end_zeit: string | null
  titel: string
  ort: string | null
}

interface Anmeldung {
  id: string
  vorname: string
  nachname: string
  anwesend_von: string | null
  anwesend_bis: string | null
  notiz: string | null
}

const ski = ref<SkiWochenende | null>(null)
const programm = ref<ProgEintrag[]>([])
const anmeldungen = ref<Anmeldung[]>([])
const anmForm = ref({ vorname: '', nachname: '', von: '', bis: '', notiz: '' })
const laden = ref(true)
const gesendet = ref(false)

async function ladeDaten() {
  laden.value = true
  const { data: lagerRow } = await supabase.from('lager').select('organisation_id, jahr').eq('id', props.lagerId).single()
  if (!lagerRow?.organisation_id) { laden.value = false; return }

  const { data: s } = await supabase
    .from('org_skiweekend')
    .select('id, jahr, ort, start_datum, end_datum, budget')
    .eq('organisation_id', lagerRow.organisation_id)
    .eq('jahr', lagerRow.jahr)
    .maybeSingle()
  ski.value = s

  if (s) {
    const [{ data: p }, { data: a }] = await Promise.all([
      supabase.from('org_skiweekend_programm').select('*').eq('skiweekend_id', s.id).order('tag').order('sortierung'),
      supabase.from('org_skiweekend_anmeldungen').select('*').eq('skiweekend_id', s.id).order('nachname'),
    ])
    programm.value = p ?? []
    anmeldungen.value = a ?? []
  }
  laden.value = false
}

onMounted(ladeDaten)

async function anmelden() {
  if (!ski.value) return
  await supabase.from('org_skiweekend_anmeldungen').insert({
    skiweekend_id: ski.value.id,
    vorname: anmForm.value.vorname,
    nachname: anmForm.value.nachname,
    anwesend_von: anmForm.value.von || null,
    anwesend_bis: anmForm.value.bis || null,
    notiz: anmForm.value.notiz || null,
  })
  anmForm.value = { vorname: '', nachname: '', von: '', bis: '', notiz: '' }
  gesendet.value = true
  await ladeDaten()
}
</script>

<template>
  <div>
    <AppHeader />
    <main class="page">
      <button class="secondary klein" @click="router.push(`/lager/${lagerId}/dashboard`)">← Zum Dashboard</button>

      <p v-if="laden" class="hint">Lade...</p>

      <template v-else-if="ski">
        <h2>Skiweekend {{ ski.jahr }}</h2>
        <p class="meta">
          <span v-if="ski.ort">📍 {{ ski.ort }}</span>
          <span v-if="ski.start_datum"> · {{ ski.start_datum }} – {{ ski.end_datum }}</span>
        </p>

        <h3 v-if="programm.length">Timetable</h3>
        <ul v-if="programm.length" class="prog-liste">
          <li v-for="e in programm" :key="e.id">
            {{ formatProgrammTag(e.tag) }} {{ e.start_zeit?.slice(0, 5) }}–{{ e.end_zeit?.slice(0, 5) }}: <strong>{{ e.titel }}</strong>
            <span v-if="e.ort"> · {{ e.ort }}</span>
          </li>
        </ul>

        <h3>Wer ist schon angemeldet ({{ anmeldungen.length }})</h3>
        <ul v-if="anmeldungen.length" class="anm-liste">
          <li v-for="a in anmeldungen" :key="a.id">
            {{ a.vorname }} {{ a.nachname }}
            <span v-if="a.anwesend_von"> · {{ a.anwesend_von }} – {{ a.anwesend_bis }}</span>
          </li>
        </ul>
        <p v-else class="hint">Noch niemand angemeldet.</p>

        <h3>Selbst anmelden</h3>
        <p v-if="gesendet" class="ok">Danke, deine Anmeldung ist da!</p>
        <form class="formular" @submit.prevent="anmelden">
          <label>Vorname <input v-model="anmForm.vorname" required /></label>
          <label>Nachname <input v-model="anmForm.nachname" required /></label>
          <label>Dabei von <input v-model="anmForm.von" type="date" /></label>
          <label>Dabei bis <input v-model="anmForm.bis" type="date" /></label>
          <label>Notiz <input v-model="anmForm.notiz" placeholder="z.B. eigenes Auto, Ski-Grösse..." /></label>
          <button type="submit">Anmelden</button>
        </form>
      </template>

      <p v-else class="hint">Für dieses Jahr ist noch kein Skiweekend geplant.</p>
    </main>
  </div>
</template>

<style scoped>
.page { max-width: 640px; margin: 0 auto; padding: 1.25rem; }
.page h2 { margin: 0.75rem 0 0.25rem; }
.page h3 { margin: 1.25rem 0 0.5rem; font-size: 1rem; }
.meta { color: var(--color-text-muted); }
.hint { color: var(--color-text-muted); font-size: 0.9rem; }
.ok { color: #2e7d32; font-size: 0.9rem; }
.prog-liste, .anm-liste { list-style: none; padding: 0; margin: 0; font-size: 0.9rem; }
.prog-liste li, .anm-liste li { padding: 0.35rem 0; border-bottom: 1px solid var(--color-border); }
.formular { display: flex; flex-direction: column; gap: 0.75rem; max-width: 360px; }
.formular label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.85rem; color: var(--color-text-muted); }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.5rem; margin-bottom: 0.5rem; }
</style>
