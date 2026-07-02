<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabaseClient'

const route = useRoute()
const lagerId = route.params.id as string

const lagerName = ref('')
const ladefehler = ref('')
const gesendet = ref(false)
const speichern = ref(false)
const fehler = ref('')

const form = ref({
  vorname: '',
  nachname: '',
  geburtsdatum: '',
  geschlecht: '',
  ahv_nr: '',
  email: '',
  telefon: '',
  anwesend_von: '',
  anwesend_bis: '',
})

onMounted(async () => {
  const { data, error } = await supabase.from('lager').select('name, status, start_datum, end_datum').eq('id', lagerId).single()
  if (error || !data) {
    ladefehler.value = 'Lager wurde nicht gefunden.'
    return
  }
  if (data.status !== 'anmeldung_offen') {
    ladefehler.value = 'Die Anmeldung für dieses Lager ist aktuell nicht offen.'
    return
  }
  lagerName.value = data.name
  form.value.anwesend_von = data.start_datum ?? ''
  form.value.anwesend_bis = data.end_datum ?? ''
})

async function absenden() {
  fehler.value = ''
  speichern.value = true
  const { error } = await supabase.from('anmeldungen_leiter').insert({
    lager_id: lagerId,
    vorname: form.value.vorname,
    nachname: form.value.nachname,
    geburtsdatum: form.value.geburtsdatum || null,
    geschlecht: form.value.geschlecht || null,
    ahv_nr: form.value.ahv_nr || null,
    email: form.value.email,
    telefon: form.value.telefon || null,
    anwesend_von: form.value.anwesend_von || null,
    anwesend_bis: form.value.anwesend_bis || null,
  })
  speichern.value = false
  if (error) {
    fehler.value = error.message
    return
  }
  gesendet.value = true
}
</script>

<template>
  <main>
    <h1>Anmeldung Leiter/in</h1>
    <p v-if="lagerName" class="hint">{{ lagerName }}</p>

    <p v-if="ladefehler" class="error">{{ ladefehler }}</p>

    <template v-else-if="!gesendet">
      <form @submit.prevent="absenden">
        <label>
          Vorname
          <input v-model="form.vorname" type="text" required />
        </label>
        <label>
          Nachname
          <input v-model="form.nachname" type="text" required />
        </label>
        <label>
          Geburtsdatum
          <input v-model="form.geburtsdatum" type="date" />
        </label>
        <label>
          Geschlecht
          <select v-model="form.geschlecht">
            <option value="">–</option>
            <option value="m">männlich</option>
            <option value="w">weiblich</option>
            <option value="d">divers</option>
          </select>
        </label>
        <label>
          AHV-Nummer
          <input v-model="form.ahv_nr" type="text" placeholder="756.xxxx.xxxx.xx" />
        </label>
        <label>
          E-Mail
          <input v-model="form.email" type="email" required />
        </label>
        <label>
          Telefon
          <input v-model="form.telefon" type="tel" />
        </label>
        <label>
          Anwesend von
          <input v-model="form.anwesend_von" type="date" />
        </label>
        <label>
          Anwesend bis
          <input v-model="form.anwesend_bis" type="date" />
        </label>
        <button type="submit" :disabled="speichern">
          {{ speichern ? 'Sende...' : 'Anmelden' }}
        </button>
      </form>
      <p v-if="fehler" class="error">{{ fehler }}</p>
    </template>

    <p v-else>Danke, die Anmeldung ist eingegangen!</p>
  </main>
</template>

<style scoped>
main {
  max-width: 480px;
  margin: 2rem auto;
  padding: 0 1rem;
}
.hint {
  color: var(--color-text-muted);
  font-size: 0.9rem;
}
form {
  display: flex;
  flex-direction: column;
  gap: 0.85rem;
  margin-top: 1.5rem;
}
label {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.85rem;
  color: var(--color-text-muted);
}
.error {
  color: var(--color-danger);
}
</style>
