<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
import AppHeader from '../components/AppHeader.vue'

interface FeedbackEintrag {
  id: string
  email: string | null
  text: string
  seite_pfad: string | null
  app_commit: string | null
  created_at: string
}

const { session } = useAuth()
const eintraege = ref<FeedbackEintrag[]>([])
const laden = ref(true)
const kopiert = ref(false)

async function laden_() {
  laden.value = true
  const { data } = await supabase
    .from('app_feedback')
    .select('id, email, text, seite_pfad, app_commit, created_at')
    .order('created_at', { ascending: false })
  eintraege.value = (data ?? []) as FeedbackEintrag[]
  laden.value = false
}

onMounted(laden_)

function formatDatum(iso: string) {
  return new Intl.DateTimeFormat('de-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(iso))
}

const exportText = computed(() => {
  if (!eintraege.value.length) return ''
  return eintraege.value
    .map((e) => {
      const commit = e.app_commit ? e.app_commit.slice(0, 7) : 'unbekannt'
      return `[${formatDatum(e.created_at)} · Commit ${commit} · Seite: ${e.seite_pfad ?? '–'} · von ${e.email ?? 'unbekannt'}]\n${e.text}`
    })
    .join('\n\n---\n\n')
})

async function textKopieren() {
  if (!exportText.value) return
  await navigator.clipboard.writeText(exportText.value)
  kopiert.value = true
  setTimeout(() => { kopiert.value = false }, 2500)
}

function alsDateiHerunterladen() {
  const blob = new Blob([exportText.value], { type: 'text/plain;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `stoela_feedback_${new Date().toISOString().slice(0, 10)}.txt`
  a.click()
  URL.revokeObjectURL(url)
}
</script>

<template>
  <div>
    <div class="top-full"><AppHeader :show-alle-lager="true" /></div>
    <main>
      <h1>Feedback zur App</h1>
      <p class="hint">
        Rückmeldungen der Nutzenden mit Zeitpunkt, Seite und Commit-Stand. Text kann direkt in Claude Code
        eingefügt werden.
      </p>
      <p v-if="!session" class="hint">Bitte einloggen.</p>
      <template v-else>
        <div v-if="!laden" class="aktionen">
          <button type="button" :disabled="!eintraege.length" @click="textKopieren">
            {{ kopiert ? '✓ Kopiert' : 'Als Text kopieren' }}
          </button>
          <button type="button" class="secondary" :disabled="!eintraege.length" @click="alsDateiHerunterladen">Als .txt herunterladen</button>
        </div>
        <p v-if="laden" class="hint">Lade…</p>
        <p v-else-if="!eintraege.length" class="hint">Noch kein Feedback vorhanden (oder keine Berechtigung, welches zu sehen).</p>
        <div v-else class="liste">
          <article v-for="e in eintraege" :key="e.id" class="eintrag">
            <div class="meta">
              <span>{{ formatDatum(e.created_at) }}</span>
              <span v-if="e.app_commit">Commit {{ e.app_commit.slice(0, 7) }}</span>
              <span v-if="e.seite_pfad">{{ e.seite_pfad }}</span>
              <span v-if="e.email">{{ e.email }}</span>
            </div>
            <p class="text">{{ e.text }}</p>
          </article>
        </div>
      </template>
    </main>
  </div>
</template>

<style scoped>
.top-full { position: sticky; top: 0; z-index: 100; width: 100%; background: var(--color-surface); border-bottom: 1px solid var(--color-border); }
main { max-width: 720px; margin: 0 auto; padding: 1.25rem 1rem 3rem; }
.hint { color: var(--color-text-muted); font-size: 0.9rem; }
.aktionen { display: flex; gap: 0.6rem; margin: 1rem 0; }
.liste { display: flex; flex-direction: column; gap: 0.75rem; margin-top: 1rem; }
.eintrag { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.85rem 1rem; background: var(--color-surface); }
.meta { display: flex; flex-wrap: wrap; gap: 0.6rem; font-size: 0.75rem; color: var(--color-text-muted); margin-bottom: 0.4rem; }
.text { white-space: pre-wrap; margin: 0; }
</style>
