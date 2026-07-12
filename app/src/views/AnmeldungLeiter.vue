<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
import { bestaetigenBis } from '../lib/workflowUtils'
import { ladeProfilLeiterDaten, speichereProfilLeiterDaten } from '../lib/profileNames'
import { ESSENS_OPTIONEN, ahvBeimTippen, essensLabel } from '../lib/tnAnmeldung'

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

interface LeiterAnmeldungConfig {
  geburtsdatum: boolean
  geschlecht: boolean
  ahv_nr: boolean
  essensgewohnheiten: boolean
}

const lagerInfo = ref<{ name: string; start_datum: string | null; end_datum: string | null } | null>(null)
const anmeldungConfig = ref<LeiterAnmeldungConfig>({
  geburtsdatum: true,
  geschlecht: true,
  ahv_nr: true,
  essensgewohnheiten: true,
})
const ladefehler = ref('')
const gesendet = ref(false)
const speichern = ref(false)
const fehler = ref('')
const bestehendeAnfrage = ref<string | null>(null)
const profilHatStammdaten = ref(false)
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
  provisorisch: false,
  essensgewohnheiten: [] as typeof ESSENS_OPTIONEN[number]['id'][],
  essensgewohnheiten_keine: false,
  essensgewohnheiten_sonstiges: '',
})

function toggleEssens(id: typeof ESSENS_OPTIONEN[number]['id']) {
  if (form.value.essensgewohnheiten_keine) form.value.essensgewohnheiten_keine = false
  const idx = form.value.essensgewohnheiten.indexOf(id)
  if (idx >= 0) form.value.essensgewohnheiten.splice(idx, 1)
  else form.value.essensgewohnheiten.push(id)
}

function keineEssensGewohnheiten() {
  form.value.essensgewohnheiten_keine = !form.value.essensgewohnheiten_keine
  if (form.value.essensgewohnheiten_keine) {
    form.value.essensgewohnheiten = []
    form.value.essensgewohnheiten_sonstiges = ''
  }
}

onMounted(async () => {
  if (!session.value) {
    await router.replace({ path: '/login', query: { redirect: route.fullPath } })
    return
  }

  const { data, error } = await supabase.rpc('get_lager_anmeldung_info', { p_lager_id: lagerId, p_typ: 'leiter' })
  if (error || !data) {
    ladefehler.value = 'Die Leiteranmeldung ist für dieses Lager aktuell nicht eröffnet. Bitte bei der Lagerleitung nachfragen.'
    return
  }
  lagerInfo.value = data as typeof lagerInfo.value
  if ((data as { leiter_anmeldung_config?: Partial<LeiterAnmeldungConfig> }).leiter_anmeldung_config) {
    anmeldungConfig.value = {
      ...anmeldungConfig.value,
      ...(data as { leiter_anmeldung_config: Partial<LeiterAnmeldungConfig> }).leiter_anmeldung_config,
    }
  }
  form.value.anwesend_von = data.start_datum ?? ''
  form.value.anwesend_bis = data.end_datum ?? ''

  const profil = await ladeProfilLeiterDaten(session.value.user)
  form.value.vorname = profil.vorname
  form.value.nachname = profil.nachname
  form.value.geburtsdatum = profil.geburtsdatum
  form.value.geschlecht = profil.geschlecht
  form.value.ahv_nr = profil.ahv_nr
  form.value.telefon = profil.telefon
  profilHatNamen.value = profil.namenVollstaendig
  profilHatStammdaten.value = profil.stammdatenVollstaendig

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

  try {
    await speichereProfilLeiterDaten(session.value.user.id, {
      vorname: form.value.vorname,
      nachname: form.value.nachname,
      geburtsdatum: form.value.geburtsdatum,
      geschlecht: form.value.geschlecht,
      ahv_nr: form.value.ahv_nr,
      telefon: form.value.telefon,
    })
  } catch (e) {
    speichern.value = false
    fehler.value = e instanceof Error ? e.message : 'Profil konnte nicht gespeichert werden.'
    return
  }

  const essensText = essensLabel(
    form.value.essensgewohnheiten,
    form.value.essensgewohnheiten_sonstiges,
    form.value.essensgewohnheiten_keine,
  )

  const { data: inserted, error } = await supabase
    .from('anmeldungen_leiter')
    .insert({
      lager_id: lagerId,
      profile_id: session.value.user.id,
      vorname: form.value.vorname.trim(),
      nachname: form.value.nachname.trim(),
      geburtsdatum: form.value.geburtsdatum || null,
      geschlecht: form.value.geschlecht || null,
      ahv_nr: form.value.ahv_nr || null,
      email: email.value,
      telefon: form.value.telefon || null,
      anwesend_von: form.value.provisorisch ? null : (form.value.anwesend_von || null),
      anwesend_bis: form.value.provisorisch ? null : (form.value.anwesend_bis || null),
      essensgewohnheiten: essensText === '–' ? null : essensText,
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

        <template v-if="!profilHatStammdaten">
          <label v-if="anmeldungConfig.geburtsdatum">Geburtsdatum <input v-model="form.geburtsdatum" type="date" /></label>
          <label v-if="anmeldungConfig.geschlecht">Geschlecht
            <select v-model="form.geschlecht">
              <option value="">–</option>
              <option value="m">männlich</option>
              <option value="w">weiblich</option>
              <option value="d">divers</option>
            </select>
          </label>
          <label v-if="anmeldungConfig.ahv_nr">AHV-Nummer <input :value="form.ahv_nr" type="text" placeholder="756.xxxx.xxxx.xx" @input="form.ahv_nr = ahvBeimTippen(($event.target as HTMLInputElement).value)" /></label>
          <label>Telefon <input v-model="form.telefon" type="tel" /></label>
        </template>
        <p v-else class="hint">Stammdaten aus deinem Profil übernommen (Geburtsdatum, Geschlecht, AHV, Telefon).</p>

        <label class="checkbox-label">
          <input v-model="form.provisorisch" type="checkbox" />
          Provisorisch anmelden (An-/Abreise noch unklar – spätestens 3 Monate vor Lager bestätigen)
        </label>
        <template v-if="!form.provisorisch">
          <label>Anwesend von <input v-model="form.anwesend_von" type="date" /></label>
          <label>Anwesend bis <input v-model="form.anwesend_bis" type="date" /></label>
        </template>
        <p v-if="form.provisorisch && bestaetigungHinweis" class="hint">{{ bestaetigungHinweis }}</p>

        <fieldset v-if="anmeldungConfig.essensgewohnheiten" class="essen-feld">
          <legend>Essensgewohnheiten</legend>
          <label v-for="o in ESSENS_OPTIONEN" :key="o.id" class="checkbox-label">
            <input type="checkbox" :checked="form.essensgewohnheiten.includes(o.id)" @change="toggleEssens(o.id)" />
            {{ o.label }}
          </label>
          <label class="checkbox-label">
            <input type="checkbox" :checked="form.essensgewohnheiten_keine" @change="keineEssensGewohnheiten" />
            Keine besonderen Gewohnheiten
          </label>
          <label>Sonstiges
            <input v-model="form.essensgewohnheiten_sonstiges" placeholder="z.B. kein Rindfleisch" />
          </label>
        </fieldset>

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
.essen-feld { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.75rem; display: flex; flex-direction: column; gap: 0.45rem; }
.essen-feld legend { font-size: 0.85rem; color: var(--color-text-muted); padding: 0 0.25rem; }
</style>
