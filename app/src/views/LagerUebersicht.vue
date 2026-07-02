<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
import { useGooglePlaces } from '../composables/useGooglePlaces'

interface Lager {
  id: string
  jahr: number
  name: string
  ort: string | null
  start_datum: string | null
  end_datum: string | null
  status: string
}

const { session, signOut, setPassword } = useAuth()
const router = useRouter()

async function logout() {
  await signOut()
  await router.push('/login')
}

const kontoOffen = ref(false)
const neuesPasswort = ref('')
const kontoNachricht = ref('')
const kontoError = ref('')
const kontoSaving = ref(false)

async function passwortSetzen() {
  kontoError.value = ''
  kontoNachricht.value = ''
  kontoSaving.value = true
  try {
    await setPassword(neuesPasswort.value)
    kontoNachricht.value = 'Passwort gesetzt. Du kannst dich künftig damit einloggen.'
    neuesPasswort.value = ''
  } catch (e) {
    kontoError.value = e instanceof Error ? e.message : 'Passwort konnte nicht gesetzt werden.'
  } finally {
    kontoSaving.value = false
  }
}

const lager = ref<Lager[]>([])
const loading = ref(true)
const error = ref('')

const naechstesJahr = new Date().getFullYear() + 1
const form = ref({
  jahr: naechstesJahr,
  name: `Stöckli-Lager ${naechstesJahr}`,
  ort: '',
  ort_lat: null as number | null,
  ort_lng: null as number | null,
  ort_place_id: null as string | null,
  start_datum: '',
  end_datum: '',
})
const saving = ref(false)

const { attachAutocomplete } = useGooglePlaces()
const ortInput = ref<HTMLInputElement | null>(null)

onMounted(() => {
  if (ortInput.value) {
    attachAutocomplete(ortInput.value, (gewaehlt) => {
      form.value.ort = gewaehlt.adresse
      form.value.ort_lat = gewaehlt.lat
      form.value.ort_lng = gewaehlt.lng
      form.value.ort_place_id = gewaehlt.placeId
    })
  }
})

async function ladeLager() {
  loading.value = true
  const { data, error: fetchError } = await supabase
    .from('lager')
    .select('id, jahr, name, ort, start_datum, end_datum, status')
    .order('jahr', { ascending: false })

  if (fetchError) error.value = fetchError.message
  else lager.value = data ?? []
  loading.value = false

  // Einziges kommendes Lager → direkt zum Dashboard
  const heute = new Date().toISOString().slice(0, 10)
  const kommende = lager.value.filter((l) => {
    if (l.status === 'archiviert' || l.status === 'abgeschlossen') return false
    if (l.end_datum && l.end_datum < heute) return false
    return true
  })
  if (kommende.length === 1) {
    await router.replace(`/lager/${kommende[0].id}`)
  }
}

async function erstellen() {
  error.value = ''
  saving.value = true
  const { data: neuesLager, error: insertError } = await supabase
    .from('lager')
    .insert({
      jahr: form.value.jahr,
      name: form.value.name,
      ort: form.value.ort || null,
      ort_lat: form.value.ort_lat,
      ort_lng: form.value.ort_lng,
      ort_place_id: form.value.ort_place_id,
      start_datum: form.value.start_datum || null,
      end_datum: form.value.end_datum || null,
      status: 'anmeldung_offen',
      created_by: session.value?.user.id ?? null,
    })
    .select('id')
    .single()

  if (insertError) {
    error.value = insertError.message
    saving.value = false
    return
  }

  // Ersteller/in wird automatisch bestätigtes Teammitglied dieses Lagers
  if (session.value) {
    await supabase.from('lager_leiter').insert({
      lager_id: neuesLager.id,
      profile_id: session.value.user.id,
      rolle: 'lagerleitung',
      status: 'bestaetigt',
    })
  }

  saving.value = false
  form.value.name = `Stöckli-Lager ${form.value.jahr + 1}`
  form.value.jahr += 1
  form.value.ort = ''
  form.value.ort_lat = null
  form.value.ort_lng = null
  form.value.ort_place_id = null
  form.value.start_datum = ''
  form.value.end_datum = ''
  await ladeLager()
}

onMounted(ladeLager)
</script>

<template>
  <main>
    <header>
      <h1>Stöckli Lager</h1>
      <div class="user">
        <span>{{ session?.user.email }}</span>
        <button class="secondary" @click="kontoOffen = !kontoOffen">Konto</button>
        <button class="secondary" @click="logout">Logout</button>
      </div>
    </header>

    <section v-if="kontoOffen">
      <h2>Konto</h2>
      <form @submit.prevent="passwortSetzen">
        <label>
          Neues Passwort
          <input v-model="neuesPasswort" type="password" required minlength="6" autocomplete="new-password" />
        </label>
        <button type="submit" :disabled="kontoSaving">
          {{ kontoSaving ? 'Speichere...' : 'Passwort setzen' }}
        </button>
      </form>
      <p v-if="kontoNachricht">{{ kontoNachricht }}</p>
      <p v-if="kontoError" class="error">{{ kontoError }}</p>
    </section>

    <section>
      <h2>Neues Lager erstellen</h2>
      <p class="hint">
        Oder <router-link to="/lager/import">aus eCamp-PDF importieren</router-link> (Blöcke werden automatisch übernommen).
      </p>
      <form @submit.prevent="erstellen">
        <label>
          Jahr
          <input v-model.number="form.jahr" type="number" required min="2020" />
        </label>
        <label>
          Name
          <input v-model="form.name" type="text" required />
        </label>
        <label>
          Ort
          <input ref="ortInput" v-model="form.ort" type="text" placeholder="Adresse eingeben..." />
        </label>
        <label>
          Start
          <input v-model="form.start_datum" type="date" />
        </label>
        <label>
          Ende
          <input v-model="form.end_datum" type="date" />
        </label>
        <button type="submit" :disabled="saving">
          {{ saving ? 'Speichere...' : 'Lager erstellen' }}
        </button>
      </form>
      <p v-if="error" class="error">{{ error }}</p>
    </section>

    <section>
      <h2>Bestehende Lager</h2>
      <p v-if="loading">Lade...</p>
      <table v-else-if="lager.length">
        <thead>
          <tr>
            <th>Jahr</th>
            <th>Name</th>
            <th>Ort</th>
            <th>Start</th>
            <th>Ende</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="l in lager" :key="l.id" class="lager-zeile" @click="router.push(`/lager/${l.id}`)">
            <td>{{ l.jahr }}</td>
            <td>{{ l.name }}</td>
            <td>{{ l.ort ?? '–' }}</td>
            <td>{{ l.start_datum ?? '–' }}</td>
            <td>{{ l.end_datum ?? '–' }}</td>
            <td>{{ l.status }}</td>
          </tr>
        </tbody>
      </table>
      <p v-else>Noch kein Lager erfasst.</p>
    </section>
  </main>
</template>

<style scoped>
main {
  max-width: 760px;
  margin: 2rem auto;
  padding: 0 1rem;
}
header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 2rem;
}
.user {
  display: flex;
  gap: 0.75rem;
  align-items: center;
  font-size: 0.9rem;
}
form {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 0.75rem;
  align-items: end;
  margin-bottom: 1rem;
}
label {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.85rem;
  color: var(--color-text-muted);
}
table {
  width: 100%;
  border-collapse: collapse;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  overflow: hidden;
}
th,
td {
  text-align: left;
  padding: 0.5rem 0.75rem;
  border-bottom: 1px solid var(--color-border);
}
th {
  color: var(--color-text-muted);
  font-weight: 700;
  font-size: 0.85rem;
}
.lager-zeile {
  cursor: pointer;
}
.lager-zeile:hover {
  background: var(--color-surface-muted);
}
.error {
  color: var(--color-danger);
}
.hint {
  font-size: 0.85rem;
  color: var(--color-text-muted);
  margin-top: -0.5rem;
  margin-bottom: 1rem;
}
</style>
