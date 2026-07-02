<script setup lang="ts">
import { ref } from 'vue'
import { useAuth } from '../composables/useAuth'

const { signInWithPassword, signInWithGoogle } = useAuth()

const email = ref('')
const password = ref('')
const error = ref('')
const loading = ref(false)

async function submitPassword() {
  error.value = ''
  loading.value = true
  try {
    await signInWithPassword(email.value, password.value)
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Login fehlgeschlagen.'
  } finally {
    loading.value = false
  }
}

async function withGoogle() {
  error.value = ''
  try {
    await signInWithGoogle()
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Google-Login fehlgeschlagen.'
  }
}
</script>

<template>
  <main>
    <h1>Stöckli Lager</h1>
    <p class="hint">Nur für das Leiterteam. Teilnehmer/innen finden ihre Infos unter dem Willkommens-Link.</p>

    <button class="google" type="button" @click="withGoogle">Mit Google anmelden</button>

    <p class="divider">oder</p>

    <form @submit.prevent="submitPassword">
      <input
        v-model="email"
        type="email"
        required
        placeholder="deine.email@example.com"
        autocomplete="email"
      />
      <input
        v-model="password"
        type="password"
        required
        placeholder="Passwort"
        autocomplete="current-password"
      />
      <button type="submit" :disabled="loading">
        {{ loading ? 'Logge ein...' : 'Einloggen' }}
      </button>
    </form>

    <p v-if="error" class="error">{{ error }}</p>
  </main>
</template>

<style scoped>
main {
  max-width: 400px;
  margin: 4rem auto;
  text-align: center;
}
h1 {
  font-size: 1.7rem;
}
.hint {
  font-size: 0.85rem;
  color: var(--color-text-muted);
  margin-bottom: 1.5rem;
}
.google {
  width: 100%;
  background: var(--color-surface);
  color: var(--color-text);
  border: 1px solid var(--color-border);
  margin-bottom: 1rem;
}
.google:hover:not(:disabled) {
  background: var(--color-surface-muted);
}
.divider {
  color: var(--color-text-muted);
  font-size: 0.85rem;
  margin: 1rem 0;
}
form {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}
.error {
  color: var(--color-danger);
  margin-top: 1rem;
}
</style>
