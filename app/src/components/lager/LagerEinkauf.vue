<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { downloadEinkaufPdf } from '../../lib/einkaufPdf'

interface EinkaufItem {
  id: string
  name: string
  menge: number | null
  einheit: string | null
  bereich: string
  mahlzeit: string | null
  notiz: string | null
  erledigt: boolean
  erstellt_von: string | null
  programm_block_id: string | null
}

interface EinkaufTermin {
  id: string
  einkauf_am: string
  frueh_geschlossen: boolean
}

const props = defineProps<{
  lagerId: string
  lagerName: string
  userId: string
  istKueche: boolean
  bloecke: { id: string; titel: string; code: string }[]
}>()

const items = ref<EinkaufItem[]>([])
const termine = ref<EinkaufTermin[]>([])
const fehler = ref('')
const form = ref({ name: '', menge: '', einheit: '', bereich: 'lager', mahlzeit: '', notiz: '', programm_block_id: '' })
const terminForm = ref({ datum: '', uhrzeit: '10:00' })

const aktiverTermin = computed(() => termine.value.find((t) => !t.frueh_geschlossen) ?? null)

const deadline = computed(() => {
  if (!aktiverTermin.value) return null
  const d = new Date(aktiverTermin.value.einkauf_am)
  d.setHours(d.getHours() - 4)
  return d
})

const eintragOffen = computed(() => {
  if (!aktiverTermin.value || aktiverTermin.value.frueh_geschlossen) return false
  if (!deadline.value) return true
  return new Date() < deadline.value
})

function darfBearbeiten(item: EinkaufItem) {
  return item.erstellt_von === props.userId || props.istKueche
}

function formatTermin(iso: string) {
  return new Intl.DateTimeFormat('de-CH', { dateStyle: 'full', timeStyle: 'short' }).format(new Date(iso))
}

async function laden() {
  const [{ data: itemData }, { data: terminData }] = await Promise.all([
    supabase.from('einkaufsliste_items').select('*').eq('lager_id', props.lagerId).order('created_at'),
    supabase.from('einkaufs_termine').select('id, einkauf_am, frueh_geschlossen').eq('lager_id', props.lagerId).order('einkauf_am', { ascending: false }),
  ])
  items.value = (itemData ?? []) as EinkaufItem[]
  termine.value = terminData ?? []
}

async function hinzufuegen() {
  fehler.value = ''
  if (!eintragOffen.value && !props.istKueche) {
    fehler.value = 'Die Deadline für Einträge ist vorbei.'
    return
  }
  const { error } = await supabase.from('einkaufsliste_items').insert({
    lager_id: props.lagerId,
    name: form.value.name,
    menge: form.value.menge ? Number(form.value.menge) : null,
    einheit: form.value.einheit || null,
    bereich: form.value.bereich,
    mahlzeit: form.value.mahlzeit || null,
    notiz: form.value.notiz || null,
    programm_block_id: form.value.programm_block_id || null,
    erstellt_von: props.userId,
  })
  if (error) { fehler.value = error.message; return }
  form.value = { name: '', menge: '', einheit: '', bereich: 'lager', mahlzeit: '', notiz: '', programm_block_id: '' }
  await laden()
}

async function toggleErledigt(item: EinkaufItem) {
  if (!darfBearbeiten(item)) return
  await supabase.from('einkaufsliste_items').update({ erledigt: !item.erledigt }).eq('id', item.id)
  item.erledigt = !item.erledigt
}

async function mahlzeitSetzen(item: EinkaufItem, mahlzeit: string) {
  if (!props.istKueche) return
  await supabase.from('einkaufsliste_items').update({ mahlzeit: mahlzeit || null }).eq('id', item.id)
  await laden()
}

async function terminSetzen() {
  if (!props.istKueche || !terminForm.value.datum) return
  const iso = `${terminForm.value.datum}T${terminForm.value.uhrzeit}:00`
  await supabase.from('einkaufs_termine').insert({
    lager_id: props.lagerId,
    einkauf_am: new Date(iso).toISOString(),
    erstellt_von: props.userId,
  })
  terminForm.value.datum = ''
  await laden()
}

async function fruehSchliessen() {
  if (!props.istKueche || !aktiverTermin.value) return
  await supabase.from('einkaufs_termine').update({ frueh_geschlossen: true }).eq('id', aktiverTermin.value.id)
  await laden()
}

function pdfExport() {
  downloadEinkaufPdf(
    props.lagerName,
    termine.value.map((t) => ({
      einkaufAm: formatTermin(t.einkauf_am),
      deadline: formatTermin(new Date(new Date(t.einkauf_am).getTime() - 4 * 3600000).toISOString()),
    })),
    items.value.map((i) => ({
      name: i.name,
      menge: [i.menge, i.einheit].filter(Boolean).join(' '),
      bereich: i.bereich,
      mahlzeit: i.mahlzeit ?? '–',
      notiz: i.notiz ?? '',
      erledigt: i.erledigt,
    })),
  )
}

onMounted(laden)
</script>

<template>
  <section>
    <div v-if="aktiverTermin" class="termin-banner" :class="{ geschlossen: aktiverTermin.frueh_geschlossen }">
      <p><strong>Nächster Einkauf:</strong> {{ formatTermin(aktiverTermin.einkauf_am) }}</p>
      <p v-if="deadline && !aktiverTermin.frueh_geschlossen">
        Einträge bis: {{ formatTermin(deadline.toISOString()) }}
      </p>
      <p v-if="aktiverTermin.frueh_geschlossen" class="warn">Einkaufsliste geschlossen.</p>
      <button v-if="istKueche && !aktiverTermin.frueh_geschlossen" class="secondary klein" @click="fruehSchliessen">
        Früh schliessen
      </button>
    </div>

    <div v-if="istKueche" class="kueche-box">
      <h3>Einkaufstermin setzen (Küche)</h3>
      <div class="inline-form">
        <input v-model="terminForm.datum" type="date" />
        <input v-model="terminForm.uhrzeit" type="time" />
        <button @click="terminSetzen">Termin speichern</button>
        <button class="secondary" @click="pdfExport">PDF / Drucken</button>
      </div>
    </div>

    <table v-if="items.length" class="liste">
      <thead>
        <tr><th></th><th>Artikel</th><th>Bereich</th><th>Mahlzeit</th><th>Notiz</th></tr>
      </thead>
      <tbody>
        <tr v-for="item in items" :key="item.id" :class="{ erledigt: item.erledigt }">
          <td>
            <input
              type="checkbox"
              :checked="item.erledigt"
              :disabled="!darfBearbeiten(item)"
              @change="toggleErledigt(item)"
            />
          </td>
          <td>{{ item.name }} <span v-if="item.menge" class="hint">{{ item.menge }} {{ item.einheit }}</span></td>
          <td>{{ item.bereich }}</td>
          <td>
            <select
              v-if="istKueche"
              :value="item.mahlzeit ?? ''"
              @change="mahlzeitSetzen(item, ($event.target as HTMLSelectElement).value)"
            >
              <option value="">–</option>
              <option value="fruehstueck">Frühstück</option>
              <option value="zmittag">Z'Mittag</option>
              <option value="znacht">Z'Nacht</option>
              <option value="jause">Jause</option>
            </select>
            <span v-else>{{ item.mahlzeit ?? '–' }}</span>
          </td>
          <td>{{ item.notiz ?? '' }}</td>
        </tr>
      </tbody>
    </table>

    <h3 v-if="eintragOffen || istKueche">Eintrag hinzufügen</h3>
    <form v-if="eintragOffen || istKueche" @submit.prevent="hinzufuegen" class="inline-form">
      <input v-model="form.name" placeholder="Artikel" required />
      <input v-model="form.menge" type="number" step="any" placeholder="Menge" class="klein" />
      <input v-model="form.einheit" placeholder="Einheit" class="klein" />
      <select v-model="form.bereich">
        <option value="lager">Ganzes Lager</option>
        <option value="programm">Programm</option>
        <option value="privat">Privat</option>
      </select>
      <select v-if="form.bereich === 'programm'" v-model="form.programm_block_id">
        <option value="">Programm wählen</option>
        <option v-for="b in bloecke" :key="b.id" :value="b.id">{{ b.code }} {{ b.titel }}</option>
      </select>
      <input v-model="form.notiz" placeholder="Notiz" />
      <button type="submit">Hinzufügen</button>
    </form>
    <p v-if="fehler" class="error">{{ fehler }}</p>
  </section>
</template>

<style scoped>
.termin-banner {
  background: var(--color-surface); border: 1px solid var(--color-border);
  border-radius: var(--radius-md); padding: 0.85rem 1rem; margin-bottom: 1rem;
}
.termin-banner.geschlossen { opacity: 0.75; }
.warn { color: var(--color-danger); font-size: 0.85rem; }
.kueche-box { margin-bottom: 1rem; padding: 1rem; background: var(--color-surface-muted); border-radius: var(--radius-md); }
.liste { width: 100%; border-collapse: collapse; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); margin: 1rem 0; font-size: 0.9rem; }
.liste th, .liste td { text-align: left; padding: 0.5rem 0.7rem; border-bottom: 1px solid var(--color-border); }
.liste tr.erledigt td { text-decoration: line-through; color: var(--color-text-muted); }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: center; margin: 0.75rem 0; }
.klein { width: 80px; }
.hint { font-size: 0.8rem; color: var(--color-text-muted); }
.error { color: var(--color-danger); }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.5rem; }
</style>
