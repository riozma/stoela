<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { formatProgrammTag } from '../../lib/programmUtils'

interface ProgrammEintrag {
  id: string
  tag: string
  start_zeit: string | null
  end_zeit: string | null
  titel: string
  ort: string | null
  beschreibung: string | null
}

interface Anmeldung {
  id: string
  vorname: string
  nachname: string
  anwesend_von: string | null
  anwesend_bis: string | null
  notiz: string | null
}

const props = defineProps<{
  lagerId: string
  vorweekendStart: string | null
  vorweekendEnde: string | null
}>()

const programm = ref<ProgrammEintrag[]>([])
const anmeldungen = ref<Anmeldung[]>([])
const form = ref({ tag: '', start_zeit: '10:00', end_zeit: '12:00', titel: '', ort: '', beschreibung: '' })
const wwForm = ref({ start: '', ende: '' })
const fehler = ref('')

const tage = computed(() => {
  if (!props.vorweekendStart || !props.vorweekendEnde) return []
  const list: string[] = []
  const cur = new Date(props.vorweekendStart + 'T00:00:00')
  const end = new Date(props.vorweekendEnde + 'T00:00:00')
  while (cur <= end) {
    list.push(cur.toISOString().slice(0, 10))
    cur.setDate(cur.getDate() + 1)
  }
  return list
})

async function laden() {
  wwForm.value.start = props.vorweekendStart ?? ''
  wwForm.value.ende = props.vorweekendEnde ?? ''
  const [{ data: p }, { data: a }] = await Promise.all([
    supabase.from('vorweekend_programm').select('*').eq('lager_id', props.lagerId).order('tag').order('sortierung'),
    supabase.from('vorweekend_anmeldungen').select('id, vorname, nachname, anwesend_von, anwesend_bis, notiz').eq('lager_id', props.lagerId),
  ])
  programm.value = p ?? []
  anmeldungen.value = a ?? []
}

onMounted(laden)

async function datenSpeichern() {
  await supabase.from('lager').update({
    vorweekend_start: wwForm.value.start || null,
    vorweekend_ende: wwForm.value.ende || null,
  }).eq('id', props.lagerId)
  await supabase.rpc('lager_termine_sync', { p_lager_id: props.lagerId })
}

async function programmHinzufuegen() {
  fehler.value = ''
  const { error } = await supabase.from('vorweekend_programm').insert({
    lager_id: props.lagerId,
    tag: form.value.tag,
    start_zeit: form.value.start_zeit || null,
    end_zeit: form.value.end_zeit || null,
    titel: form.value.titel,
    ort: form.value.ort || null,
    beschreibung: form.value.beschreibung || null,
  })
  if (error) { fehler.value = error.message; return }
  form.value = { tag: tage.value[0] ?? '', start_zeit: '10:00', end_zeit: '12:00', titel: '', ort: '', beschreibung: '' }
  await laden()
}

async function programmLoeschen(id: string) {
  await supabase.from('vorweekend_programm').delete().eq('id', id)
  await laden()
}
</script>

<template>
  <section class="vorweekend">
    <h3>Vorweekend</h3>
    <p class="hint">Ca. 4.5–5 Monate vor Lager: Motto, Teambuilding, Tagesteams. Feinprogramm läuft in eCamp.</p>

    <form class="ww-daten" @submit.prevent="datenSpeichern">
      <label>Start <input v-model="wwForm.start" type="date" /></label>
      <label>Ende <input v-model="wwForm.ende" type="date" /></label>
      <button type="submit" class="secondary klein">Daten speichern</button>
    </form>

    <h4>Programm (Timetable light)</h4>
    <div v-if="programm.length" class="programm-liste">
      <article v-for="e in programm" :key="e.id" class="prog-karte">
        <span class="zeit">{{ e.start_zeit?.slice(0, 5) }}–{{ e.end_zeit?.slice(0, 5) }}</span>
        <strong>{{ formatProgrammTag(e.tag) }}: {{ e.titel }}</strong>
        <p v-if="e.ort">{{ e.ort }}</p>
        <p v-if="e.beschreibung" class="beschreibung">{{ e.beschreibung }}</p>
        <button class="secondary klein" @click="programmLoeschen(e.id)">Löschen</button>
      </article>
    </div>
    <p v-else class="hint">Noch kein Vorweekend-Programm.</p>

    <form class="form-grid" @submit.prevent="programmHinzufuegen">
      <label>Tag
        <select v-model="form.tag" required>
          <option v-for="t in tage" :key="t" :value="t">{{ formatProgrammTag(t) }}</option>
        </select>
      </label>
      <label>Start <input v-model="form.start_zeit" type="time" /></label>
      <label>Ende <input v-model="form.end_zeit" type="time" /></label>
      <label class="full">Titel <input v-model="form.titel" required placeholder="z.B. Teambuilding" /></label>
      <label>Ort <input v-model="form.ort" /></label>
      <label class="full">Plan <textarea v-model="form.beschreibung" rows="2" /></label>
      <button type="submit">Eintrag hinzufügen</button>
    </form>

    <h4>Anmeldungen Leiter/innen</h4>
    <p class="hint">
      Leiter melden sich unter
      <router-link :to="`/lager/${lagerId}/anmelden-leiter`">/anmelden-leiter</router-link>
      an – Vorweekend-Zeiten können später ergänzt werden.
    </p>
    <ul v-if="anmeldungen.length" class="anmeld-liste">
      <li v-for="a in anmeldungen" :key="a.id">
        {{ a.vorname }} {{ a.nachname }}
        <span v-if="a.anwesend_von" class="klein"> · {{ a.anwesend_von }} – {{ a.anwesend_bis }}</span>
      </li>
    </ul>
    <p v-if="fehler" class="error">{{ fehler }}</p>
  </section>
</template>

<style scoped>
.vorweekend h3 { margin: 0 0 0.25rem; }
.vorweekend h4 { margin: 1.25rem 0 0.5rem; font-size: 0.95rem; }
.ww-daten { display: flex; flex-wrap: wrap; gap: 0.6rem; align-items: end; margin: 1rem 0; }
.ww-daten label { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.82rem; color: var(--color-text-muted); }
.programm-liste { display: grid; gap: 0.5rem; margin-bottom: 1rem; }
.prog-karte { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.75rem 1rem; }
.zeit { font-size: 0.78rem; color: var(--color-text-muted); margin-right: 0.5rem; }
.beschreibung { font-size: 0.88rem; color: var(--color-text-muted); margin: 0.25rem 0; }
.form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 0.6rem; margin-top: 0.75rem; }
.form-grid label { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.82rem; color: var(--color-text-muted); }
.form-grid .full { grid-column: 1 / -1; }
.anmeld-liste { list-style: none; padding: 0; font-size: 0.9rem; }
.klein { font-size: 0.78rem; color: var(--color-text-muted); }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.error { color: var(--color-danger); }
button.klein { font-size: 0.75rem; padding: 0.25rem 0.55rem; }
</style>
