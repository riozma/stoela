<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../supabaseClient'

interface Aemtli {
  id: string
  name: string
  beschreibung: string | null
}

const aemtliListe = ref<Aemtli[]>([])
const loading = ref(true)
const error = ref('')

const neuerName = ref('')
const neueBeschreibung = ref('')
const speichern = ref(false)

async function laden() {
  loading.value = true
  const { data, error: err } = await supabase.from('aemtli').select('id, name, beschreibung').order('name')
  if (err) error.value = err.message
  else aemtliListe.value = data ?? []
  loading.value = false
}

async function erstellen() {
  if (!neuerName.value.trim()) return
  speichern.value = true
  const { error: err } = await supabase.from('aemtli').insert({
    name: neuerName.value.trim(),
    beschreibung: neueBeschreibung.value || null,
  })
  speichern.value = false
  if (err) {
    error.value = err.message
    return
  }
  neuerName.value = ''
  neueBeschreibung.value = ''
  await laden()
}

onMounted(laden)
</script>

<template>
  <main>
    <p><router-link to="/lager">← Zur Übersicht</router-link></p>
    <h1>Ämtli</h1>
    <p class="hint">
      Der Ämtli-Katalog gehört dem Verein, nicht einem einzelnen Lager. Was hier steht (Anleitungen, ToDos,
      Learnings) bleibt Jahr für Jahr erhalten und wird beim nächsten Lager einfach wieder zugewiesen.
    </p>

    <p v-if="loading">Lade...</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <ul v-else class="aemtli-liste">
      <li v-for="a in aemtliListe" :key="a.id">
        <router-link :to="`/aemtli/${a.id}`">{{ a.name }}</router-link>
        <span v-if="a.beschreibung" class="hint"> – {{ a.beschreibung }}</span>
      </li>
    </ul>

    <h3>Neues Ämtli</h3>
    <form @submit.prevent="erstellen" class="inline-form">
      <input v-model="neuerName" placeholder="Name" required />
      <input v-model="neueBeschreibung" placeholder="Kurzbeschreibung (optional)" />
      <button type="submit" :disabled="speichern">{{ speichern ? 'Speichere...' : 'Erstellen' }}</button>
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
.aemtli-liste {
  list-style: none;
  padding: 0;
  margin: 1.25rem 0;
}
.aemtli-liste li {
  padding: 0.6rem 0;
  border-bottom: 1px solid var(--color-border);
}
.aemtli-liste a {
  font-weight: 700;
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
