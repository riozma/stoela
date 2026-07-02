<script setup lang="ts">
import { onMounted, ref, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'

const route = useRoute()
const router = useRouter()
const { session } = useAuth()
const lagerId = route.params.id as string

const lagerInfo = ref<{ name: string; start_datum: string | null; end_datum: string | null } | null>(null)
const ladefehler = ref('')
const gesendet = ref(false)
const speichern = ref(false)
const fehler = ref('')
const bestehendeAnfrage = ref<string | null>(null)

const form = ref({
  vorname: '',
  nachname: '',
  geburtsdatum: '',
  geschlecht: '',
  ahv_nr: '',
  telefon: '',
  anwesend_von: '',
  anwesend_bis: '',
})

const email = computed(() => session.value?.user.email ?? '')

onMounted(async () => {
  if (!session.value) {
    await router.replace({ path: '/login', query: { redirect: route.fullPath } })
    return
  }

  const { data, error } = await supabase.rpc('get_lager_anmeldung_info', { p_lager_id: lagerId, p_typ: 'leiter' })
  if (error || !data) {
    const { data: peek } = await supabase.rpc('get_lager_anmeldung_peek', { p_lager_id: lagerId })
    ladefehler.value = peek?.status
      ? `Leiter-Bewerbung nicht möglich (Status: ${peek.status}).`
      : 'Dieses Lager ist nicht verfügbar.'
    return
  }
  lagerInfo.value = data as typeof lagerInfo.value
  form.value.anwesend_von = data.start_datum ?? ''
  form.value.anwesend_bis = data.end_datum ?? ''

  const { data: profil } = await supabase.from('profiles').select('vorname, nachname').eq('id', session.value.user.id).single()
  if (profil?.vorname) form.value.vorname = profil.vorname
  if (profil?.nachname) form.value.nachname = profil.nachname

  const { data: anfrage } = await supabase
    .from('anmeldungen_leiter')
    .select('id, status')
    .eq('lager_id', lagerId)
    .eq('profile_id', session.value.user.id)
    .maybeSingle()

  if (anfrage) {
    bestehendeAnfrage.value = anfrage.status
    if (anfrage.status === 'bestaetigt') gesendet.value = true
  }
})

async function absenden() {
  if (!session.value) return
  fehler.value = ''
  speichern.value = true
  const { error } = await supabase.from('anmeldungen_leiter').insert({
    lager_id: lagerId,
    profile_id: session.value.user.id,
    vorname: form.value.vorname,
    nachname: form.value.nachname,
    geburtsdatum: form.value.geburtsdatum || null,
    geschlecht: form.value.geschlecht || null,
    ahv_nr: form.value.ahv_nr || null,
    email: email.value,
    telefon: form.value.telefon || null,
    anwesend_von: form.value.anwesend_von || null,
    anwesend_bis: form.value.anwesend_bis || null,
    status: 'angefragt',
  })
  speichern.value = false
  if (error) {
    fehler.value = error.message
    return
  }
  gesendet.value = true
  bestehendeAnfrage.value = 'angefragt'
}
</script>

<template>
  <main>
    <h1>Als Leiter/in bewerben</h1>
    <p v-if="lagerInfo" class="hint">{{ lagerInfo.name }}</p>
    <p class="hint">Eingeloggt als {{ email }}</p>

    <p v-if="ladefehler" class="error">{{ ladefehler }}</p>

    <template v-else-if="bestehendeAnfrage === 'angefragt' || (gesendet && bestehendeAnfrage !== 'bestaetigt')">
      <p>Deine Anfrage ist eingegangen. Die Lagerleitung muss dich noch freischalten – danach siehst du das Lager in deiner Übersicht.</p>
    </template>

    <template v-else-if="bestehendeAnfrage === 'abgelehnt'">
      <p class="error">Deine Anfrage wurde abgelehnt.</p>
    </template>

    <template v-else-if="bestehendeAnfrage === 'bestaetigt'">
      <p>Du bist freigeschaltet! <router-link :to="`/lager/${lagerId}/dashboard`">Zum Lager</router-link></p>
    </template>

    <template v-else-if="!gesendet">
      <form @submit.prevent="absenden">
        <label>Vorname <input v-model="form.vorname" type="text" required /></label>
        <label>Nachname <input v-model="form.nachname" type="text" required /></label>
        <label>Geburtsdatum <input v-model="form.geburtsdatum" type="date" /></label>
        <label>Geschlecht
          <select v-model="form.geschlecht">
            <option value="">–</option>
            <option value="m">männlich</option>
            <option value="w">weiblich</option>
            <option value="d">divers</option>
          </select>
        </label>
        <label>AHV-Nummer <input v-model="form.ahv_nr" type="text" placeholder="756.xxxx.xxxx.xx" /></label>
        <label>Telefon <input v-model="form.telefon" type="tel" /></label>
        <label>Anwesend von <input v-model="form.anwesend_von" type="date" /></label>
        <label>Anwesend bis <input v-model="form.anwesend_bis" type="date" /></label>
        <button type="submit" :disabled="speichern">{{ speichern ? 'Sende...' : 'Anfrage senden' }}</button>
      </form>
      <p v-if="fehler" class="error">{{ fehler }}</p>
    </template>
  </main>
</template>

<style scoped>
main { max-width: 480px; margin: 2rem auto; padding: 0 1rem; }
.hint { color: var(--color-text-muted); font-size: 0.9rem; }
form { display: flex; flex-direction: column; gap: 0.85rem; margin-top: 1.5rem; }
label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.85rem; color: var(--color-text-muted); }
.error { color: var(--color-danger); }
</style>
