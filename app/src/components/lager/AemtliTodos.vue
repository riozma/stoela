<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { initialTodosForAemtli, type AemtliTodo } from '../../lib/aemtliDefaultTodos'

const props = defineProps<{
  lagerId: string
  aemtliId: string
  aemtliName: string
}>()

const zuweisungId = ref<string | null>(null)
const todos = ref<AemtliTodo[]>([])
const neuerText = ref('')
const laden = ref(true)
const fehler = ref('')

const organisationId = ref<string | null>(null)
const vorlageBearbeiten = ref(false)
const vorlage = ref<AemtliTodo[]>([])
const neuerVorlagenText = ref('')
const vorlageSpeichern = ref(false)

const offen = computed(() => todos.value.filter((t) => !t.done).length)
const erledigt = computed(() => todos.value.filter((t) => t.done).length)

function istPlatzhalter(liste: AemtliTodo[]) {
  return liste.length === 1 && liste[0].text.startsWith('Aufgaben für ')
}

// Die org-weite Vorlage (org_aemtli_meta.default_checkliste) ist die
// eigentliche, jahresübergreifend editierbare Quelle für "Standard-ToDos,
// die jedes Jahr neu kommen". Sie wird beim ersten Gebrauch eines Ämtlis
// aus der hartcodierten Fallback-Liste befüllt, ist danach aber frei
// bearbeitbar und wirkt für alle künftigen Lagerjahre.
async function ladeOrgUndVorlage(): Promise<AemtliTodo[]> {
  const { data: org } = await supabase.from('organisation').select('id').eq('slug', 'stoeckli').maybeSingle()
  organisationId.value = org?.id ?? null

  const { data: meta } = await supabase
    .from('org_aemtli_meta')
    .select('default_checkliste')
    .eq('aemtli_id', props.aemtliId)
    .maybeSingle()

  const bestehende = (meta?.default_checkliste as AemtliTodo[]) ?? []
  if (bestehende.length) {
    vorlage.value = bestehende
    return bestehende
  }

  const fallback = initialTodosForAemtli(props.aemtliName)
  vorlage.value = fallback
  if (organisationId.value) {
    await supabase.from('org_aemtli_meta').upsert(
      { organisation_id: organisationId.value, aemtli_id: props.aemtliId, default_checkliste: fallback },
      { onConflict: 'organisation_id,aemtli_id' },
    )
  }
  return fallback
}

async function vorlageSpeichernUndSchliessen() {
  if (!organisationId.value) return
  vorlageSpeichern.value = true
  await supabase.from('org_aemtli_meta').upsert(
    { organisation_id: organisationId.value, aemtli_id: props.aemtliId, default_checkliste: vorlage.value },
    { onConflict: 'organisation_id,aemtli_id' },
  )
  vorlageSpeichern.value = false
  vorlageBearbeiten.value = false
}

function vorlageTodoHinzufuegen() {
  const text = neuerVorlagenText.value.trim()
  if (!text) return
  vorlage.value.push({ id: crypto.randomUUID(), text, done: false })
  neuerVorlagenText.value = ''
}

function vorlageTodoEntfernen(id: string) {
  vorlage.value = vorlage.value.filter((t) => t.id !== id)
}

async function ensureZuweisung() {
  const { data: existing } = await supabase
    .from('aemtli_zuweisungen')
    .select('id, checkliste')
    .eq('lager_id', props.lagerId)
    .eq('aemtli_id', props.aemtliId)
    .maybeSingle()

  if (existing) {
    zuweisungId.value = existing.id
    const liste = (existing.checkliste as AemtliTodo[]) ?? []
    if (!liste.length || istPlatzhalter(liste)) {
      todos.value = await ladeOrgUndVorlage()
      await speichern()
    } else {
      todos.value = liste
      await ladeOrgUndVorlage()
    }
    return
  }

  const initial = await ladeOrgUndVorlage()
  const { data, error } = await supabase
    .from('aemtli_zuweisungen')
    .insert({
      lager_id: props.lagerId,
      aemtli_id: props.aemtliId,
      checkliste: initial,
      status: 'in_arbeit',
    })
    .select('id')
    .single()

  if (error) {
    fehler.value = error.message
    return
  }
  zuweisungId.value = data.id
  todos.value = initial
}

async function speichern() {
  if (!zuweisungId.value) return
  const erledigtAlles = todos.value.length > 0 && todos.value.every((t) => t.done)
  await supabase
    .from('aemtli_zuweisungen')
    .update({
      checkliste: todos.value,
      status: erledigtAlles ? 'erledigt' : todos.value.some((t) => t.done) ? 'in_arbeit' : 'offen',
    })
    .eq('id', zuweisungId.value)
}

async function toggle(todo: AemtliTodo) {
  todo.done = !todo.done
  await speichern()
}

async function hinzufuegen() {
  const text = neuerText.value.trim()
  if (!text) return
  todos.value.push({ id: crypto.randomUUID(), text, done: false })
  neuerText.value = ''
  await speichern()
}

async function entfernen(id: string) {
  todos.value = todos.value.filter((t) => t.id !== id)
  await speichern()
}

onMounted(async () => {
  await ensureZuweisung()
  laden.value = false
})
</script>

<template>
  <section class="aemtli-todos">
    <header>
      <h3>Aufgaben ({{ aemtliName }})</h3>
      <span class="stats">{{ offen }} offen · {{ erledigt }} erledigt</span>
    </header>

    <p v-if="fehler" class="error">{{ fehler }}</p>
    <p v-if="laden" class="hint">Lade Aufgaben...</p>

    <ul v-else class="todo-liste">
      <li v-for="t in todos" :key="t.id" :class="{ done: t.done }">
        <label>
          <input type="checkbox" :checked="t.done" @change="toggle(t)" />
          <input class="text-input" v-model="t.text" @change="speichern" />
        </label>
        <button type="button" class="secondary klein" @click="entfernen(t.id)">×</button>
      </li>
    </ul>

    <form class="inline-form" @submit.prevent="hinzufuegen">
      <input v-model="neuerText" placeholder="Neue Aufgabe..." />
      <button type="submit">Hinzufügen</button>
    </form>

    <button type="button" class="secondary vorlage-link" @click="vorlageBearbeiten = !vorlageBearbeiten">
      {{ vorlageBearbeiten ? 'Vorlage schliessen' : 'Standard-Vorlage fürs nächste Jahr bearbeiten' }}
    </button>

    <div v-if="vorlageBearbeiten" class="vorlage-box">
      <p class="hint">
        Diese Liste gilt für alle künftigen Lagerjahre als Ausgangspunkt für dieses Ämtli – unabhängig von den
        Häkchen oben.
      </p>
      <ul class="todo-liste">
        <li v-for="t in vorlage" :key="t.id">
          <input class="text-input" v-model="t.text" />
          <button type="button" class="secondary klein" @click="vorlageTodoEntfernen(t.id)">×</button>
        </li>
      </ul>
      <form class="inline-form" @submit.prevent="vorlageTodoHinzufuegen">
        <input v-model="neuerVorlagenText" placeholder="Neuer Vorlage-Punkt..." />
        <button type="submit">Hinzufügen</button>
      </form>
      <button type="button" @click="vorlageSpeichernUndSchliessen" :disabled="vorlageSpeichern">
        {{ vorlageSpeichern ? 'Speichere...' : 'Vorlage speichern' }}
      </button>
    </div>
  </section>
</template>

<style scoped>
.aemtli-todos {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 1rem;
  margin-bottom: 1.25rem;
}
header { display: flex; justify-content: space-between; align-items: baseline; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 0.75rem; }
header h3 { margin: 0; font-size: 1rem; }
.stats { font-size: 0.8rem; color: var(--color-text-muted); }
.todo-liste { list-style: none; padding: 0; margin: 0 0 0.75rem; }
.todo-liste li {
  display: flex; align-items: center; justify-content: space-between; gap: 0.5rem;
  padding: 0.35rem 0; border-bottom: 1px solid var(--color-border);
}
.todo-liste label { display: flex; align-items: center; gap: 0.5rem; flex: 1; font-size: 0.9rem; }
.text-input {
  flex: 1;
  border: none;
  background: transparent;
  padding: 0.15rem 0.3rem;
  font-size: inherit;
  color: inherit;
}
.text-input:hover,
.text-input:focus {
  background: var(--color-surface-muted);
  border-radius: var(--radius-md);
}
.todo-liste li.done .text-input { text-decoration: line-through; color: var(--color-text-muted); }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; }
.inline-form input { flex: 1; min-width: 180px; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.error { color: var(--color-danger); }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.45rem; }
.vorlage-link { margin-top: 0.9rem; font-size: 0.82rem; }
.vorlage-box {
  margin-top: 0.75rem;
  padding: 0.85rem;
  background: var(--color-surface-muted);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
}
</style>
