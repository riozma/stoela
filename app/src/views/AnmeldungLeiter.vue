<script setup lang="ts">
import { onMounted, ref, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
import { bestaetigenBis } from '../lib/workflowUtils'
import { ladeUndSyncProfilNamen, speichereProfilNamen } from '../lib/profileNames'

const route = useRoute()
const router = useRouter()
const { session } = useAuth()
const lagerId = route.params.id as string

const email = computed(() => session.value?.user.email ?? '')

const bestaetigungHinweis = computed(() => {
  if (!lagerInfo.value?.start_datum) return ''
  const bis = bestaetigenBis(lagerInfo.value.start_datum)
  return bis ? `Bitte spätestens bis ${bis} bestätigen (3 Monate vor Lager).` : ''
})

const lagerInfo = ref<{ name: string; start_datum: string | null; end_datum: string | null } | null>(null)
const ladefehler = ref('')
const gesendet = ref(false)
const speichern = ref(false)
const fehler = ref('')
const bestehendeAnfrage = ref<string | null>(null)
const profilHatNamen = ref(false)

const form = ref({
  vorname: '',
  nachname: '',
  geburtsdatum: '',
  geschlecht: '',
  ahv_nr: '',
  telefon: '',
  anwesend_von: '',
  anwesend_bis: '',
  provisorisch: true,
})

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

  const namen = await ladeUndSyncProfilNamen(session.value.user)
  form.value.vorname = namen.vorname
  form.value.nachname = namen.nachname
  profilHatNamen.value = namen.vollstaendig

  const { data: anfrage } = await supabase
    .from('anmeldungen_leiter')
    .select('id, status')
    .eq('lager_id', lagerId)
    .eq('profile_id', session.value.user.id)
    .maybeSingle()

  if (anfrage) {
    bestehendeAnfrage.value = anfrage.status
    if (anfrage.status === 'bestaetigt') {
      gesendet.value = true
      await router.replace(`/lager/${lagerId}/dashboard`)
      return
    }
  }
})

async function absenden() {
  if (!session.value) return
  fehler.value = ''
  speichern.value = true

  if (!profilHatNamen.value) {
    try {
      const gespeichert = await speichereProfilNamen(
        session.value.user.id,
        form.value.vorname,
        form.value.nachname,
      )
      form.value.vorname = gespeichert.vorname
      form.value.nachname = gespeichert.nachname
      profilHatNamen.value = true
    } catch (e) {
      speichern.value = false
      fehler.value = e instanceof Error ? e.message : 'Name konnte nicht gespeichert werden.'
      return
    }
  }

  const { data: inserted, error } = await supabase
    .from('anmeldungen_leiter')
    .insert({
      lager_id: lagerId,
      profile_id: session.value.user.id,
      vorname: form.value.vorname,
      nachname: form.value.nachname,
      geburtsdatum: form.value.geburtsdatum || null,
      geschlecht: form.value.geschlecht || null,
      ahv_nr: form.value.ahv_nr || null,
      email: email.value,
      telefon: form.value.telefon || null,
      anwesend_von: form.value.provisorisch ? null : (form.value.anwesend_von || null),
      anwesend_bis: form.value.provisorisch ? null : (form.value.anwesend_bis || null),
      status: form.value.provisorisch ? 'angemeldet' : 'angefragt',
      anmeldung_art: form.value.provisorisch ? 'provisorisch' : 'fix',
      bestaetigen_bis: lagerInfo.value?.start_datum ? bestaetigenBis(lagerInfo.value.start_datum) : null,
    })
    .select('status')
    .single()
  speichern.value = false
  if (error) {
    if (error.message.includes('Vereinsmitglied')) {
      fehler.value = 'Du musst zuerst Vereinsmitglied sein. Stelle auf der Startseite eine Beitrittsanfrage.'
    } else {
      fehler.value = error.message
    }
    return
  }
  gesendet.value = true
  bestehendeAnfrage.value = inserted?.status ?? 'angefragt'
  if (bestehendeAnfrage.value === 'bestaetigt') {
    await router.replace(`/lager/${lagerId}/dashboard`)
  }
}
</script>

<template>
  <main>
    <h1>Als Leiter/in bewerben</h1>
    <p v-if="lagerInfo" class="hint">{{ lagerInfo.name }}</p>
    <p class="hint">Eingeloggt als {{ email }}</p>

    <p v-if="ladefehler" class="error">{{ ladefehler }}</p>

    <template v-else-if="bestehendeAnfrage === 'angefragt' || bestehendeAnfrage === 'angemeldet' || (gesendet && bestehendeAnfrage !== 'bestaetigt')">
      <p>Deine Anmeldung ist eingegangen.
        <template v-if="form.provisorisch || bestehendeAnfrage === 'angemeldet'">
          Du bist provisorisch angemeldet. {{ bestaetigungHinweis }}
        </template>
        <template v-else>Die Lagerleitung muss dich noch freischalten.</template>
      </p>
    </template>

    <template v-else-if="bestehendeAnfrage === 'abgelehnt'">
      <p class="error">Deine Anfrage wurde abgelehnt.</p>
    </template>

    <template v-else-if="bestehendeAnfrage === 'bestaetigt'">
      <p>Du bist freigeschaltet! <router-link :to="`/lager/${lagerId}/dashboard`">Zum Lager</router-link></p>
    </template>

    <template v-else-if="!gesendet">
      <form @submit.prevent="absenden">
        <template v-if="!profilHatNamen">
          <label>Vorname <input v-model="form.vorname" type="text" required /></label>
          <label>Nachname <input v-model="form.nachname" type="text" required /></label>
        </template>
        <p v-else class="hint">Angemeldet als {{ form.vorname }} {{ form.nachname }}</p>
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
        <label class="checkbox-label">
          <input v-model="form.provisorisch" type="checkbox" />
          Provisorisch anmelden (An-/Abreise noch unklar – spätestens 3 Monate vor Lager bestätigen)
        </label>
        <template v-if="!form.provisorisch">
          <label>Anwesend von <input v-model="form.anwesend_von" type="date" /></label>
          <label>Anwesend bis <input v-model="form.anwesend_bis" type="date" /></label>
        </template>
        <p v-if="form.provisorisch && bestaetigungHinweis" class="hint">{{ bestaetigungHinweis }}</p>
        <button type="submit" :disabled="speichern">{{ speichern ? 'Sende...' : 'Anmeldung senden' }}</button>
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
.checkbox-label { flex-direction: row !important; align-items: center; gap: 0.5rem; font-size: 0.88rem !important; color: var(--color-text) !important; }
</style>
