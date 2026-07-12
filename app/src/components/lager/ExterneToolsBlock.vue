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
}

const props = defineProps<{
  organisationId: string
}>()

const TOOL_NAMEN = ['eCamp', 'Lagerkochbuch', 'J&S-Lageranmeldung', 'Jubla Atlassian', 'jubla.db', 'Externe Cloud']

const ressourcen = ref<OrgRessource[]>([])
const laden = ref(true)
const sichtbarePasswoerter = ref<Record<string, boolean>>({})

async function laderRessourcen() {
  laden.value = true
  const { data } = await supabase.rpc('list_org_ressourcen', { p_organisation_id: props.organisationId })
  ressourcen.value = (data ?? []) as OrgRessource[]
  laden.value = false
}

onMounted(laderRessourcen)

function findeRessource(name: string, typ: 'link' | 'zugang'): OrgRessource | null {
  const exakt = ressourcen.value.find((r) => r.typ === typ && r.titel.toLowerCase() === name.toLowerCase())
  if (exakt) return exakt
  // "Externe Cloud" matcht auch jahresspezifische Titel wie "Cloud 2026".
  if (name === 'Externe Cloud') {
    return ressourcen.value.find((r) => r.typ === typ && r.titel.toLowerCase().includes('cloud')) ?? null
  }
  return null
}

const tools = computed(() =>
  TOOL_NAMEN.map((name) => {
    const link = findeRessource(name, 'link')
    return {
      name: link && name === 'Externe Cloud' ? link.titel : name,
      link,
      login: findeRessource(name, 'zugang'),
    }
  }),
)

function togglePasswort(id: string) {
  sichtbarePasswoerter.value[id] = !sichtbarePasswoerter.value[id]
}
</script>

<template>
  <section class="externe-tools">
    <h3>Externe Tools</h3>
    <p class="hint">
      Nützliche externe Seiten für den Verein. Links und Logindaten werden zentral im
      <router-link :to="`/organisation?org=${organisationId}`">Verein unter Ressourcen</router-link>
      gepflegt (Admin/Lalei).
    </p>

    <p v-if="laden" class="hint">Lade…</p>
    <div v-else class="tools-liste">
      <article v-for="t in tools" :key="t.name" class="tool-karte">
        <div class="tool-kopf">
          <a v-if="t.link?.url" :href="t.link.url" target="_blank" rel="noopener noreferrer">{{ t.name }} ↗</a>
          <span v-else>{{ t.name }}</span>
        </div>
        <p v-if="t.link?.notiz" class="tool-notiz">{{ t.link.notiz }}</p>
        <p v-if="!t.link" class="hint klein">Noch kein Link im Verein hinterlegt.</p>
        <div v-if="t.login" class="tool-login">
          <span>Login: {{ t.login.benutzername }}</span>
          <span v-if="t.login.passwort">
            <code>{{ sichtbarePasswoerter[t.login.id] ? t.login.passwort : '••••••••' }}</code>
            <button type="button" class="klein-btn" @click="togglePasswort(t.login.id)">
              {{ sichtbarePasswoerter[t.login.id] ? 'Verbergen' : 'Anzeigen' }}
            </button>
          </span>
        </div>
      </article>
    </div>
  </section>
</template>

<style scoped>
.externe-tools { margin-top: 1.5rem; }
.externe-tools h3 { margin: 0 0 0.25rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.hint.klein { font-size: 0.78rem; }
.tools-liste { display: grid; gap: 0.6rem; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); margin: 0.75rem 0; }
.tool-karte { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.75rem 0.85rem; background: var(--color-surface); }
.tool-kopf a { font-weight: 600; }
.tool-notiz { font-size: 0.85rem; color: var(--color-text-muted); margin: 0.35rem 0 0; }
.tool-login { margin-top: 0.5rem; font-size: 0.82rem; display: flex; flex-direction: column; gap: 0.2rem; }
.klein-btn { font-size: 0.75rem; padding: 0.15rem 0.4rem; background: none; border: none; cursor: pointer; color: var(--color-text-muted); }
</style>
