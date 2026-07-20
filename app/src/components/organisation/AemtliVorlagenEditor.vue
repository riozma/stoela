<script setup lang="ts">
import { ref, onMounted, watch } from 'vue'
import { supabase } from '../../supabaseClient'
import { initialTodosForAemtli, type AemtliTodo } from '../../lib/aemtliDefaultTodos'

const props = defineProps<{
  organisationId: string
  aemtliId: string
  aemtliName: string
}>()

interface Link {
  titel: string
  url: string
}

const laden = ref(true)
const speichern = ref(false)
const vorlageSpeichern = ref(false)
const gespeichert = ref(false)

const beschreibung = ref('')
const hinweise = ref('')
const links = ref<Link[]>([])
const dokumenteLinks = ref<Link[]>([])
const funktionHinweis = ref('')
const funktionPosition = ref<'oben' | 'mitte' | 'unten'>('mitte')
const dokumente = ref<{ id: string; titel: string; dateiname: string | null }[]>([])

const vorlage = ref<AemtliTodo[]>([])
const neuerVorlagenText = ref('')

async function laden_() {
  laden.value = true
  const [{ data: meta }, { data: docs }] = await Promise.all([
    supabase
      .from('org_aemtli_meta')
      .select('beschreibung, hinweise_md, links, dokumente_links, funktion_hinweis, funktion_position, default_checkliste')
      .eq('organisation_id', props.organisationId)
      .eq('aemtli_id', props.aemtliId)
      .maybeSingle(),
    supabase
      .from('org_aemtli_dokumente')
      .select('id, titel, dateiname')
      .eq('organisation_id', props.organisationId)
      .eq('aemtli_id', props.aemtliId)
      .order('created_at', { ascending: false }),
  ])
  beschreibung.value = meta?.beschreibung ?? ''
  hinweise.value = meta?.hinweise_md ?? ''
  links.value = ((meta?.links as Link[]) ?? []).map((l) => ({ ...l }))
  dokumenteLinks.value = ((meta?.dokumente_links as Link[]) ?? []).map((l) => ({ ...l }))
  funktionHinweis.value = meta?.funktion_hinweis ?? ''
  funktionPosition.value = (meta?.funktion_position as typeof funktionPosition.value) ?? 'mitte'
  dokumente.value = docs ?? []

  const bestehendeVorlage = (meta?.default_checkliste as AemtliTodo[]) ?? []
  vorlage.value = bestehendeVorlage.length ? bestehendeVorlage : initialTodosForAemtli(props.aemtliName)
  laden.value = false
}

onMounted(laden_)
watch(() => props.aemtliId, laden_)

function linkHinzufuegen() {
  links.value.push({ titel: '', url: '' })
}
function linkEntfernen(i: number) {
  links.value.splice(i, 1)
}
function dokumentLinkHinzufuegen() {
  dokumenteLinks.value.push({ titel: '', url: '' })
}

async function speichernHandler() {
  speichern.value = true
  gespeichert.value = false
  await supabase.from('org_aemtli_meta').upsert(
    {
      organisation_id: props.organisationId,
      aemtli_id: props.aemtliId,
      beschreibung: beschreibung.value || null,
      hinweise_md: hinweise.value || null,
      links: links.value.filter((l) => l.titel.trim() || l.url.trim()),
      dokumente_links: dokumenteLinks.value.filter((l) => l.titel.trim() || l.url.trim()),
      funktion_hinweis: funktionHinweis.value || null,
      funktion_position: funktionPosition.value,
    },
    { onConflict: 'organisation_id,aemtli_id' },
  )
  speichern.value = false
  gespeichert.value = true
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

async function vorlageSpeichernHandler() {
  vorlageSpeichern.value = true
  gespeichert.value = false
  await supabase.from('org_aemtli_meta').upsert(
    { organisation_id: props.organisationId, aemtli_id: props.aemtliId, default_checkliste: vorlage.value },
    { onConflict: 'organisation_id,aemtli_id' },
  )
  vorlageSpeichern.value = false
  gespeichert.value = true
}
</script>

<template>
  <section class="aemtli-vorlage">
    <h2>{{ aemtliName }} – Vorlage</h2>
    <p class="hint">
      Diese Angaben gelten für alle Lagerjahre. Sie werden in jedem Lager auf der jeweiligen Ämtli-Seite angezeigt
      (dort nur lesbar) und können ausschliesslich hier bearbeitet werden.
    </p>

    <p v-if="laden">Lade…</p>
    <template v-else>
      <div class="feld-box">
        <label>
          Kurzbeschreibung
          <input v-model="beschreibung" placeholder="Ein Satz, worum es bei diesem Ämtli geht" />
        </label>
        <label>
          Hinweise / Anleitung
          <textarea v-model="hinweise" rows="4" placeholder="Anleitung, Ablauf, was zu beachten ist..."></textarea>
        </label>

        <div class="links-editor">
          <span class="feld-label">Links (z.B. Vorlagen-Ordner)</span>
          <div v-for="(l, i) in links" :key="i" class="link-zeile">
            <input v-model="l.titel" placeholder="Titel" />
            <input v-model="l.url" placeholder="https://..." />
            <button type="button" class="secondary klein" @click="linkEntfernen(i)">×</button>
          </div>
          <button type="button" class="secondary" @click="linkHinzufuegen">+ Link</button>
        </div>

        <div class="links-editor">
          <span class="feld-label">Drive / Dokumenten-Ordner (Mehrjahres)</span>
          <div v-for="(l, i) in dokumenteLinks" :key="'d' + i" class="link-zeile">
            <input v-model="l.titel" placeholder="Titel" />
            <input v-model="l.url" placeholder="https://drive.google.com/..." />
            <button type="button" class="secondary klein" @click="dokumenteLinks.splice(i, 1)">×</button>
          </div>
          <button type="button" class="secondary" @click="dokumentLinkHinzufuegen">+ Drive-Link</button>
        </div>

        <ul v-if="dokumente.length" class="links-liste">
          <li v-for="d in dokumente" :key="d.id">{{ d.titel || d.dateiname }}</li>
        </ul>

        <label>
          Erklärung zur eingebauten Funktion dieses Ämtlis
          <textarea v-model="funktionHinweis" rows="2" placeholder="Falls die Funktion auf der Lagerseite weitere Erklärung braucht..."></textarea>
        </label>
        <label>
          Platzierung der Funktion auf der Lagerseite
          <select v-model="funktionPosition">
            <option value="oben">Oben (vor den Hinweisen)</option>
            <option value="mitte">Mitte (nach den Hinweisen, vor den ToDos)</option>
            <option value="unten">Unten (nach den ToDos)</option>
          </select>
        </label>

        <div class="bearbeiten-aktionen">
          <button type="button" @click="speichernHandler" :disabled="speichern">
            {{ speichern ? 'Speichere...' : 'Speichern' }}
          </button>
        </div>
      </div>

      <div class="feld-box">
        <h3>Standard-Aufgaben (Vorlage)</h3>
        <p class="hint">
          Diese Liste gilt als Ausgangspunkt für alle künftigen Lagerjahre. Im Lager selbst können pro Jahr eigene
          Häkchen/Anpassungen gemacht werden, ohne diese Vorlage zu verändern.
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
        <button type="button" @click="vorlageSpeichernHandler" :disabled="vorlageSpeichern">
          {{ vorlageSpeichern ? 'Speichere...' : 'Vorlage speichern' }}
        </button>
      </div>

      <p v-if="gespeichert" class="ok">Gespeichert.</p>
    </template>
  </section>
</template>

<style scoped>
.aemtli-vorlage h2 { margin: 0 0 0.25rem; }
.feld-box {
  background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md);
  padding: 1rem 1.25rem; margin: 1rem 0; display: flex; flex-direction: column; gap: 0.85rem;
}
.feld-box label { display: flex; flex-direction: column; gap: 0.3rem; font-size: 0.85rem; color: var(--color-text-muted); }
.feld-box input, .feld-box textarea, .feld-box select { width: 100%; }
.links-editor { display: flex; flex-direction: column; gap: 0.4rem; }
.feld-label { font-size: 0.85rem; color: var(--color-text-muted); }
.link-zeile { display: flex; gap: 0.4rem; }
.link-zeile input { flex: 1; }
.links-liste { list-style: none; padding: 0; margin: 0; font-size: 0.88rem; }
.bearbeiten-aktionen { display: flex; gap: 0.6rem; justify-content: flex-end; }
.todo-liste { list-style: none; padding: 0; margin: 0 0 0.75rem; }
.todo-liste li { display: flex; align-items: center; gap: 0.5rem; padding: 0.35rem 0; border-bottom: 1px solid var(--color-border); }
.text-input { flex: 1; border: none; background: transparent; padding: 0.15rem 0.3rem; font-size: inherit; color: inherit; }
.text-input:hover, .text-input:focus { background: var(--color-surface-muted); border-radius: var(--radius-md); }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 0.6rem; }
.inline-form input { flex: 1; min-width: 180px; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.ok { color: #2e7d32; font-size: 0.88rem; }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.45rem; }
</style>
