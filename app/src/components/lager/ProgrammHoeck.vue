<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { supabase } from '../../supabaseClient'

interface Block {
  id: string
  code: string
  nummer: string | null
  titel: string
  tag: string | null
  start_zeit: string | null
  end_zeit: string | null
  verantwortlich: string | null
  sicherheitsueberlegungen?: string | null
}

const props = defineProps<{
  lagerId: string
  tag: string
  bloecke: Block[]
  userId: string
  userName: string
}>()

const notizen = ref('')
const autorName = ref<string | null>(null)
const updatedAt = ref<string | null>(null)
const speichern = ref(false)
const nachricht = ref('')
const offen = ref(true)

const bloeckeFuerTag = computed(() =>
  props.bloecke
    .filter((b) => b.tag === props.tag)
    .sort((a, b) => (a.start_zeit ?? '').localeCompare(b.start_zeit ?? '')),
)

function formatTag(tag: string) {
  return new Intl.DateTimeFormat('de-CH', { weekday: 'long', day: 'numeric', month: 'long' }).format(new Date(tag + 'T00:00:00'))
}

function formatZeit(zeit: string | null) {
  if (!zeit) return '–'
  return new Intl.DateTimeFormat('de-CH', { hour: '2-digit', minute: '2-digit' }).format(new Date(zeit))
}

function formatDatumZeit(iso: string) {
  return new Intl.DateTimeFormat('de-CH', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(iso))
}

async function laden() {
  const { data } = await supabase
    .from('hoeck_notizen')
    .select('notizen, autor_name, updated_at')
    .eq('lager_id', props.lagerId)
    .eq('tag', props.tag)
    .maybeSingle()

  notizen.value = data?.notizen ?? ''
  autorName.value = data?.autor_name ?? null
  updatedAt.value = data?.updated_at ?? null
}

watch(() => props.tag, () => { laden() }, { immediate: true })

async function speichereNotizen() {
  speichern.value = true
  nachricht.value = ''
  const { error } = await supabase.from('hoeck_notizen').upsert(
    {
      lager_id: props.lagerId,
      tag: props.tag,
      notizen: notizen.value,
      updated_by: props.userId,
      autor_name: props.userName,
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'lager_id,tag' },
  )
  speichern.value = false
  if (error) {
    nachricht.value = error.message
    return
  }
  nachricht.value = 'Höck-Notizen gespeichert.'
  await laden()
}
</script>

<template>
  <section class="programm-hoeck">
    <header @click="offen = !offen">
      <h3>Höck – {{ formatTag(tag) }}</h3>
      <span class="toggle">{{ offen ? '▾' : '▸' }}</span>
    </header>

    <div v-if="offen" class="hoeck-inhalt">
      <p class="hint">Tagesbesprechung für alle Leiter – gleiche Ansicht für das ganze Team.</p>

      <div v-if="bloeckeFuerTag.length" class="programm-vorschau">
        <h4>Programm an diesem Tag</h4>
        <div v-for="b in bloeckeFuerTag" :key="b.id" class="block-karte">
          <strong>{{ formatZeit(b.start_zeit) }} · {{ b.code }} {{ b.nummer }} {{ b.titel }}</strong>
          <p v-if="b.verantwortlich">Verantwortlich: {{ b.verantwortlich }}</p>
          <p v-if="b.sicherheitsueberlegungen"><em>Sicherheit:</em> {{ b.sicherheitsueberlegungen }}</p>
        </div>
      </div>

      <label class="notizen-label">Notizen vom Höck</label>
      <textarea v-model="notizen" rows="5" placeholder="Besprochenes, offene Punkte, Erinnerungen..."></textarea>
      <button @click="speichereNotizen" :disabled="speichern">{{ speichern ? 'Speichere...' : 'Notizen speichern' }}</button>
      <p v-if="nachricht" class="hint">{{ nachricht }}</p>
      <p v-if="updatedAt" class="meta">Zuletzt von {{ autorName ?? 'Unbekannt' }} · {{ formatDatumZeit(updatedAt) }}</p>
    </div>
  </section>
</template>

<style scoped>
.programm-hoeck {
  margin: 1rem 0 1.5rem;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  overflow: hidden;
}
header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 0.75rem 1rem;
  cursor: pointer;
  background: var(--color-surface-muted);
  border-bottom: 1px solid var(--color-border);
}
header h3 { margin: 0; font-size: 1rem; }
.toggle { color: var(--color-text-muted); }
.hoeck-inhalt { padding: 1rem; }
.hint { color: var(--color-text-muted); font-size: 0.85rem; margin: 0.4rem 0; }
.meta { font-size: 0.8rem; color: var(--color-text-muted); margin-top: 0.5rem; }
.block-karte {
  background: var(--color-surface-muted);
  border-radius: var(--radius-md);
  padding: 0.6rem 0.85rem;
  margin-bottom: 0.5rem;
  font-size: 0.88rem;
}
.block-karte p { margin: 0.25rem 0; }
.notizen-label { display: block; font-size: 0.85rem; font-weight: 700; margin: 0.75rem 0 0.35rem; }
textarea { width: 100%; margin-bottom: 0.5rem; }
</style>
