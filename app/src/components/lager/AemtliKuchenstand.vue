<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

interface Standort { id: string; ort: string; datum: string | null; notiz: string | null; schichten: Schicht[] }
interface Schicht { id: string; titel: string | null; start_zeit: string | null; end_zeit: string | null; anmeldungen: { id: string; vorname: string; nachname: string; was: string | null; menge: string | null }[] }

const standorte = ref<Standort[]>([])
const standortForm = ref({ ort: '', datum: '', notiz: '' })
const schichtForm = ref({ standortId: '', titel: 'Schicht', start: '09:00', ende: '12:00' })
const anmForm = ref({ schichtId: '', vorname: '', nachname: '', was: '', menge: '' })

async function laden() {
  const { data: s } = await supabase.from('kuchenstand_standorte').select('*').eq('lager_id', props.lagerId).order('sortierung')
  const result: Standort[] = []
  for (const st of s ?? []) {
    const { data: sch } = await supabase.from('kuchenstand_schichten').select('*').eq('standort_id', st.id)
    const schichten: Schicht[] = []
    for (const sc of sch ?? []) {
      const { data: anm } = await supabase.from('kuchenstand_anmeldungen').select('*').eq('schicht_id', sc.id)
      schichten.push({ ...sc, anmeldungen: anm ?? [] })
    }
    result.push({ ...st, schichten })
  }
  standorte.value = result
}

onMounted(laden)

async function standortHinzufuegen() {
  await supabase.from('kuchenstand_standorte').insert({
    lager_id: props.lagerId, ort: standortForm.value.ort, datum: standortForm.value.datum || null, notiz: standortForm.value.notiz || null,
  })
  standortForm.value = { ort: '', datum: '', notiz: '' }
  await laden()
  await supabase.rpc('lager_termine_sync', { p_lager_id: props.lagerId })
}

async function schichtHinzufuegen() {
  await supabase.from('kuchenstand_schichten').insert({
    standort_id: schichtForm.value.standortId,
    titel: schichtForm.value.titel,
    start_zeit: schichtForm.value.start,
    end_zeit: schichtForm.value.ende,
  })
  await laden()
}

async function anmelden() {
  await supabase.from('kuchenstand_anmeldungen').insert({
    schicht_id: anmForm.value.schichtId,
    vorname: anmForm.value.vorname,
    nachname: anmForm.value.nachname,
    was: anmForm.value.was || null,
    menge: anmForm.value.menge || null,
  })
  anmForm.value = { schichtId: '', vorname: '', nachname: '', was: '', menge: '' }
  await laden()
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <h3>Standorte</h3>
    <p class="hint">Standorte mit Datum erscheinen automatisch im Lager-Kalender.</p>
    <form class="inline-form" @submit.prevent="standortHinzufuegen">
      <input v-model="standortForm.ort" placeholder="Ort" required />
      <input v-model="standortForm.datum" type="date" />
      <input v-model="standortForm.notiz" placeholder="Notiz" />
      <button type="submit">+ Standort</button>
    </form>

    <article v-for="st in standorte" :key="st.id" class="standort-karte">
      <strong>{{ st.ort }}</strong>
      <span v-if="st.datum" class="hint"> · {{ st.datum }}</span>
      <p v-if="st.notiz" class="hint">{{ st.notiz }}</p>

      <form class="inline-form" @submit.prevent="schichtForm.standortId = st.id; schichtHinzufuegen()">
        <input v-model="schichtForm.titel" placeholder="Schicht" />
        <input v-model="schichtForm.start" type="time" />
        <input v-model="schichtForm.ende" type="time" />
        <button type="submit" @click="schichtForm.standortId = st.id">+ Schicht</button>
      </form>

      <div v-for="sc in st.schichten" :key="sc.id" class="schicht">
        <h4>{{ sc.titel }} {{ sc.start_zeit?.slice(0,5) }}–{{ sc.end_zeit?.slice(0,5) }}</h4>
        <ul>
          <li v-for="a in sc.anmeldungen" :key="a.id">{{ a.vorname }} {{ a.nachname }} – {{ a.was }} {{ a.menge }}</li>
        </ul>
        <form class="inline-form" @submit.prevent="anmForm.schichtId = sc.id; anmelden()">
          <input v-model="anmForm.vorname" placeholder="Vorname" required />
          <input v-model="anmForm.nachname" placeholder="Nachname" required />
          <input v-model="anmForm.was" placeholder="Was bringst du?" />
          <input v-model="anmForm.menge" placeholder="Menge" />
          <button type="submit" @click="anmForm.schichtId = sc.id">Anmelden</button>
        </form>
      </div>
    </article>
  </AemtliShell>
</template>

<style scoped>
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 0.5rem 0; align-items: end; }
.standort-karte { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.85rem; margin: 0.75rem 0; }
.schicht { margin-top: 0.5rem; padding-left: 0.5rem; border-left: 3px solid var(--color-accent); }
.schicht h4 { margin: 0.35rem 0; font-size: 0.88rem; }
.hint { color: var(--color-text-muted); font-size: 0.85rem; }
</style>
