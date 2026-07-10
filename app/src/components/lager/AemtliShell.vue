<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliTodos from './AemtliTodos.vue'
import { formatFaelligkeit, faelligStatus } from '../../lib/workflowUtils'

const props = defineProps<{
  lagerId: string
  aemtliId: string
  aemtliName: string
}>()

interface Link {
  titel: string
  url: string
}

const organisationId = ref<string | null>(null)
const beschreibung = ref('')
const hinweise = ref('')
const links = ref<Link[]>([])
const dokumenteLinks = ref<Link[]>([])
const dokumente = ref<{ id: string; titel: string; storage_path: string; dateiname: string | null }[]>([])
const funktionHinweis = ref('')
const funktionPosition = ref<'oben' | 'mitte' | 'unten'>('mitte')
const naechstesTodo = ref<{ titel: string; faellig_am: string | null } | null>(null)

async function ladeOrgId() {
  const { data } = await supabase
    .from('lager')
    .select('organisation_id')
    .eq('id', props.lagerId)
    .single()
  return data?.organisation_id ?? null
}

const bearbeitenModus = ref(false)
const speichern = ref(false)
const entwurf = ref({
  beschreibung: '',
  hinweise: '',
  links: [] as Link[],
  dokumenteLinks: [] as Link[],
  funktionHinweis: '',
  funktionPosition: 'mitte' as 'oben' | 'mitte' | 'unten',
})

async function laden() {
  const orgId = await ladeOrgId()
  const [{ data: meta }, { data: todos }] = await Promise.all([
    supabase
      .from('org_aemtli_meta')
      .select('beschreibung, hinweise_md, links, dokumente_links, funktion_hinweis, funktion_position')
      .eq('organisation_id', orgId)
      .eq('aemtli_id', props.aemtliId)
      .maybeSingle(),
    supabase
      .from('lager_todos')
      .select('titel, faellig_am, erledigt')
      .eq('lager_id', props.lagerId)
      .eq('aemtli_name', props.aemtliName)
      .eq('erledigt', false)
      .order('faellig_am', { ascending: true, nullsFirst: false })
      .limit(1),
  ])
  organisationId.value = orgId
  if (meta) {
    beschreibung.value = meta.beschreibung ?? ''
    hinweise.value = meta.hinweise_md ?? ''
    links.value = (meta.links as Link[]) ?? []
    dokumenteLinks.value = (meta.dokumente_links as Link[]) ?? []
    funktionHinweis.value = meta.funktion_hinweis ?? ''
    funktionPosition.value = (meta.funktion_position as typeof funktionPosition.value) ?? 'mitte'
  }
  if (orgId) {
    const { data: docs } = await supabase
      .from('org_aemtli_dokumente')
      .select('id, titel, storage_path, dateiname')
      .eq('organisation_id', orgId)
      .eq('aemtli_id', props.aemtliId)
      .order('created_at', { ascending: false })
    dokumente.value = docs ?? []
  }
  naechstesTodo.value = todos?.[0] ?? null
}

function bearbeitenStarten() {
  entwurf.value = {
    beschreibung: beschreibung.value,
    hinweise: hinweise.value,
    links: links.value.map((l) => ({ ...l })),
    dokumenteLinks: dokumenteLinks.value.map((l) => ({ ...l })),
    funktionHinweis: funktionHinweis.value,
    funktionPosition: funktionPosition.value,
  }
  bearbeitenModus.value = true
}

function linkHinzufuegen() {
  entwurf.value.links.push({ titel: '', url: '' })
}
function dokumentLinkHinzufuegen() {
  entwurf.value.dokumenteLinks.push({ titel: '', url: '' })
}
function linkEntfernen(i: number) {
  entwurf.value.links.splice(i, 1)
}

async function speichernUndSchliessen() {
  if (!organisationId.value) return
  speichern.value = true
  await supabase.from('org_aemtli_meta').upsert(
    {
      organisation_id: organisationId.value,
      aemtli_id: props.aemtliId,
      beschreibung: entwurf.value.beschreibung || null,
      hinweise_md: entwurf.value.hinweise || null,
      links: entwurf.value.links.filter((l) => l.titel.trim() || l.url.trim()),
      dokumente_links: entwurf.value.dokumenteLinks.filter((l) => l.titel.trim() || l.url.trim()),
      funktion_hinweis: entwurf.value.funktionHinweis || null,
      funktion_position: entwurf.value.funktionPosition,
    },
    { onConflict: 'organisation_id,aemtli_id' },
  )
  speichern.value = false
  bearbeitenModus.value = false
  await laden()
}

onMounted(laden)

function hinweisHtml(md: string) {
  return md.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>').replace(/\n/g, '<br>')
}

const todoStatus = computed(() =>
  naechstesTodo.value ? faelligStatus(naechstesTodo.value.faellig_am, false) : 'offen',
)
</script>

<template>
  <section class="aemtli-shell">
    <header class="shell-kopf">
      <div>
        <h2>{{ aemtliName }}</h2>
        <p v-if="beschreibung && !bearbeitenModus" class="beschreibung">{{ beschreibung }}</p>
      </div>
      <div class="shell-kopf-rechts">
        <div v-if="naechstesTodo" class="naechstes-todo" :class="todoStatus">
          <span class="label">Als Nächstes</span>
          <strong>{{ naechstesTodo.titel }}</strong>
          <span v-if="naechstesTodo.faellig_am" class="datum">{{ formatFaelligkeit(naechstesTodo.faellig_am) }}</span>
        </div>
        <button v-if="!bearbeitenModus" class="secondary" type="button" @click="bearbeitenStarten">
          Seite bearbeiten
        </button>
      </div>
    </header>

    <!-- Bearbeitungsmodus: Einleitung, Hinweise, Links, Funktions-Erklärung/-Platzierung -->
    <div v-if="bearbeitenModus" class="bearbeiten-box">
      <label>
        Kurzbeschreibung
        <input v-model="entwurf.beschreibung" placeholder="Ein Satz, worum es bei diesem Ämtli geht" />
      </label>
      <label>
        Hinweise / Anleitung
        <textarea v-model="entwurf.hinweise" rows="4" placeholder="Anleitung, Ablauf, was zu beachten ist..."></textarea>
      </label>

      <div class="links-editor">
        <span class="feld-label">Links (z.B. Vorlagen-Ordner)</span>
        <div v-for="(l, i) in entwurf.links" :key="i" class="link-zeile">
          <input v-model="l.titel" placeholder="Titel" />
          <input v-model="l.url" placeholder="https://..." />
          <button type="button" class="secondary klein" @click="linkEntfernen(i)">×</button>
        </div>
        <button type="button" class="secondary" @click="linkHinzufuegen">+ Link</button>
      </div>

      <div class="links-editor">
        <span class="feld-label">Drive / Dokumenten-Ordner (Mehrjahres)</span>
        <div v-for="(l, i) in entwurf.dokumenteLinks" :key="'d' + i" class="link-zeile">
          <input v-model="l.titel" placeholder="Titel" />
          <input v-model="l.url" placeholder="https://drive.google.com/..." />
          <button type="button" class="secondary klein" @click="entwurf.dokumenteLinks.splice(i, 1)">×</button>
        </div>
        <button type="button" class="secondary" @click="dokumentLinkHinzufuegen">+ Drive-Link</button>
      </div>

      <label>
        Erklärung zur eingebauten Funktion dieses Ämtlis
        <textarea
          v-model="entwurf.funktionHinweis"
          rows="2"
          placeholder="Falls die Funktion unten weitere Erklärung braucht..."
        ></textarea>
      </label>
      <label>
        Platzierung der Funktion auf der Seite
        <select v-model="entwurf.funktionPosition">
          <option value="oben">Oben (vor den Hinweisen)</option>
          <option value="mitte">Mitte (nach den Hinweisen, vor den ToDos)</option>
          <option value="unten">Unten (nach den ToDos)</option>
        </select>
      </label>

      <div class="bearbeiten-aktionen">
        <button type="button" class="secondary" @click="bearbeitenModus = false">Abbrechen</button>
        <button type="button" @click="speichernUndSchliessen" :disabled="speichern">
          {{ speichern ? 'Speichere...' : 'Speichern' }}
        </button>
      </div>
    </div>

    <!-- Ansicht: Einleitung → ToDos → Dokumente → Funktionen unten -->
    <template v-else>
      <div v-if="hinweise" class="hinweis-box" v-html="hinweisHtml(hinweise)" />

      <AemtliTodos :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName" />

      <div v-if="links.length || dokumenteLinks.length || dokumente.length" class="dokumente-box">
        <h3>Hilfsdokumente &amp; Links (Mehrjahres)</h3>
        <ul v-if="links.length" class="links-liste">
          <li v-for="(l, i) in links" :key="'l-' + i">
            <a :href="l.url" target="_blank" rel="noopener">{{ l.titel || l.url }}</a>
          </li>
        </ul>
        <ul v-if="dokumenteLinks.length" class="links-liste">
          <li v-for="(l, i) in dokumenteLinks" :key="'d-' + i">
            <a :href="l.url" target="_blank" rel="noopener">{{ l.titel || l.url }} (Ordner)</a>
          </li>
        </ul>
        <ul v-if="dokumente.length" class="links-liste">
          <li v-for="d in dokumente" :key="d.id">{{ d.titel || d.dateiname }}</li>
        </ul>
      </div>

      <div class="aemtli-funktionen">
        <h3 v-if="funktionHinweis">Funktionen dieses Ämtlis</h3>
        <p v-if="funktionHinweis" class="funktion-hinweis">{{ funktionHinweis }}</p>
        <slot />
      </div>
    </template>
  </section>
</template>

<style scoped>
.shell-kopf { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 0.75rem; margin-bottom: 0.75rem; }
.shell-kopf h2 { margin: 0 0 0.25rem; }
.shell-kopf-rechts { display: flex; align-items: center; gap: 0.6rem; flex-wrap: wrap; }
.beschreibung { color: var(--color-text-muted); font-size: 0.92rem; margin: 0; }
.naechstes-todo {
  background: var(--color-surface-muted); border: 1px solid var(--color-border);
  border-radius: var(--radius-md); padding: 0.55rem 0.85rem; min-width: 12rem;
}
.naechstes-todo.bald { border-color: #c98a3f; }
.naechstes-todo.ueberfaellig { border-color: var(--color-danger); }
.naechstes-todo .label { display: block; font-size: 0.7rem; text-transform: uppercase; color: var(--color-text-muted); }
.naechstes-todo .datum { display: block; font-size: 0.78rem; color: var(--color-text-muted); margin-top: 0.15rem; }
.hinweis-box {
  background: var(--color-surface-muted); border: 1px solid var(--color-border);
  border-radius: var(--radius-md); padding: 0.75rem 1rem; font-size: 0.88rem; line-height: 1.45; margin-bottom: 1rem;
}
.dokumente-box { margin: 1rem 0; padding: 0.75rem; border: 1px solid var(--color-border); border-radius: var(--radius-md); }
.dokumente-box h3 { margin: 0 0 0.5rem; font-size: 0.95rem; }
.aemtli-funktionen { margin-top: 1.5rem; padding-top: 1rem; border-top: 1px solid var(--color-border); }
.aemtli-funktionen h3 { margin: 0 0 0.75rem; font-size: 0.95rem; color: var(--color-text-muted); }
.funktion-hinweis { color: var(--color-text-muted); font-size: 0.88rem; margin: 0 0 0.75rem; font-style: italic; }
.bearbeiten-box {
  background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md);
  padding: 1rem 1.25rem; margin-bottom: 1.25rem; display: flex; flex-direction: column; gap: 0.85rem;
}
.bearbeiten-box label { display: flex; flex-direction: column; gap: 0.3rem; font-size: 0.85rem; color: var(--color-text-muted); }
.bearbeiten-box input,
.bearbeiten-box textarea,
.bearbeiten-box select { width: 100%; }
.links-editor { display: flex; flex-direction: column; gap: 0.4rem; }
.feld-label { font-size: 0.85rem; color: var(--color-text-muted); }
.link-zeile { display: flex; gap: 0.4rem; }
.link-zeile input { flex: 1; }
.bearbeiten-aktionen { display: flex; gap: 0.6rem; justify-content: flex-end; }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.45rem; }
</style>
