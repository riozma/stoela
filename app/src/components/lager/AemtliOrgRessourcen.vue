<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'
import { supabase } from '../../supabaseClient'
import { SICHTBARKEIT_LABELS, type OrgRessource } from '../../lib/orgRessourcen'

const props = defineProps<{
  organisationId: string | null
  titel?: string
  filter?: (r: OrgRessource) => boolean
  leerHinweis?: string
}>()

const eintraege = ref<OrgRessource[]>([])
const sichtbarePasswoerter = ref<Record<string, boolean>>({})

async function laden() {
  if (!props.organisationId) {
    eintraege.value = []
    return
  }
  const { data } = await supabase.rpc('list_org_ressourcen', { p_organisation_id: props.organisationId })
  const alle = (data ?? []) as OrgRessource[]
  eintraege.value = props.filter ? alle.filter(props.filter) : alle
}

onMounted(laden)
watch(() => props.organisationId, laden)

function togglePw(id: string) {
  sichtbarePasswoerter.value[id] = !sichtbarePasswoerter.value[id]
}
</script>

<template>
  <section v-if="organisationId" class="org-infos">
    <h3>{{ titel ?? 'Vereins-Zugänge' }}</h3>
    <div v-if="eintraege.length" class="org-liste">
      <article v-for="r in eintraege" :key="r.id" class="org-karte">
        <div class="kopf">
          <strong>{{ r.titel }}</strong>
          <span class="klein">{{ SICHTBARKEIT_LABELS[r.sichtbarkeit] }}</span>
        </div>
        <p v-if="r.typ === 'link' && r.url">
          <a :href="r.url" target="_blank" rel="noopener noreferrer">{{ r.url }}</a>
        </p>
        <template v-else-if="r.typ === 'zugang'">
          <p v-if="r.url" class="zeile">
            <span>Seite:</span>
            <a :href="r.url" target="_blank" rel="noopener noreferrer">{{ r.url }}</a>
          </p>
          <p v-if="r.benutzername" class="zeile"><span>Login:</span> {{ r.benutzername }}</p>
          <p v-if="r.passwort" class="zeile">
            <span>Passwort:</span>
            <code>{{ sichtbarePasswoerter[r.id] ? r.passwort : '••••••••' }}</code>
            <button type="button" class="klein-btn" @click="togglePw(r.id)">
              {{ sichtbarePasswoerter[r.id] ? 'Verbergen' : 'Anzeigen' }}
            </button>
          </p>
        </template>
        <p v-if="r.notiz" class="notiz">{{ r.notiz }}</p>
      </article>
    </div>
    <p v-else class="hint">{{ leerHinweis ?? 'Keine passenden Einträge unter Verein → Links & Zugänge.' }}</p>
  </section>
</template>

<style scoped>
.org-infos { margin: 0 0 1rem; }
.org-infos h3 { margin: 0 0 0.5rem; font-size: 0.95rem; }
.org-liste { display: grid; gap: 0.5rem; }
.org-karte { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.6rem 0.75rem; font-size: 0.88rem; }
.kopf { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: center; margin-bottom: 0.25rem; }
.klein { font-size: 0.75rem; color: var(--color-text-muted); }
.zeile { margin: 0.15rem 0; }
.zeile span { color: var(--color-text-muted); margin-right: 0.35rem; }
.notiz { margin: 0.25rem 0 0; color: var(--color-text-muted); font-size: 0.82rem; }
.hint { color: var(--color-text-muted); font-size: 0.85rem; }
.klein-btn { font-size: 0.75rem; padding: 0.15rem 0.4rem; margin-left: 0.35rem; }
</style>
