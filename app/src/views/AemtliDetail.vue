<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'

type BlockTyp = 'text' | 'link' | 'todos' | 'funktion'
interface Block {
  typ: BlockTyp
  titel: string
  inhalt: string | string[]
}
interface Aemtli {
  id: string
  name: string
  beschreibung: string | null
  seiten_inhalt: Block[]
}
interface Learning {
  id: string
  text: string
  created_at: string
  lager_id: string | null
  lager_name?: string
}

const route = useRoute()
const aemtliId = route.params.id as string
const { session } = useAuth()

const aemtli = ref<Aemtli | null>(null)
const bloecke = ref<Block[]>([])
const loading = ref(true)
const error = ref('')
const bearbeitenModus = ref(false)
const speichern = ref(false)

const learnings = ref<Learning[]>([])
const neuesLearning = ref('')
const learningSpeichern = ref(false)

const leerText = (): Block => ({ typ: 'text', titel: 'Neuer Abschnitt', inhalt: '' })

async function laden() {
  loading.value = true
  const { data, error: err } = await supabase
    .from('aemtli')
    .select('id, name, beschreibung, seiten_inhalt')
    .eq('id', aemtliId)
    .single()
  if (err || !data) {
    error.value = err?.message ?? 'Ämtli nicht gefunden.'
    loading.value = false
    return
  }
  aemtli.value = data
  bloecke.value = JSON.parse(JSON.stringify(data.seiten_inhalt ?? []))
  loading.value = false
}

async function ladeLearnings() {
  const { data, error: err } = await supabase
    .from('aemtli_learnings')
    .select('id, text, created_at, lager_id, lager:lager_id (name)')
    .eq('aemtli_id', aemtliId)
    .order('created_at', { ascending: false })
  if (err) return
  learnings.value = (data ?? []).map((l: any) => ({
    id: l.id,
    text: l.text,
    created_at: l.created_at,
    lager_id: l.lager_id,
    lager_name: l.lager?.name,
  }))
}

function blockHinzufuegen(typ: BlockTyp) {
  const basis = leerText()
  basis.typ = typ
  if (typ === 'todos') basis.inhalt = []
  if (typ === 'link') basis.titel = 'Link'
  if (typ === 'funktion') {
    basis.titel = 'Funktion'
    basis.inhalt = 'einkaufsliste'
  }
  bloecke.value.push(basis)
}

function blockEntfernen(index: number) {
  bloecke.value.splice(index, 1)
}

function blockVerschieben(index: number, richtung: -1 | 1) {
  const ziel = index + richtung
  if (ziel < 0 || ziel >= bloecke.value.length) return
  const [block] = bloecke.value.splice(index, 1)
  bloecke.value.splice(ziel, 0, block)
}

function todoHinzufuegen(block: Block) {
  if (!Array.isArray(block.inhalt)) block.inhalt = []
  block.inhalt.push('')
}

function todoEntfernen(block: Block, i: number) {
  if (Array.isArray(block.inhalt)) block.inhalt.splice(i, 1)
}

async function speichernUndSchliessen() {
  if (!aemtli.value) return
  speichern.value = true
  const { error: err } = await supabase.from('aemtli').update({ seiten_inhalt: bloecke.value }).eq('id', aemtliId)
  speichern.value = false
  if (err) {
    error.value = err.message
    return
  }
  bearbeitenModus.value = false
  await laden()
}

async function learningHinzufuegen() {
  if (!neuesLearning.value.trim()) return
  learningSpeichern.value = true
  await supabase.from('aemtli_learnings').insert({
    aemtli_id: aemtliId,
    autor_id: session.value?.user.id ?? null,
    text: neuesLearning.value.trim(),
  })
  learningSpeichern.value = false
  neuesLearning.value = ''
  await ladeLearnings()
}

onMounted(async () => {
  await Promise.all([laden(), ladeLearnings()])
})
</script>

<template>
  <main>
    <p><router-link to="/aemtli">← Zu allen Ämtli</router-link></p>

    <p v-if="loading">Lade...</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <template v-else-if="aemtli">
      <header class="kopf">
        <h1>{{ aemtli.name }}</h1>
        <button class="secondary" @click="bearbeitenModus = !bearbeitenModus">
          {{ bearbeitenModus ? 'Abbrechen' : 'Bearbeiten' }}
        </button>
      </header>
      <p v-if="aemtli.beschreibung" class="hint">{{ aemtli.beschreibung }}</p>

      <!-- Ansicht -->
      <div v-if="!bearbeitenModus" class="bloecke">
        <p v-if="!bloecke.length" class="hint">
          Diese Ämtli-Seite ist noch leer. Klick auf „Bearbeiten", um Anleitungen, Links, Standard-ToDos oder
          Funktionen hinzuzufügen.
        </p>
        <section v-for="(b, i) in bloecke" :key="i" class="block">
          <h3>{{ b.titel }}</h3>
          <p v-if="b.typ === 'text'">{{ b.inhalt }}</p>
          <a v-else-if="b.typ === 'link'" :href="b.inhalt as string" target="_blank" rel="noopener">{{ b.inhalt }}</a>
          <ul v-else-if="b.typ === 'todos'">
            <li v-for="(todo, ti) in b.inhalt as string[]" :key="ti">{{ todo }}</li>
          </ul>
          <p v-else-if="b.typ === 'funktion'" class="hint">Funktion „{{ b.inhalt }}" (folgt).</p>
        </section>
      </div>

      <!-- Bearbeitungsmodus -->
      <div v-else class="bloecke">
        <section v-for="(b, i) in bloecke" :key="i" class="block block-edit">
          <div class="block-kopf">
            <input v-model="b.titel" class="titel-input" />
            <div class="block-aktionen">
              <button class="secondary" type="button" @click="blockVerschieben(i, -1)" :disabled="i === 0">↑</button>
              <button class="secondary" type="button" @click="blockVerschieben(i, 1)" :disabled="i === bloecke.length - 1">↓</button>
              <button class="secondary" type="button" @click="blockEntfernen(i)">Entfernen</button>
            </div>
          </div>

          <textarea v-if="b.typ === 'text'" v-model="b.inhalt as string" rows="3" placeholder="Text..."></textarea>
          <input v-else-if="b.typ === 'link'" v-model="b.inhalt as string" placeholder="https://..." />
          <div v-else-if="b.typ === 'todos'">
            <div v-for="(todo, ti) in b.inhalt as string[]" :key="ti" class="todo-zeile">
              <input v-model="(b.inhalt as string[])[ti]" placeholder="ToDo..." />
              <button class="secondary" type="button" @click="todoEntfernen(b, ti)">×</button>
            </div>
            <button class="secondary" type="button" @click="todoHinzufuegen(b)">+ ToDo</button>
          </div>
          <input v-else-if="b.typ === 'funktion'" v-model="b.inhalt as string" placeholder="z.B. einkaufsliste" />
        </section>

        <div class="block-hinzufuegen">
          <span class="hint">Abschnitt hinzufügen:</span>
          <button class="secondary" type="button" @click="blockHinzufuegen('text')">Text</button>
          <button class="secondary" type="button" @click="blockHinzufuegen('link')">Link</button>
          <button class="secondary" type="button" @click="blockHinzufuegen('todos')">ToDo-Liste</button>
          <button class="secondary" type="button" @click="blockHinzufuegen('funktion')">Funktion</button>
        </div>

        <button @click="speichernUndSchliessen" :disabled="speichern">
          {{ speichern ? 'Speichere...' : 'Speichern' }}
        </button>
      </div>

      <h2>Learnings</h2>
      <p class="hint">Wissen, das von Jahr zu Jahr weitergegeben werden soll -- nicht an ein einzelnes Lager gebunden.</p>
      <ul v-if="learnings.length" class="learnings-liste">
        <li v-for="l in learnings" :key="l.id">
          <span>{{ l.text }}</span>
          <span class="hint" v-if="l.lager_name"> – {{ l.lager_name }}</span>
        </li>
      </ul>
      <p v-else class="hint">Noch keine Learnings festgehalten.</p>

      <form @submit.prevent="learningHinzufuegen" class="inline-form">
        <input v-model="neuesLearning" placeholder="Neues Learning festhalten..." />
        <button type="submit" :disabled="learningSpeichern">{{ learningSpeichern ? 'Speichere...' : 'Hinzufügen' }}</button>
      </form>
    </template>
  </main>
</template>

<style scoped>
main {
  max-width: 700px;
  margin: 2rem auto;
  padding: 0 1rem;
}
.kopf {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.hint {
  color: var(--color-text-muted);
  font-size: 0.9rem;
}
.bloecke {
  margin: 1.5rem 0;
  display: flex;
  flex-direction: column;
  gap: 1rem;
}
.block {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 0.9rem 1.1rem;
}
.block h3 {
  margin: 0 0 0.4rem;
  font-size: 1rem;
}
.block-kopf {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 0.5rem;
  margin-bottom: 0.5rem;
}
.titel-input {
  font-weight: 700;
  flex: 1;
}
.block-aktionen {
  display: flex;
  gap: 0.3rem;
}
.block-edit textarea,
.block-edit input {
  width: 100%;
}
.todo-zeile {
  display: flex;
  gap: 0.4rem;
  margin-bottom: 0.4rem;
}
.todo-zeile input {
  flex: 1;
}
.block-hinzufuegen {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  align-items: center;
}
.learnings-liste {
  list-style: none;
  padding: 0;
  margin: 1rem 0;
}
.learnings-liste li {
  padding: 0.4rem 0;
  border-bottom: 1px solid var(--color-border);
}
.inline-form {
  display: flex;
  gap: 0.6rem;
  margin-top: 0.75rem;
}
.inline-form input {
  flex: 1;
}
.error {
  color: var(--color-danger);
}
</style>
