<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../supabaseClient'

interface Verein {
  id: string
}
interface Event {
  id: string
  name: string
  datum: string | null
  ort: string | null
  beschreibung: string | null
}

const vereinId = ref<string | null>(null)
const events = ref<Event[]>([])
const loading = ref(true)
const error = ref('')

const form = ref({ name: '', datum: '', ort: '', beschreibung: '' })
const saving = ref(false)

async function laden() {
  loading.value = true
  const { data: verein } = await supabase.from('verein').select('id').limit(1).single<Verein>()
  vereinId.value = verein?.id ?? null

  const { data, error: err } = await supabase
    .from('events')
    .select('id, name, datum, ort, beschreibung')
    .order('datum', { ascending: false })
  if (err) error.value = err.message
  else events.value = data ?? []
  loading.value = false
}

async function erstellen() {
  if (!vereinId.value) return
  saving.value = true
  const { error: err } = await supabase.from('events').insert({
    verein_id: vereinId.value,
    name: form.value.name,
    datum: form.value.datum || null,
    ort: form.value.ort || null,
    beschreibung: form.value.beschreibung || null,
  })
  saving.value = false
  if (err) {
    error.value = err.message
    return
  }
  form.value = { name: '', datum: '', ort: '', beschreibung: '' }
  await laden()
}

onMounted(laden)
</script>

<template>
  <main>
    <p><router-link to="/lager">← Zur Übersicht</router-link></p>
    <h1>Events</h1>
    <p class="hint">Einzelne Anlässe des Vereins, unabhängig von einem grossen Lager (z.B. Vorbereitungstreffen).</p>

    <p v-if="loading">Lade...</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <table v-else-if="events.length" class="liste">
      <thead>
        <tr>
          <th>Datum</th>
          <th>Name</th>
          <th>Ort</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="e in events" :key="e.id">
          <td>{{ e.datum ?? '–' }}</td>
          <td>{{ e.name }}</td>
          <td>{{ e.ort ?? '–' }}</td>
        </tr>
      </tbody>
    </table>
    <p v-else class="hint">Noch keine Events erfasst.</p>

    <h3>Neuer Event</h3>
    <form @submit.prevent="erstellen" class="inline-form">
      <input v-model="form.name" placeholder="Name" required />
      <input v-model="form.datum" type="date" />
      <input v-model="form.ort" placeholder="Ort" />
      <button type="submit" :disabled="saving">{{ saving ? 'Speichere...' : 'Erstellen' }}</button>
    </form>
  </main>
</template>

<style scoped>
main {
  max-width: 640px;
  margin: 2rem auto;
  padding: 0 1rem;
}
.hint {
  color: var(--color-text-muted);
  font-size: 0.9rem;
}
.liste {
  width: 100%;
  border-collapse: collapse;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  margin: 1rem 0;
}
.liste th,
.liste td {
  text-align: left;
  padding: 0.5rem 0.75rem;
  border-bottom: 1px solid var(--color-border);
}
.liste th {
  color: var(--color-text-muted);
  font-weight: 700;
  font-size: 0.85rem;
}
.inline-form {
  display: flex;
  flex-wrap: wrap;
  gap: 0.6rem;
  align-items: center;
  margin-top: 0.75rem;
}
.error {
  color: var(--color-danger);
}
</style>
