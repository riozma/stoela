<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'

interface ChatMessage {
  role: 'user' | 'assistant'
  content: string
}

const props = defineProps<{
  lagerId: string
  lagerName: string
  lagerStatus: string
  startDatum: string | null
  endDatum: string | null
  ort: string | null
}>()

const frage = ref('')
const sende = ref(false)
const ladeKontext = ref(false)
const fehler = ref('')
const kontextText = ref('')
const messages = ref<ChatMessage[]>([
  { role: 'assistant', content: 'Hoi! Frag mich alles zum aktuellen Lager. Ich antworte mit dem vorhandenen Lagerkontext.' },
])

function isoDate(value: string | null) {
  if (!value) return '–'
  return value.slice(0, 10)
}

async function kontextLaden() {
  ladeKontext.value = true
  fehler.value = ''

  const heute = new Date().toISOString().slice(0, 10)
  const [todosQ, bloeckeQ, tnQ, leiterQ] = await Promise.all([
    supabase
      .from('lager_todos')
      .select('titel, faellig_am, kategorie, zustaendig, aemtli_name')
      .eq('lager_id', props.lagerId)
      .eq('erledigt', false)
      .order('faellig_am', { ascending: true, nullsFirst: false })
      .limit(12),
    supabase
      .from('programmbloecke')
      .select('code, titel, tag, start_zeit, end_zeit, verantwortlich, ort')
      .eq('lager_id', props.lagerId)
      .gte('tag', heute)
      .order('tag', { ascending: true })
      .limit(10),
    supabase
      .from('anmeldungen_tn')
      .select('*', { count: 'exact', head: true })
      .eq('lager_id', props.lagerId),
    supabase
      .from('anmeldungen_leiter')
      .select('*', { count: 'exact', head: true })
      .eq('lager_id', props.lagerId)
      .in('status', ['angemeldet', 'bestaetigt']),
  ])

  ladeKontext.value = false
  if (todosQ.error || bloeckeQ.error || tnQ.error || leiterQ.error) {
    fehler.value = todosQ.error?.message || bloeckeQ.error?.message || tnQ.error?.message || leiterQ.error?.message || 'Kontext konnte nicht geladen werden.'
    return
  }

  const todoLines = (todosQ.data ?? []).map((t) => {
    const due = t.faellig_am ? ` bis ${t.faellig_am}` : ''
    const aemtli = t.aemtli_name ? ` (${t.aemtli_name})` : ''
    return `- ${t.titel}${aemtli}${due}`
  })
  const blockLines = (bloeckeQ.data ?? []).map((b) => {
    const zeit = b.start_zeit ? ` ${new Date(b.start_zeit).toISOString().slice(11, 16)}-${b.end_zeit ? new Date(b.end_zeit).toISOString().slice(11, 16) : '?'}` : ''
    return `- ${b.tag ?? '?'}${zeit}: [${b.code}] ${b.titel}${b.verantwortlich ? ` (${b.verantwortlich})` : ''}`
  })

  kontextText.value = [
    `Lager: ${props.lagerName}`,
    `Status: ${props.lagerStatus}`,
    `Zeitraum: ${isoDate(props.startDatum)} bis ${isoDate(props.endDatum)}`,
    `Ort: ${props.ort ?? '–'}`,
    `TN total: ${tnQ.count ?? 0}`,
    `Leiter total (angemeldet/bestaetigt): ${leiterQ.count ?? 0}`,
    'Offene Todos:',
    ...(todoLines.length ? todoLines : ['- keine']),
    'Nächste Programmblöcke:',
    ...(blockLines.length ? blockLines : ['- keine']),
  ].join('\n')
}

async function senden() {
  const q = frage.value.trim()
  if (!q || sende.value) return
  fehler.value = ''
  sende.value = true

  messages.value.push({ role: 'user', content: q })
  frage.value = ''

  if (!kontextText.value) await kontextLaden()

  const history = messages.value.slice(-10)
  const { data, error } = await supabase.functions.invoke('lager-chatbot', {
    body: {
      question: q,
      context: kontextText.value,
      history,
    },
  })

  sende.value = false
  if (error) {
    fehler.value = error.message
    messages.value.push({ role: 'assistant', content: 'Ich konnte gerade nicht antworten. Bitte versuche es erneut.' })
    return
  }

  messages.value.push({
    role: 'assistant',
    content: data?.answer?.toString?.() ?? 'Keine Antwort erhalten.',
  })
}

onMounted(kontextLaden)
</script>

<template>
  <section>
    <div class="kopf">
      <h2>Lager-Chatbot</h2>
      <button class="secondary klein" :disabled="ladeKontext" @click="kontextLaden">
        {{ ladeKontext ? 'Kontext lädt…' : 'Kontext aktualisieren' }}
      </button>
    </div>
    <p class="hint">Alle sehen diesen Chat. Antworten basieren auf kompaktem Supabase-Lagerkontext.</p>

    <div class="chat">
      <div v-for="(m, i) in messages" :key="i" class="msg" :class="m.role">
        <strong>{{ m.role === 'user' ? 'Du' : 'Bot' }}</strong>
        <p>{{ m.content }}</p>
      </div>
    </div>

    <form class="eingabe" @submit.prevent="senden">
      <textarea
        v-model="frage"
        rows="3"
        placeholder="z.B. Was ist als Nächstes fällig? Welche Programmblöcke stehen morgen an?"
      />
      <button type="submit" :disabled="sende || !frage.trim()">
        {{ sende ? 'Sende…' : 'Senden' }}
      </button>
    </form>

    <details class="kontext">
      <summary>Genutzter Kontext (kompakt)</summary>
      <pre>{{ kontextText }}</pre>
    </details>

    <p v-if="fehler" class="error">{{ fehler }}</p>
  </section>
</template>

<style scoped>
.kopf { display: flex; justify-content: space-between; align-items: center; gap: 0.6rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.chat {
  margin: 0.8rem 0;
  display: flex;
  flex-direction: column;
  gap: 0.55rem;
}
.msg {
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 0.55rem 0.7rem;
  background: var(--color-surface);
}
.msg.user { border-color: var(--color-accent); }
.msg strong { font-size: 0.8rem; color: var(--color-text-muted); }
.msg p { margin: 0.25rem 0 0; white-space: pre-wrap; }
.eingabe { display: flex; flex-direction: column; gap: 0.5rem; }
.kontext { margin-top: 0.8rem; }
.kontext pre {
  white-space: pre-wrap;
  font-size: 0.78rem;
  background: var(--color-surface-muted);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 0.6rem 0.7rem;
}
.error { color: var(--color-danger); margin-top: 0.65rem; }
button.klein { font-size: 0.8rem; padding: 0.3rem 0.55rem; }
</style>
