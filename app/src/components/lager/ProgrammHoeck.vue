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

interface HoeckRolle {
  id: string
  titel: string
  leiter_name: string | null
  start_zeit: string | null
  end_zeit: string | null
  dauer_min: number | null
  vorbereitung: string | null
  block_id: string | null
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
const rollen = ref<HoeckRolle[]>([])
const rollenForm = ref({ blockId: '', titel: '', leiterName: '', start: '09:00', ende: '10:00', vorbereitung: '' })

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

async function ladenRollen() {
  const { data } = await supabase.from('hoeck_rollen').select('*').eq('lager_id', props.lagerId).eq('tag', props.tag).order('sortierung')
  rollen.value = data ?? []
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
  await ladenRollen()
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
  if (error) { nachricht.value = error.message; return }
  nachricht.value = 'Höck-Notizen gespeichert.'
  await laden()
}

async function rolleHinzufuegen() {
  const start = rollenForm.value.start
  const end = rollenForm.value.ende
  const dauer = start && end ? Math.max(0, parseInt(end.slice(0, 2)) * 60 + parseInt(end.slice(3)) - parseInt(start.slice(0, 2)) * 60 - parseInt(start.slice(3))) : null
  await supabase.from('hoeck_rollen').insert({
    lager_id: props.lagerId,
    tag: props.tag,
    block_id: rollenForm.value.blockId || null,
    titel: rollenForm.value.titel || 'Programm',
    leiter_name: rollenForm.value.leiterName || null,
    start_zeit: start || null,
    end_zeit: end || null,
    dauer_min: dauer,
    vorbereitung: rollenForm.value.vorbereitung || null,
  })
  rollenForm.value = { blockId: '', titel: '', leiterName: '', start: '09:00', ende: '10:00', vorbereitung: '' }
  await ladenRollen()
}

async function rolleLoeschen(id: string) {
  await supabase.from('hoeck_rollen').delete().eq('id', id)
  await ladenRollen()
}
</script>

<template>
  <section class="programm-hoeck">
    <header @click="offen = !offen">
      <h3>Höck – {{ formatTag(tag) }}</h3>
      <span class="toggle">{{ offen ? '▾' : '▸' }}</span>
    </header>

    <div v-if="offen" class="hoeck-inhalt">
      <p class="hint">Flughöhe fürs Team: wer wo wann – Feinprogramm wird hier besprochen und zugewiesen.</p>

      <div v-if="bloeckeFuerTag.length" class="programm-vorschau">
        <h4>Grobprogramm heute</h4>
        <div v-for="b in bloeckeFuerTag" :key="b.id" class="block-karte">
          <strong>{{ formatZeit(b.start_zeit) }} · {{ b.code }} {{ b.nummer }} {{ b.titel }}</strong>
          <p v-if="b.verantwortlich">Verantwortlich: {{ b.verantwortlich }}</p>
        </div>
      </div>

      <h4>Rollen &amp; Zuteilung (Höck)</h4>
      <ul v-if="rollen.length" class="rollen-liste">
        <li v-for="r in rollen" :key="r.id">
          <strong>{{ r.titel }}</strong> – {{ r.leiter_name ?? '?' }}
          <span class="klein">{{ r.start_zeit?.slice(0,5) }}–{{ r.end_zeit?.slice(0,5) }}</span>
          <p v-if="r.vorbereitung" class="klein">Vorbereitung: {{ r.vorbereitung }}</p>
          <button class="secondary klein" @click="rolleLoeschen(r.id)">×</button>
        </li>
      </ul>
      <form class="rollen-form" @submit.prevent="rolleHinzufuegen">
        <select v-model="rollenForm.blockId">
          <option value="">Block (optional)</option>
          <option v-for="b in bloeckeFuerTag" :key="b.id" :value="b.id">{{ b.titel }}</option>
        </select>
        <input v-model="rollenForm.titel" placeholder="Rolle / Programm" required />
        <input v-model="rollenForm.leiterName" placeholder="Leiter/in" />
        <input v-model="rollenForm.start" type="time" />
        <input v-model="rollenForm.ende" type="time" />
        <input v-model="rollenForm.vorbereitung" placeholder="Vorbereitung?" />
        <button type="submit">+ Zuweisen</button>
      </form>

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
  display: flex; justify-content: space-between; align-items: center;
  padding: 0.75rem 1rem; cursor: pointer;
  background: var(--color-surface-muted); border-bottom: 1px solid var(--color-border);
}
header h3 { margin: 0; font-size: 1rem; }
.toggle { color: var(--color-text-muted); }
.hoeck-inhalt { padding: 1rem; }
.hint { color: var(--color-text-muted); font-size: 0.85rem; margin: 0.4rem 0; }
.meta { font-size: 0.8rem; color: var(--color-text-muted); margin-top: 0.5rem; }
.block-karte {
  background: var(--color-surface-muted); border-radius: var(--radius-md);
  padding: 0.6rem 0.85rem; margin-bottom: 0.5rem; font-size: 0.88rem;
}
.block-karte p { margin: 0.25rem 0; }
.rollen-liste { list-style: none; padding: 0; margin: 0.5rem 0; font-size: 0.88rem; }
.rollen-liste li { padding: 0.4rem 0; border-bottom: 1px solid var(--color-border); }
.rollen-form { display: flex; flex-wrap: wrap; gap: 0.4rem; margin: 0.5rem 0 1rem; align-items: end; }
.klein { font-size: 0.78rem; color: var(--color-text-muted); }
.notizen-label { display: block; font-size: 0.85rem; font-weight: 700; margin: 0.75rem 0 0.35rem; }
textarea { width: 100%; margin-bottom: 0.5rem; }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.45rem; margin-left: 0.35rem; }
</style>
