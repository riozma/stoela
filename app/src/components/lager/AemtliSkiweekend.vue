<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { formatProgrammTag } from '../../lib/programmUtils'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

interface SkiWochenende {
  id: string
  jahr: number
  ort: string | null
  start_datum: string | null
  end_datum: string | null
  budget: number | null
  notiz: string | null
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
const skiForm = ref({ jahr: new Date().getFullYear() + 1, ort: '', start: '', ende: '', budget: null as number | null, notiz: '' })
const progForm = ref({ tag: '', start: '09:00', ende: '17:00', titel: '', ort: '' })
const anmForm = ref({ vorname: '', nachname: '', von: '', bis: '', notiz: '' })

async function ladeOrgId() {
  const { data } = await supabase
    .from('lager')
    .select('organisation_id')
    .eq('id', props.lagerId)
    .single()
  return data?.organisation_id ?? null
}

async function laden() {
  const orgId = await ladeOrgId()
  if (!orgId) return
  const jahr = new Date().getFullYear() + 1
  let { data: s } = await supabase.from('org_skiweekend').select('*').eq('organisation_id', orgId).eq('jahr', jahr).maybeSingle()
  if (!s) {
    const { data: neu } = await supabase.from('org_skiweekend').insert({
      organisation_id: orgId, jahr, ort: null, notiz: 'Mit Kassier Budget klären',
    }).select('*').single()
    s = neu
  }
  ski.value = s
  if (s) {
    skiForm.value = {
      jahr: s.jahr,
      ort: s.ort ?? '',
      start: s.start_datum ?? '',
      ende: s.end_datum ?? '',
      budget: s.budget,
      notiz: s.notiz ?? '',
    }
  }
  if (!s) return
  const [{ data: p }, { data: a }] = await Promise.all([
    supabase.from('org_skiweekend_programm').select('*').eq('skiweekend_id', s.id).order('tag').order('sortierung'),
    supabase.from('org_skiweekend_anmeldungen').select('*').eq('skiweekend_id', s.id).order('nachname'),
  ])
  programm.value = p ?? []
  anmeldungen.value = a ?? []
  if (s.start_datum) progForm.value.tag = s.start_datum
}

onMounted(laden)

async function skiSpeichern() {
  if (!ski.value) return
  await supabase.from('org_skiweekend').update({
    ort: skiForm.value.ort || null,
    start_datum: skiForm.value.start || null,
    end_datum: skiForm.value.ende || null,
    budget: skiForm.value.budget,
    notiz: skiForm.value.notiz || null,
  }).eq('id', ski.value.id)
  await laden()
}

async function progHinzufuegen() {
  if (!ski.value) return
  await supabase.from('org_skiweekend_programm').insert({
    skiweekend_id: ski.value.id,
    tag: progForm.value.tag,
    start_zeit: progForm.value.start,
    end_zeit: progForm.value.ende,
    titel: progForm.value.titel,
    ort: progForm.value.ort || null,
  })
  progForm.value.titel = ''
  await laden()
}

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
  await laden()
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <p class="hint org-hinweis">Skiweekend wird auf <strong>Organisationsebene</strong> geplant (nicht pro Lager). Budget mit Kassier absprechen.</p>

    <template v-if="ski">
      <h3>Skiweekend {{ ski.jahr }}</h3>
      <form class="inline-form" @submit.prevent="skiSpeichern">
        <input v-model="skiForm.ort" placeholder="Ort / Skigebiet" />
        <input v-model="skiForm.start" type="date" placeholder="Start" />
        <input v-model="skiForm.ende" type="date" placeholder="Ende" />
        <input v-model.number="skiForm.budget" type="number" placeholder="Budget CHF" />
        <input v-model="skiForm.notiz" placeholder="Notiz" />
        <button type="submit">Speichern</button>
      </form>
      <p v-if="ski.ort" class="meta">{{ ski.ort }} · {{ ski.start_datum }} – {{ ski.end_datum }} · Budget: {{ ski.budget ?? '–' }}</p>

      <h4>Timetable</h4>
      <ul v-if="programm.length" class="prog-liste">
        <li v-for="e in programm" :key="e.id">
          {{ formatProgrammTag(e.tag) }} {{ e.start_zeit?.slice(0,5) }}–{{ e.end_zeit?.slice(0,5) }}: <strong>{{ e.titel }}</strong>
          <span v-if="e.ort"> · {{ e.ort }}</span>
        </li>
      </ul>
      <form class="inline-form" @submit.prevent="progHinzufuegen">
        <input v-model="progForm.tag" type="date" required />
        <input v-model="progForm.start" type="time" />
        <input v-model="progForm.ende" type="time" />
        <input v-model="progForm.titel" placeholder="Titel" required />
        <input v-model="progForm.ort" placeholder="Ort" />
        <button type="submit">+ Eintrag</button>
      </form>

      <h4>Anmeldungen Leiter/innen</h4>
      <ul v-if="anmeldungen.length" class="anm-liste">
        <li v-for="a in anmeldungen" :key="a.id">
          {{ a.vorname }} {{ a.nachname }}
          <span v-if="a.anwesend_von"> · {{ a.anwesend_von }} – {{ a.anwesend_bis }}</span>
          <span v-if="a.notiz" class="klein"> ({{ a.notiz }})</span>
        </li>
      </ul>
      <form class="inline-form" @submit.prevent="anmelden">
        <input v-model="anmForm.vorname" placeholder="Vorname" required />
        <input v-model="anmForm.nachname" placeholder="Nachname" required />
        <input v-model="anmForm.von" type="date" />
        <input v-model="anmForm.bis" type="date" />
        <input v-model="anmForm.notiz" placeholder="Notiz" />
        <button type="submit">Anmelden</button>
      </form>
    </template>
  </AemtliShell>
</template>

<style scoped>
.org-hinweis { background: var(--color-surface-muted); padding: 0.6rem 0.85rem; border-radius: var(--radius-md); margin-bottom: 1rem; }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 0.5rem 0; align-items: end; }
h3, h4 { margin: 1rem 0 0.35rem; font-size: 0.95rem; }
.prog-liste, .anm-liste { list-style: none; padding: 0; font-size: 0.88rem; }
.meta, .klein { font-size: 0.82rem; color: var(--color-text-muted); }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
