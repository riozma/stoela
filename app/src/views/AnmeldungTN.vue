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
  allergien: '',
  notfallkontakt: '',
  eltern_email: '',
})

onMounted(async () => {
  const { data, error } = await supabase.rpc('get_lager_anmeldung_info', { p_lager_id: lagerId, p_typ: 'tn' })
  if (error || !data) {
    const { data: peek } = await supabase.rpc('get_lager_anmeldung_peek', { p_lager_id: lagerId })
    if (peek?.status) {
      ladefehler.value = `Anmeldung nicht offen (aktueller Status: ${peek.status}). Die Lagerleitung muss unter Einstellungen den Status auf «Anmeldung offen» setzen.`
    } else {
      ladefehler.value = 'Die Anmeldung für dieses Lager ist aktuell nicht verfügbar.'
    }
    return
  }
  lagerName.value = (data as { name: string }).name
})

async function absenden() {
  fehler.value = ''
  speichern.value = true
  const { error } = await supabase.from('anmeldungen_tn').insert({
    lager_id: lagerId,
    vorname: form.value.vorname,
    nachname: form.value.nachname,
    geburtsdatum: form.value.geburtsdatum,
    geschlecht: form.value.geschlecht || null,
    ahv_nr: form.value.ahv_nr || null,
    allergien: form.value.allergien || null,
    notfallkontakt: form.value.notfallkontakt,
    eltern_email: form.value.eltern_email,
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
    <h1>Anmeldung Teilnehmer/in</h1>
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
          <input v-model="form.geburtsdatum" type="date" required />
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
          Allergien / Unverträglichkeiten
          <input v-model="form.allergien" type="text" />
        </label>
        <label>
          Notfallkontakt (Name + Telefon)
          <input v-model="form.notfallkontakt" type="text" required />
        </label>
        <label>
          E-Mail Eltern
          <input v-model="form.eltern_email" type="email" required />
        </label>
        <button type="submit" :disabled="speichern">
          {{ speichern ? 'Sende...' : 'Anmelden' }}
        </button>
      </form>
      <p v-if="fehler" class="error">{{ fehler }}</p>
    </template>

    <p v-else>
      Danke, die Anmeldung ist eingegangen!
      <router-link :to="`/lager/${lagerId}/willkommen`">Zur Lager-Infoseite</router-link>
    </p>
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
