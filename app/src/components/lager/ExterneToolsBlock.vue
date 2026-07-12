<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'

interface OrgRessource {
  id: string
  typ: 'link' | 'zugang'
  titel: string
  url: string | null
  benutzername: string | null
  passwort: string | null
  notiz: string | null
  sichtbarkeit: string
  sortierung: number
  zugewiesene_profile_ids: string[]
}

const props = defineProps<{
  organisationId: string
  istLeitung?: boolean
}>()

const ressourcen = ref<OrgRessource[]>([])
const laden = ref(true)
const sichtbarePasswoerter = ref<Record<string, boolean>>({})
const bearbeitenOffen = ref(false)
const form = ref({ id: '', titel: '', url: '', notiz: '', benutzername: '', passwort: '' })
const speichern = ref(false)
const fehler = ref('')

async function laderRessourcen() {
  laden.value = true
  const { data } = await supabase.rpc('list_org_ressourcen', { p_organisation_id: props.organisationId })
  ressourcen.value = (data ?? []) as OrgRessource[]
  laden.value = false
}

onMounted(laderRessourcen)

const links = computed(() => ressourcen.value.filter((r) => r.typ === 'link'))

function loginFuer(titel: string): OrgRessource | null {
  return ressourcen.value.find((r) => r.typ === 'zugang' && r.titel.toLowerCase() === titel.toLowerCase()) ?? null
}

function togglePasswort(id: string) {
  sichtbarePasswoerter.value[id] = !sichtbarePasswoerter.value[id]
}

function neuStarten() {
  form.value = { id: '', titel: '', url: '', notiz: '', benutzername: '', passwort: '' }
  bearbeitenOffen.value = true
}

function bearbeitenStarten(r: OrgRessource) {
  form.value = { id: r.id, titel: r.titel, url: r.url ?? '', notiz: r.notiz ?? '', benutzername: '', passwort: '' }
  bearbeitenOffen.value = true
}

async function speichernHandler() {
  fehler.value = ''
  speichern.value = true
  const { error } = await supabase.rpc('org_ressource_speichern', {
    p_organisation_id: props.organisationId,
    p_id: form.value.id || null,
    p_typ: 'link',
    p_titel: form.value.titel,
    p_url: form.value.url,
    p_notiz: form.value.notiz || null,
    p_sichtbarkeit: 'alle',
    p_sortierung: links.value.length,
  })
  speichern.value = false
  if (error) { fehler.value = error.message; return }
  bearbeitenOffen.value = false
  await laderRessourcen()
}

async function loeschenHandler(id: string) {
  if (!window.confirm('Tool wirklich entfernen?')) return
  await supabase.rpc('org_ressource_loeschen', { p_organisation_id: props.organisationId, p_id: id })
  await laderRessourcen()
}
</script>

<template>
  <section class="externe-tools">
    <h3>Externe Tools</h3>
    <p class="hint">Nützliche externe Seiten für den Verein – eCamp, Lagerkochbuch, Vereinsdatenbank etc.</p>

    <p v-if="laden" class="hint">Lade…</p>
    <div v-else-if="links.length" class="tools-liste">
      <article v-for="r in links" :key="r.id" class="tool-karte">
        <div class="tool-kopf">
          <a :href="r.url ?? '#'" target="_blank" rel="noopener noreferrer">{{ r.titel }} ↗</a>
          <button v-if="istLeitung" type="button" class="klein-btn" @click="bearbeitenStarten(r)">✏️</button>
          <button v-if="istLeitung" type="button" class="klein-btn" @click="loeschenHandler(r.id)">✕</button>
        </div>
        <p v-if="r.notiz" class="tool-notiz">{{ r.notiz }}</p>
        <div v-if="loginFuer(r.titel)" class="tool-login">
          <span>Login: {{ loginFuer(r.titel)!.benutzername }}</span>
          <span v-if="loginFuer(r.titel)!.passwort">
            <code>{{ sichtbarePasswoerter[loginFuer(r.titel)!.id] ? loginFuer(r.titel)!.passwort : '••••••••' }}</code>
            <button type="button" class="klein-btn" @click="togglePasswort(loginFuer(r.titel)!.id)">
              {{ sichtbarePasswoerter[loginFuer(r.titel)!.id] ? 'Verbergen' : 'Anzeigen' }}
            </button>
          </span>
        </div>
      </article>
    </div>
    <p v-else class="hint">Noch keine externen Tools hinterlegt.</p>

    <button v-if="istLeitung && !bearbeitenOffen" type="button" class="secondary klein-btn" @click="neuStarten">+ Tool hinzufügen</button>

    <form v-if="bearbeitenOffen" class="tool-form" @submit.prevent="speichernHandler">
      <label>Titel <input v-model="form.titel" required placeholder="z.B. eCamp" /></label>
      <label>Link <input v-model="form.url" type="url" required placeholder="https://..." /></label>
      <label>Kontext / Notiz <input v-model="form.notiz" placeholder="Wofür ist das?" /></label>
      <div class="inline-aktionen">
        <button type="submit" :disabled="speichern">{{ speichern ? 'Speichere…' : 'Speichern' }}</button>
        <button type="button" class="secondary" @click="bearbeitenOffen = false">Abbrechen</button>
      </div>
      <p v-if="fehler" class="error">{{ fehler }}</p>
      <p class="hint klein">
        Logindaten (Benutzername/Passwort) pro Tool bitte im Verein unter Ressourcen &gt; Logindaten anlegen –
        Titel muss dann exakt mit dem Tool-Namen hier übereinstimmen, damit er zugeordnet wird.
      </p>
    </form>
  </section>
</template>

<style scoped>
.externe-tools { margin-top: 1.5rem; }
.externe-tools h3 { margin: 0 0 0.25rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.hint.klein { font-size: 0.78rem; }
.tools-liste { display: grid; gap: 0.6rem; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); margin: 0.75rem 0; }
.tool-karte { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.75rem 0.85rem; background: var(--color-surface); }
.tool-kopf { display: flex; align-items: center; gap: 0.4rem; }
.tool-kopf a { font-weight: 600; }
.tool-notiz { font-size: 0.85rem; color: var(--color-text-muted); margin: 0.35rem 0 0; }
.tool-login { margin-top: 0.5rem; font-size: 0.82rem; display: flex; flex-direction: column; gap: 0.2rem; }
.klein-btn { font-size: 0.75rem; padding: 0.15rem 0.4rem; background: none; border: none; cursor: pointer; color: var(--color-text-muted); }
.tool-form { display: flex; flex-direction: column; gap: 0.55rem; margin-top: 0.75rem; padding: 0.85rem; background: var(--color-surface-muted); border-radius: var(--radius-md); max-width: 420px; }
.tool-form label { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.85rem; color: var(--color-text-muted); }
.inline-aktionen { display: flex; gap: 0.5rem; }
.error { color: var(--color-danger); font-size: 0.85rem; }
</style>
