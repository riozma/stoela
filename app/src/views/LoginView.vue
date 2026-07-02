<script setup lang="ts">
import { ref } from 'vue'
import { useAuth } from '../composables/useAuth'

const { sendMagicLink } = useAuth()

const email = ref('')
const sent = ref(false)
const error = ref('')
const loading = ref(false)

async function submit() {
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
</script>

<template>
  <main>
    <h1>Stöckli Lager</h1>
    <p v-if="!sent">Melde dich mit deiner E-Mail-Adresse an, du erhältst einen Login-Link.</p>

    <form v-if="!sent" @submit.prevent="submit">
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

    <p v-else>
      Check dein Postfach ({{ email }}) – dort findest du den Login-Link.
    </p>

    <p v-if="error" class="error">{{ error }}</p>
  </main>
</template>

<style scoped>
main {
  max-width: 400px;
  margin: 4rem auto;
  font-family: system-ui, sans-serif;
  text-align: center;
}
form {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  margin-top: 1.5rem;
}
input {
  padding: 0.6rem;
  font-size: 1rem;
}
button {
  padding: 0.6rem;
  font-size: 1rem;
  cursor: pointer;
}
.error {
  color: #b00020;
}
</style>
