<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { useAuth } from '../../composables/useAuth'
import { ahvBeimTippen, ESSENS_OPTIONEN, essensLabel } from '../../lib/tnAnmeldung'
import { speichereProfilLeiterDaten } from '../../lib/profileNames'

const props = defineProps<{
  lagerId: string
  config: { geburtsdatum: boolean; geschlecht: boolean; ahv_nr: boolean; essensgewohnheiten: boolean }
}>()

const { session } = useAuth()

interface EigeneAnmeldung {
  id: string
  geburtsdatum: string | null
  geschlecht: string | null
  ahv_nr: string | null
  essensgewohnheiten: string | null
  anwesend_von: string | null
  anwesend_bis: string | null
}

const offen = ref(false)
const anmeldung = ref<EigeneAnmeldung | null>(null)
const fehlt = ref<string[]>([])
const speichern = ref(false)
const fehler = ref('')

const form = ref({
  geburtsdatum: '', geschlecht: '', ahv_nr: '',
  essensgewohnheiten: [] as typeof ESSENS_OPTIONEN[number]['id'][],
  essensgewohnheiten_keine: false,
  anwesend_von: '', anwesend_bis: '',
})

function toggleEssens(id: typeof ESSENS_OPTIONEN[number]['id']) {
  if (form.value.essensgewohnheiten_keine) form.value.essensgewohnheiten_keine = false
  const idx = form.value.essensgewohnheiten.indexOf(id)
  if (idx >= 0) form.value.essensgewohnheiten.splice(idx, 1)
  else form.value.essensgewohnheiten.push(id)
}

async function pruefen() {
  if (!session.value) return
  const { data } = await supabase
    .from('anmeldungen_leiter')
    .select('id, geburtsdatum, geschlecht, ahv_nr, essensgewohnheiten, anwesend_von, anwesend_bis')
    .eq('lager_id', props.lagerId)
    .eq('profile_id', session.value.user.id)
    .eq('status', 'bestaetigt')
    .maybeSingle()
  if (!data) return
  anmeldung.value = data as EigeneAnmeldung

  const fehlend: string[] = []
  if (props.config.geburtsdatum && !data.geburtsdatum) fehlend.push('Geburtsdatum')
  if (props.config.geschlecht && !data.geschlecht) fehlend.push('Geschlecht')
  if (props.config.ahv_nr && !data.ahv_nr) fehlend.push('AHV-Nummer')
  if (props.config.essensgewohnheiten && !data.essensgewohnheiten) fehlend.push('Essensgewohnheiten')
  if (!data.anwesend_von || !data.anwesend_bis) fehlend.push('Anwesenheitszeitraum')

  if (!fehlend.length) return
  fehlt.value = fehlend
  form.value = {
    geburtsdatum: data.geburtsdatum ?? '',
    geschlecht: data.geschlecht ?? '',
    ahv_nr: data.ahv_nr ?? '',
    essensgewohnheiten: [],
    essensgewohnheiten_keine: false,
    anwesend_von: data.anwesend_von ?? '',
    anwesend_bis: data.anwesend_bis ?? '',
  }
  offen.value = true
}

onMounted(pruefen)

async function speichernHandler() {
  if (!anmeldung.value || !session.value) return
  fehler.value = ''
  speichern.value = true
  const essensText = form.value.essensgewohnheiten.length || form.value.essensgewohnheiten_keine
    ? essensLabel(form.value.essensgewohnheiten, '', form.value.essensgewohnheiten_keine)
    : anmeldung.value.essensgewohnheiten

  const { error } = await supabase.from('anmeldungen_leiter').update({
    geburtsdatum: form.value.geburtsdatum || null,
    geschlecht: form.value.geschlecht || null,
    ahv_nr: form.value.ahv_nr || null,
    essensgewohnheiten: essensText === '–' ? null : essensText,
    anwesend_von: form.value.anwesend_von || null,
    anwesend_bis: form.value.anwesend_bis || null,
  }).eq('id', anmeldung.value.id)

  if (error) { speichern.value = false; fehler.value = error.message; return }

  try {
    await speichereProfilLeiterDaten(session.value.user.id, {
      geburtsdatum: form.value.geburtsdatum,
      geschlecht: form.value.geschlecht,
      ahv_nr: form.value.ahv_nr,
    })
  } catch { /* Profil-Sync ist optional, TN-Anmeldung nicht blockieren */ }

  speichern.value = false
  offen.value = false
}
</script>

<template>
  <div v-if="offen" class="popup-overlay">
    <div class="popup-karte">
      <h3>Bitte noch ergänzen</h3>
      <p class="hint">Diese Angaben fehlen noch für deine Anmeldung in diesem Lager: {{ fehlt.join(', ') }}.</p>

      <form @submit.prevent="speichernHandler">
        <label v-if="config.geburtsdatum && !anmeldung?.geburtsdatum">
          Geburtsdatum <input v-model="form.geburtsdatum" type="date" />
        </label>
        <label v-if="config.geschlecht && !anmeldung?.geschlecht">
          Geschlecht
          <select v-model="form.geschlecht">
            <option value="">–</option>
            <option value="m">männlich</option>
            <option value="w">weiblich</option>
            <option value="d">divers</option>
          </select>
        </label>
        <label v-if="config.ahv_nr && !anmeldung?.ahv_nr">
          AHV-Nummer
          <input :value="form.ahv_nr" type="text" placeholder="756.xxxx.xxxx.xx" @input="form.ahv_nr = ahvBeimTippen(($event.target as HTMLInputElement).value)" />
        </label>
        <fieldset v-if="config.essensgewohnheiten && !anmeldung?.essensgewohnheiten" class="essen-feld">
          <legend>Essensgewohnheiten</legend>
          <label v-for="o in ESSENS_OPTIONEN" :key="o.id" class="checkbox-label">
            <input type="checkbox" :checked="form.essensgewohnheiten.includes(o.id)" @change="toggleEssens(o.id)" />
            {{ o.label }}
          </label>
          <label class="checkbox-label">
            <input type="checkbox" v-model="form.essensgewohnheiten_keine" />
            Keine besonderen Gewohnheiten
          </label>
        </fieldset>
        <template v-if="!anmeldung?.anwesend_von || !anmeldung?.anwesend_bis">
          <label>Anwesend von <input v-model="form.anwesend_von" type="date" /></label>
          <label>Anwesend bis <input v-model="form.anwesend_bis" type="date" /></label>
        </template>

        <p v-if="fehler" class="error">{{ fehler }}</p>
        <div class="aktionen">
          <button type="button" class="secondary" @click="offen = false">Später</button>
          <button type="submit" :disabled="speichern">{{ speichern ? 'Speichere…' : 'Speichern' }}</button>
        </div>
      </form>
    </div>
  </div>
</template>

<style scoped>
.popup-overlay {
  position: fixed; inset: 0; background: rgba(0, 0, 0, 0.45); z-index: 250;
  display: flex; align-items: center; justify-content: center; padding: 1rem;
}
.popup-karte {
  background: var(--color-surface); border-radius: var(--radius-md); padding: 1.25rem;
  max-width: 420px; width: 100%; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
}
.popup-karte h3 { margin: 0 0 0.35rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin: 0 0 0.85rem; }
form { display: flex; flex-direction: column; gap: 0.75rem; }
label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.85rem; color: var(--color-text-muted); }
.checkbox-label { flex-direction: row !important; align-items: center; gap: 0.5rem; color: var(--color-text) !important; font-size: 0.88rem !important; }
.essen-feld { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.65rem; display: flex; flex-direction: column; gap: 0.4rem; }
.essen-feld legend { font-size: 0.85rem; color: var(--color-text-muted); padding: 0 0.25rem; }
.error { color: var(--color-danger); font-size: 0.85rem; }
.aktionen { display: flex; justify-content: flex-end; gap: 0.6rem; }
</style>
