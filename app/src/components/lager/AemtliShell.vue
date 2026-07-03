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

const beschreibung = ref('')
const hinweise = ref('')
const naechstesTodo = ref<{ titel: string; faellig_am: string | null } | null>(null)

async function ladeOrgId() {
  const { data } = await supabase
    .from('lager')
    .select('organisation_id')
    .eq('id', props.lagerId)
    .single()
  return data?.organisation_id ?? null
}

async function laden() {
  const orgId = await ladeOrgId()
  const { data: todos } = await supabase.from('lager_todos').select('titel, faellig_am, erledigt')
      .eq('lager_id', props.lagerId).eq('aemtli_name', props.aemtliName).eq('erledigt', false)
      .order('faellig_am', { ascending: true, nullsFirst: false }).limit(1)
  
  const meta = orgId
    ? (await supabase
      .from('org_aemtli_meta')
      .select('beschreibung, hinweise_md')
      .eq('organisation_id', orgId)
      .eq('aemtli_id', props.aemtliId)
      .maybeSingle()).data
    : null
  if (meta) {
    beschreibung.value = meta.beschreibung ?? ''
    hinweise.value = meta.hinweise_md ?? ''
  }
  naechstesTodo.value = todos?.[0] ?? null
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
        <p v-if="beschreibung" class="beschreibung">{{ beschreibung }}</p>
      </div>
      <div v-if="naechstesTodo" class="naechstes-todo" :class="todoStatus">
        <span class="label">Als Nächstes</span>
        <strong>{{ naechstesTodo.titel }}</strong>
        <span v-if="naechstesTodo.faellig_am" class="datum">{{ formatFaelligkeit(naechstesTodo.faellig_am) }}</span>
      </div>
    </header>
    <div v-if="hinweise" class="hinweis-box" v-html="hinweisHtml(hinweise)" />
    <slot />
    <AemtliTodos :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName" />
  </section>
</template>

<style scoped>
.shell-kopf { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 0.75rem; margin-bottom: 0.75rem; }
.shell-kopf h2 { margin: 0 0 0.25rem; }
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
</style>
