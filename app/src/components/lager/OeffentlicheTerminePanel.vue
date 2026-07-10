<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import {
  KALENDER_DATUM_EDITIERBAR,
  TERMIN_TYP_LABELS,
  type LagerTermin,
  type LagerTerminTyp,
} from '../../lib/lagerTermine'

const props = defineProps<{
  lagerId: string
  isLeitung: boolean
  kompakt?: boolean
}>()

const emit = defineEmits<{ gespeichert: [] }>()

interface TerminForm {
  id: string | null
  start_datum: string
  start_zeit: string
  ort: string
}

const termine = ref<Partial<Record<LagerTerminTyp, LagerTermin>>>({})
const formular = ref<Partial<Record<LagerTerminTyp, TerminForm>>>({})
const speichern = ref<LagerTerminTyp | null>(null)
const fehler = ref('')

const typen = KALENDER_DATUM_EDITIERBAR

function leeresForm(): TerminForm {
  return { id: null, start_datum: '', start_zeit: '', ort: '' }
}

function formAusTermin(t: LagerTermin | undefined): TerminForm {
  if (!t) return leeresForm()
  return {
    id: t.id,
    start_datum: t.start_datum ?? '',
    start_zeit: t.start_zeit?.slice(0, 5) ?? '',
    ort: t.ort ?? '',
  }
}

async function laden() {
  fehler.value = ''
  await supabase.rpc('lager_termine_sync', { p_lager_id: props.lagerId })
  const { data } = await supabase
    .from('lager_termine')
    .select('*')
    .eq('lager_id', props.lagerId)
    .in('typ', typen)
  const map: Partial<Record<LagerTerminTyp, LagerTermin>> = {}
  const forms: Partial<Record<LagerTerminTyp, TerminForm>> = {}
  for (const t of (data ?? []) as LagerTermin[]) {
    map[t.typ] = t
    forms[t.typ] = formAusTermin(t)
  }
  for (const typ of typen) {
    if (!forms[typ]) forms[typ] = leeresForm()
  }
  termine.value = map
  formular.value = forms
}

onMounted(laden)

async function speichernTyp(typ: LagerTerminTyp) {
  if (!props.isLeitung) return
  const f = formular.value[typ]
  if (!f?.start_datum) {
    fehler.value = `${TERMIN_TYP_LABELS[typ]}: Datum ist Pflicht.`
    return
  }
  speichern.value = typ
  fehler.value = ''
  const { error } = await supabase.rpc('lager_termin_oeffentlich_upsert', {
    p_lager_id: props.lagerId,
    p_typ: typ,
    p_start_datum: f.start_datum,
    p_end_datum: f.start_datum,
    p_start_zeit: f.start_zeit || null,
    p_end_zeit: null,
    p_ort: f.ort || null,
    p_nur_ein_tag: true,
    p_termin_id: f.id,
  })
  speichern.value = null
  if (error) {
    fehler.value = error.message
    return
  }
  await laden()
  emit('gespeichert')
}

defineExpose({ laden })
</script>

<template>
  <section class="oeffentliche-termine" :class="{ kompakt }">
    <header v-if="!kompakt">
      <h3>Elternabend, Kennenlernabend &amp; Diashow</h3>
      <p class="hint">
        Datum, Uhrzeit und Ort – verknüpft mit Kalender und TN-Anmeldung. Nicht löschbar, nur anpassbar.
      </p>
    </header>
    <header v-else>
      <h3>Termine für TN-Anmeldung</h3>
      <p class="hint">Gleiche Daten wie im Kalender – erscheinen im Anmeldeformular.</p>
    </header>

    <div class="termin-grid">
      <article v-for="typ in typen" :key="typ" class="termin-karte">
        <h4>{{ TERMIN_TYP_LABELS[typ] }}</h4>
        <template v-if="isLeitung">
          <label>
            Datum
            <input v-model="formular[typ]!.start_datum" type="date" />
          </label>
          <label>
            Uhrzeit
            <input v-model="formular[typ]!.start_zeit" type="time" />
          </label>
          <label>
            Ort
            <input v-model="formular[typ]!.ort" placeholder="Ort" />
          </label>
          <button
            type="button"
            class="secondary klein"
            :disabled="speichern === typ"
            @click="speichernTyp(typ)"
          >
            {{ speichern === typ ? 'Speichere…' : (formular[typ]?.id ? 'Speichern' : 'Hinzufügen') }}
          </button>
        </template>
        <template v-else>
          <p v-if="termine[typ]?.start_datum">
            {{ termine[typ]!.start_datum }}
            <span v-if="termine[typ]!.start_zeit"> · {{ termine[typ]!.start_zeit?.slice(0, 5) }}</span>
            <span v-if="termine[typ]!.ort"> · {{ termine[typ]!.ort }}</span>
          </p>
          <p v-else class="hint">Noch nicht gesetzt</p>
        </template>
      </article>
    </div>
    <p v-if="fehler" class="error">{{ fehler }}</p>
  </section>
</template>

<style scoped>
.oeffentliche-termine { margin: 1rem 0; }
.oeffentliche-termine h3 { margin: 0 0 0.35rem; font-size: 0.95rem; }
.oeffentliche-termine h4 { margin: 0 0 0.5rem; font-size: 0.88rem; }
.hint { color: var(--color-text-muted); font-size: 0.85rem; margin: 0 0 0.65rem; }
.termin-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 0.65rem;
}
.termin-karte {
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 0.65rem 0.75rem;
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
}
.termin-karte label {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  font-size: 0.78rem;
  color: var(--color-text-muted);
}
.kompakt .termin-grid { grid-template-columns: 1fr; }
button.klein { align-self: flex-start; font-size: 0.78rem; padding: 0.25rem 0.5rem; }
.error { color: var(--color-danger); font-size: 0.85rem; }
</style>
