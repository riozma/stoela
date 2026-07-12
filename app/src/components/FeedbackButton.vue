<script setup lang="ts">
import { ref } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'

const { session } = useAuth()
const route = useRoute()

const offen = ref(false)
const text = ref('')
const speichern = ref(false)
const gesendet = ref(false)
const fehler = ref('')

function oeffnen() {
  offen.value = true
  gesendet.value = false
  fehler.value = ''
}

async function absenden() {
  if (!text.value.trim() || !session.value) return
  speichern.value = true
  fehler.value = ''
  const { error } = await supabase.from('app_feedback').insert({
    profile_id: session.value.user.id,
    email: session.value.user.email,
    text: text.value.trim(),
    seite_pfad: route.fullPath,
    seite_titel: (route.meta?.titel as string | undefined) ?? route.name?.toString() ?? null,
    app_commit: (import.meta.env.VITE_APP_COMMIT as string | undefined) ?? null,
  })
  speichern.value = false
  if (error) { fehler.value = error.message; return }
  text.value = ''
  gesendet.value = true
}
</script>

<template>
  <div class="feedback-wrap">
    <button type="button" class="feedback-btn" title="Feedback zur Seite geben" @click="oeffnen">💬</button>
    <div v-if="offen" class="feedback-overlay" @click.self="offen = false">
      <div class="feedback-karte">
        <h3>Feedback zu dieser Seite</h3>
        <p class="hint">Deine Rückmeldung geht direkt an die Entwicklung – danke!</p>
        <template v-if="!gesendet">
          <textarea v-model="text" rows="4" placeholder="Was ist dir aufgefallen? Was fehlt, was stört, was wäre hilfreich?"></textarea>
          <p v-if="fehler" class="error">{{ fehler }}</p>
          <div class="aktionen">
            <button type="button" class="secondary" @click="offen = false">Abbrechen</button>
            <button type="button" :disabled="speichern || !text.trim()" @click="absenden">{{ speichern ? 'Sende…' : 'Senden' }}</button>
          </div>
        </template>
        <template v-else>
          <p class="ok">✓ Danke für dein Feedback!</p>
          <button type="button" @click="offen = false">Schliessen</button>
        </template>
      </div>
    </div>
  </div>
</template>

<style scoped>
.feedback-wrap { display: inline-flex; }
.feedback-btn {
  width: 2rem; height: 2rem; border-radius: 50%; border: 1px solid var(--color-border);
  background: var(--color-surface); font-size: 1rem; cursor: pointer; display: inline-flex;
  align-items: center; justify-content: center;
}
.feedback-btn:hover { background: var(--color-surface-muted); }
.feedback-overlay {
  position: fixed; inset: 0; background: rgba(0, 0, 0, 0.45); z-index: 300;
  display: flex; align-items: center; justify-content: center; padding: 1rem;
}
.feedback-karte {
  background: var(--color-surface); border-radius: var(--radius-md); padding: 1.25rem;
  max-width: 420px; width: 100%; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
}
.feedback-karte h3 { margin: 0 0 0.35rem; }
.hint { color: var(--color-text-muted); font-size: 0.85rem; margin: 0 0 0.75rem; }
textarea { width: 100%; box-sizing: border-box; }
.aktionen { display: flex; justify-content: flex-end; gap: 0.6rem; margin-top: 0.75rem; }
.ok { color: #2e7d32; font-weight: 600; }
.error { color: var(--color-danger); font-size: 0.85rem; }
</style>
