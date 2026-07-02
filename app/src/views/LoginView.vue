<script setup lang="ts">
import { ref } from 'vue'
import { useAuth } from '../composables/useAuth'

const { sendMagicLink, signInWithPassword, signInWithGoogle } = useAuth()

const mode = ref<'magiclink' | 'passwort'>('magiclink')

const email = ref('')
const password = ref('')
const sent = ref(false)
const error = ref('')
const loading = ref(false)

async function submitMagicLink() {
  error.value = ''
  loading.value = true
  try {
    await sendMagicLink(email.value)
    sent.value = true
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Login fehlgeschlagen.'
  } finally {
    loading.value = false
  }
}

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

    <button class="google" type="button" @click="withGoogle">Mit Google anmelden</button>

    <div class="tabs">
      <button
        type="button"
        :class="{ active: mode === 'magiclink' }"
        @click="mode = 'magiclink'; sent = false; error = ''"
      >
        Magic Link
      </button>
      <button
        type="button"
        :class="{ active: mode === 'passwort' }"
        @click="mode = 'passwort'; error = ''"
      >
        Passwort
      </button>
    </div>

    <template v-if="mode === 'magiclink'">
      <p v-if="!sent">Melde dich mit deiner E-Mail-Adresse an, du erhältst einen Login-Link.</p>
      <form v-if="!sent" @submit.prevent="submitMagicLink">
        <input
          v-model="email"
          type="email"
          required
          placeholder="deine.email@example.com"
          autocomplete="email"
        />
        <button type="submit" :disabled="loading">
          {{ loading ? 'Sende...' : 'Login-Link senden' }}
        </button>
      </form>
      <p v-else>Check dein Postfach ({{ email }}) – dort findest du den Login-Link.</p>
    </template>

    <template v-else>
      <p>Melde dich mit E-Mail und Passwort an.</p>
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
      <p class="hint">
        Noch kein Passwort? Melde dich per Magic Link an und leg unter „Konto" ein Passwort fest.
      </p>
    </template>

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
.google {
  width: 100%;
  background: var(--color-surface);
  color: var(--color-text);
  border: 1px solid var(--color-border);
  margin-bottom: 1.5rem;
}
.google:hover:not(:disabled) {
  background: var(--color-surface-muted);
}
.tabs {
  display: flex;
  gap: 0.5rem;
  justify-content: center;
  margin-bottom: 1rem;
}
.tabs button {
  background: none;
  color: var(--color-text-muted);
  border: 1px solid var(--color-border);
}
.tabs button.active {
  background: var(--color-accent);
  color: #fdfbf3;
  border-color: var(--color-accent);
}
form {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  margin-top: 1rem;
}
.hint {
  font-size: 0.85rem;
  color: var(--color-text-muted);
  margin-top: 1rem;
}
.error {
  color: var(--color-danger);
}
</style>
