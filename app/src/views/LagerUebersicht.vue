<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'

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
  start_datum: '',
  end_datum: '',
})
const saving = ref(false)

async function ladeLager() {
  loading.value = true
  const { data, error: fetchError } = await supabase
    .from('lager')
    .select('id, jahr, name, ort, start_datum, end_datum, status')
    .order('jahr', { ascending: false })

  if (fetchError) error.value = fetchError.message
  else lager.value = data ?? []
  loading.value = false
}

async function erstellen() {
  error.value = ''
  saving.value = true
  const { error: insertError } = await supabase.from('lager').insert({
    jahr: form.value.jahr,
    name: form.value.name,
    ort: form.value.ort || null,
    start_datum: form.value.start_datum || null,
    end_datum: form.value.end_datum || null,
  })
  saving.value = false

  if (insertError) {
    error.value = insertError.message
    return
  }
  form.value.name = `Stöckli-Lager ${form.value.jahr + 1}`
  form.value.jahr += 1
  form.value.ort = ''
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
        <button @click="kontoOffen = !kontoOffen">Konto</button>
        <button @click="signOut">Logout</button>
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
          <input v-model="form.ort" type="text" />
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
          <tr v-for="l in lager" :key="l.id">
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
  max-width: 720px;
  margin: 2rem auto;
  font-family: system-ui, sans-serif;
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
}
input {
  padding: 0.5rem;
  font-size: 1rem;
}
button {
  padding: 0.5rem 1rem;
  cursor: pointer;
}
table {
  width: 100%;
  border-collapse: collapse;
}
th,
td {
  text-align: left;
  padding: 0.4rem 0.6rem;
  border-bottom: 1px solid #ddd;
}
.error {
  color: #b00020;
}
</style>
