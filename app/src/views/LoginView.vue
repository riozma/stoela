<script setup lang="ts">
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'

const route = useRoute()
const router = useRouter()
const { signInWithPassword, signUpWithPassword, signInWithGoogle } = useAuth()

const modus = ref<'login' | 'register'>('login')
const email = ref('')
const password = ref('')
const vorname = ref('')
const nachname = ref('')
const geburtsdatum = ref('')
const error = ref('')
const info = ref('')
const loading = ref(false)

async function submitPassword() {
  error.value = ''
  info.value = ''
  loading.value = true
  try {
    await signInWithPassword(email.value, password.value)
    const redirect = typeof route.query.redirect === 'string' ? route.query.redirect : '/'
    await router.push(redirect)
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Login fehlgeschlagen.'
  } finally {
    loading.value = false
  }
}

async function submitRegister() {
  error.value = ''
  info.value = ''
  if (!vorname.value.trim() || !nachname.value.trim()) {
    error.value = 'Vorname und Nachname sind Pflicht.'
    return
  }
  if (password.value.length < 8) {
    error.value = 'Passwort mindestens 8 Zeichen.'
    return
  }
  loading.value = true
  try {
    await signUpWithPassword(email.value, password.value, vorname.value, nachname.value, geburtsdatum.value || undefined)
    info.value = 'Konto erstellt. Bitte E-Mail bestätigen und danach einloggen.'
    modus.value = 'login'
  } catch (e) {
    error.value = e instanceof Error ? e.message : 'Registrierung fehlgeschlagen.'
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
    <p class="hint">Leiterteam: einloggen oder registrieren. Teilnehmer/innen nutzen den Willkommens-Link zur Anmeldung.</p>

    <div class="modus-tabs">
      <button type="button" :class="{ aktiv: modus === 'login' }" @click="modus = 'login'">Einloggen</button>
      <button type="button" :class="{ aktiv: modus === 'register' }" @click="modus = 'register'">Registrieren</button>
    </div>

    <button class="google" type="button" @click="withGoogle">Mit Google anmelden</button>

    <p class="divider">oder mit E-Mail</p>

    <form v-if="modus === 'login'" @submit.prevent="submitPassword">
      <input v-model="email" type="email" required placeholder="deine.email@example.com" autocomplete="email" />
      <input v-model="password" type="password" required placeholder="Passwort" autocomplete="current-password" />
      <button type="submit" :disabled="loading">{{ loading ? 'Logge ein…' : 'Einloggen' }}</button>
    </form>

    <form v-else @submit.prevent="submitRegister">
      <input v-model="vorname" type="text" required placeholder="Vorname" autocomplete="given-name" />
      <input v-model="nachname" type="text" required placeholder="Nachname" autocomplete="family-name" />
      <input v-model="geburtsdatum" type="date" placeholder="Geburtsdatum (optional)" />
      <input v-model="email" type="email" required placeholder="deine.email@example.com" autocomplete="email" />
      <input v-model="password" type="password" required minlength="8" placeholder="Passwort (min. 8 Zeichen)" autocomplete="new-password" />
      <button type="submit" :disabled="loading">{{ loading ? 'Erstelle Konto…' : 'Konto erstellen' }}</button>
    </form>

    <p v-if="info" class="ok">{{ info }}</p>
    <p v-if="error" class="error">{{ error }}</p>
  </main>
</template>

<style scoped>
main { max-width: 400px; margin: 4rem auto; text-align: center; padding: 0 1rem; }
h1 { font-size: 1.7rem; }
.hint { font-size: 0.85rem; color: var(--color-text-muted); margin-bottom: 1rem; }
.modus-tabs { display: flex; gap: 0.5rem; margin-bottom: 1rem; }
.modus-tabs button {
  flex: 1;
  background: var(--color-surface);
  color: var(--color-text);
  border: 1px solid var(--color-border);
}
.modus-tabs button.aktiv { background: var(--color-accent); color: #fdfbf3; border-color: var(--color-accent); }
.google {
  width: 100%;
  background: var(--color-surface);
  color: var(--color-text);
  border: 1px solid var(--color-border);
  margin-bottom: 1rem;
}
.google:hover:not(:disabled) { background: var(--color-surface-muted); }
.divider { color: var(--color-text-muted); font-size: 0.85rem; margin: 1rem 0; }
form { display: flex; flex-direction: column; gap: 0.75rem; text-align: left; }
.ok { color: #2e7d32; margin-top: 1rem; }
.error { color: var(--color-danger); margin-top: 1rem; }
</style>
