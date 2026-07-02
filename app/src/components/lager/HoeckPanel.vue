<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
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
  geschichte: string | null
  sicherheitsueberlegungen: string | null
  programmabschnitt: { zeit: string | null; programm: string; verantwortlich: string | null }[]
  material: { name: string; wer: string | null }[]
  notizen: string | null
}

const props = defineProps<{
  lagerId: string
  bloecke: Block[]
  userId: string
}>()

const emit = defineEmits<{ close: [] }>()

const morgen = computed(() => {
  const d = new Date()
  d.setDate(d.getDate() + 1)
  return d.toISOString().slice(0, 10)
})

const morgenBloecke = computed(() =>
  props.bloecke.filter((b) => b.tag === morgen.value).sort((a, b) => (a.start_zeit ?? '').localeCompare(b.start_zeit ?? '')),
)

const notizen = ref('')
const speichern = ref(false)
const nachricht = ref('')

function formatTag(tag: string) {
  return new Intl.DateTimeFormat('de-CH', { weekday: 'long', day: 'numeric', month: 'long' }).format(new Date(tag + 'T00:00:00'))
}

function formatZeit(zeit: string | null) {
  if (!zeit) return '–'
  return new Intl.DateTimeFormat('de-CH', { hour: '2-digit', minute: '2-digit' }).format(new Date(zeit))
}

onMounted(async () => {
  const { data } = await supabase.from('hoeck_notizen').select('notizen').eq('lager_id', props.lagerId).eq('tag', morgen.value).maybeSingle()
  notizen.value = data?.notizen ?? ''
})

async function speichereNotizen() {
  speichern.value = true
  await supabase.from('hoeck_notizen').upsert({
    lager_id: props.lagerId,
    tag: morgen.value,
    notizen: notizen.value,
    updated_by: props.userId,
    updated_at: new Date().toISOString(),
  }, { onConflict: 'lager_id,tag' })
  speichern.value = false
  nachricht.value = 'Notizen gespeichert.'
}
</script>

<template>
  <div class="hoeck-overlay" @click.self="emit('close')">
    <div class="hoeck-panel">
      <header>
        <h2>Höck – {{ formatTag(morgen) }}</h2>
        <button class="secondary klein" @click="emit('close')">Schliessen</button>
      </header>

      <p class="hint">Besprechung des Programms für morgen. Alle anwesenden Leiter können mitdiskutieren.</p>

      <section v-if="morgenBloecke.length">
        <h3>Programm morgen</h3>
        <div v-for="b in morgenBloecke" :key="b.id" class="block-karte">
          <strong>{{ formatZeit(b.start_zeit) }} · {{ b.code }} {{ b.nummer }} {{ b.titel }}</strong>
          <p v-if="b.verantwortlich">Verantwortlich: {{ b.verantwortlich }}</p>
          <p v-if="b.geschichte"><em>Geschichte:</em> {{ b.geschichte }}</p>
          <p v-if="b.sicherheitsueberlegungen"><em>Sicherheit:</em> {{ b.sicherheitsueberlegungen }}</p>
          <ul v-if="b.material?.length">
            <li v-for="(m, i) in b.material" :key="i">{{ m.name }} <span v-if="m.wer">({{ m.wer }})</span></li>
          </ul>
        </div>
      </section>
      <p v-else class="hint">Noch keine Programmblöcke für morgen erfasst.</p>

      <h3>Notizen vom Höck</h3>
      <textarea v-model="notizen" rows="6" placeholder="Besprochenes, offene Punkte, Erinnerungen..."></textarea>
      <button @click="speichereNotizen" :disabled="speichern">{{ speichern ? 'Speichere...' : 'Notizen speichern' }}</button>
      <p v-if="nachricht" class="hint">{{ nachricht }}</p>
    </div>
  </div>
</template>

<style scoped>
.hoeck-overlay {
  position: fixed; inset: 0; background: rgba(61, 50, 34, 0.45);
  display: flex; align-items: center; justify-content: center; z-index: 100; padding: 1rem;
}
.hoeck-panel {
  background: var(--color-bg); max-width: 640px; width: 100%; max-height: 90vh;
  overflow-y: auto; border-radius: var(--radius-lg); padding: 1.25rem 1.5rem;
  border: 1px solid var(--color-border);
}
header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.75rem; }
header h2 { margin: 0; font-size: 1.2rem; }
.hint { color: var(--color-text-muted); font-size: 0.85rem; }
.block-karte {
  background: var(--color-surface); border: 1px solid var(--color-border);
  border-radius: var(--radius-md); padding: 0.75rem 1rem; margin-bottom: 0.6rem; font-size: 0.9rem;
}
.block-karte p { margin: 0.3rem 0; }
textarea { width: 100%; margin: 0.5rem 0; }
button.klein { font-size: 0.75rem; padding: 0.25rem 0.6rem; }
</style>
