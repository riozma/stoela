<script setup lang="ts">
import { nextTick, onMounted, ref, watch } from 'vue'
import { supabase } from '../../supabaseClient'

interface ChatMessage {
  id: string
  role: 'user' | 'assistant'
  content: string
  topics?: string[]
  ts: number
}

const props = defineProps<{
  lagerId: string
  lagerName: string
}>()

const frage = ref('')
const sende = ref(false)
const fehler = ref('')
const messages = ref<ChatMessage[]>([])
const chatEndRef = ref<HTMLElement | null>(null)
const chatBoxRef = ref<HTMLElement | null>(null)

let msgCounter = 0
function neueId() {
  msgCounter += 1
  return `msg-${msgCounter}`
}

function zeitFormat(ts: number) {
  return new Date(ts).toLocaleTimeString('de-CH', { hour: '2-digit', minute: '2-digit' })
}

async function scrollNachUnten() {
  await nextTick()
  chatEndRef.value?.scrollIntoView({ behavior: 'smooth', block: 'end' })
}

function begruessung() {
  messages.value = [{
    id: neueId(),
    role: 'assistant',
    content: `Hoi! Ich bin der Lager-Assistent für «${props.lagerName}». Stell mir Fragen zu Programm, Todos, Leitern, Teilnehmern, Gruppen oder Ämtli – ich lese die passenden Daten live aus der Datenbank.`,
    ts: Date.now(),
  }]
}

async function senden() {
  const q = frage.value.trim()
  if (!q || sende.value) return
  fehler.value = ''
  sende.value = true

  messages.value.push({ id: neueId(), role: 'user', content: q, ts: Date.now() })
  frage.value = ''
  await scrollNachUnten()

  const history = messages.value
    .filter((m) => m.role === 'user' || m.role === 'assistant')
    .slice(-10)
    .map((m) => ({ role: m.role, content: m.content }))

  const { data, error } = await supabase.functions.invoke('lager-chatbot', {
    body: {
      question: q,
      lagerId: props.lagerId,
      history,
    },
  })

  sende.value = false

  if (error) {
    fehler.value = error.message
    messages.value.push({
      id: neueId(),
      role: 'assistant',
      content: 'Ich konnte gerade nicht antworten. Bitte versuche es erneut.',
      ts: Date.now(),
    })
    await scrollNachUnten()
    return
  }

  messages.value.push({
    id: neueId(),
    role: 'assistant',
    content: data?.answer?.toString?.() ?? 'Keine Antwort erhalten.',
    topics: Array.isArray(data?.topics) ? data.topics : undefined,
    ts: Date.now(),
  })
  await scrollNachUnten()
}

function eingabeKeydown(e: KeyboardEvent) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault()
    senden()
  }
}

watch(() => props.lagerId, () => {
  begruessung()
})

onMounted(() => {
  begruessung()
})
</script>

<template>
  <section class="chatbot">
    <header class="chat-kopf">
      <div>
        <h2>Lager-Chat</h2>
        <p class="hint">Antworten basieren auf Live-Daten aus Supabase – je nach Frage werden relevante Bereiche geladen.</p>
      </div>
    </header>

    <div ref="chatBoxRef" class="chat-verlauf">
      <article
        v-for="m in messages"
        :key="m.id"
        class="bubble-wrap"
        :class="m.role"
      >
        <div class="bubble-meta">
          <span class="avatar" :class="m.role">{{ m.role === 'user' ? 'Du' : 'AI' }}</span>
          <span class="zeit">{{ zeitFormat(m.ts) }}</span>
        </div>
        <div class="bubble" :class="m.role">
          <p>{{ m.content }}</p>
          <div v-if="m.topics?.length" class="topic-chips">
            <span v-for="t in m.topics" :key="t" class="chip">{{ t }}</span>
          </div>
        </div>
      </article>

      <article v-if="sende" class="bubble-wrap assistant">
        <div class="bubble-meta">
          <span class="avatar assistant">AI</span>
        </div>
        <div class="bubble assistant typing">
          <span class="dot" />
          <span class="dot" />
          <span class="dot" />
        </div>
      </article>

      <div ref="chatEndRef" class="chat-end" />
    </div>

    <form class="chat-eingabe" @submit.prevent="senden">
      <textarea
        v-model="frage"
        rows="2"
        placeholder="Frage stellen… (Enter = Senden, Shift+Enter = neue Zeile)"
        :disabled="sende"
        @keydown="eingabeKeydown"
      />
      <button type="submit" :disabled="sende || !frage.trim()">
        {{ sende ? '…' : 'Senden' }}
      </button>
    </form>

    <p v-if="fehler" class="error">{{ fehler }}</p>
  </section>
</template>

<style scoped>
.chatbot {
  display: flex;
  flex-direction: column;
  min-height: min(72vh, 720px);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface);
  overflow: hidden;
}

.chat-kopf {
  padding: 0.85rem 1rem;
  border-bottom: 1px solid var(--color-border);
  background: var(--color-surface-muted);
}

.chat-kopf h2 { margin: 0 0 0.2rem; font-size: 1.05rem; }
.hint { margin: 0; color: var(--color-text-muted); font-size: 0.84rem; }

.chat-verlauf {
  flex: 1;
  overflow-y: auto;
  padding: 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.85rem;
  background: linear-gradient(180deg, var(--color-surface) 0%, var(--color-surface-muted) 100%);
}

.bubble-wrap {
  display: flex;
  flex-direction: column;
  max-width: 88%;
}

.bubble-wrap.user {
  align-self: flex-end;
  align-items: flex-end;
}

.bubble-wrap.assistant {
  align-self: flex-start;
  align-items: flex-start;
}

.bubble-meta {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  margin-bottom: 0.2rem;
}

.avatar {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1.6rem;
  height: 1.6rem;
  border-radius: 999px;
  font-size: 0.62rem;
  font-weight: 700;
}

.avatar.user {
  background: var(--color-accent);
  color: #fff;
}

.avatar.assistant {
  background: #e8edf3;
  color: #334155;
}

.zeit {
  font-size: 0.72rem;
  color: var(--color-text-muted);
}

.bubble {
  border-radius: 1rem;
  padding: 0.65rem 0.85rem;
  line-height: 1.45;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.04);
}

.bubble.user {
  background: var(--color-accent);
  color: #fff;
  border-bottom-right-radius: 0.25rem;
}

.bubble.assistant {
  background: #fff;
  border: 1px solid var(--color-border);
  border-bottom-left-radius: 0.25rem;
}

.bubble p {
  margin: 0;
  white-space: pre-wrap;
}

.topic-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 0.3rem;
  margin-top: 0.45rem;
}

.chip {
  font-size: 0.68rem;
  padding: 0.12rem 0.45rem;
  border-radius: 999px;
  background: var(--color-surface-muted);
  color: var(--color-text-muted);
  border: 1px solid var(--color-border);
}

.bubble.typing {
  display: inline-flex;
  gap: 0.28rem;
  align-items: center;
  min-width: 3.2rem;
  min-height: 1.6rem;
}

.dot {
  width: 0.45rem;
  height: 0.45rem;
  border-radius: 999px;
  background: #94a3b8;
  animation: bounce 1.2s infinite ease-in-out;
}

.dot:nth-child(2) { animation-delay: 0.15s; }
.dot:nth-child(3) { animation-delay: 0.3s; }

@keyframes bounce {
  0%, 80%, 100% { transform: translateY(0); opacity: 0.5; }
  40% { transform: translateY(-4px); opacity: 1; }
}

.chat-eingabe {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 0.55rem;
  align-items: end;
  padding: 0.75rem 0.85rem;
  border-top: 1px solid var(--color-border);
  background: var(--color-surface);
}

.chat-eingabe textarea {
  resize: none;
  min-height: 2.6rem;
  max-height: 8rem;
}

.chat-eingabe button {
  min-width: 5.5rem;
}

.chat-end { height: 1px; }

.error {
  margin: 0;
  padding: 0.5rem 0.85rem 0.75rem;
  color: var(--color-danger);
  font-size: 0.86rem;
}
</style>
