<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliTodos from './AemtliTodos.vue'

const props = defineProps<{
  lagerId: string
  aemtliId: string
  aemtliName: string
}>()

const beschreibung = ref('')
const hinweise = ref('')
const seitenTyp = ref('generic')
const feldKeys = ref<string[]>([])
const feldWerte = ref<Record<string, string>>({})

const FELD_LABELS: Record<string, string> = {
  social_media: 'Social-Media-Logins / Zugänge',
  content_plan: 'Content- / Werbeplan',
  flyer_link: 'Flyer (Link)',
  learnings: 'Learnings vom letzten Lager',
}

const sichtbareFelder = computed(() => {
  const keys = new Set([...feldKeys.value, 'learnings'])
  return [...keys]
})

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
  if (!orgId) return
  const { data: meta } = await supabase
    .from('org_aemtli_meta')
    .select('seiten_typ, beschreibung, hinweise_md, extra_felder')
    .eq('organisation_id', orgId)
    .eq('aemtli_id', props.aemtliId)
    .maybeSingle()
  if (!meta) return
  seitenTyp.value = meta.seiten_typ ?? 'generic'
  beschreibung.value = meta.beschreibung ?? ''
  hinweise.value = meta.hinweise_md ?? ''
  const raw = (meta.extra_felder as Record<string, unknown>) ?? {}
  feldKeys.value = Array.isArray(raw.felder) ? (raw.felder as string[]) : []
  const werte: Record<string, string> = {}
  for (const key of [...feldKeys.value, 'learnings']) {
    werte[key] = typeof raw[key] === 'string' ? raw[key] : ''
  }
  feldWerte.value = werte
}

onMounted(laden)

async function speichernExtra() {
  const orgId = await ladeOrgId()
  if (!orgId) return
  const payload: Record<string, unknown> = { felder: feldKeys.value }
  for (const key of sichtbareFelder.value) {
    payload[key] = feldWerte.value[key] ?? ''
  }
  await supabase
    .from('org_aemtli_meta')
    .update({ extra_felder: payload })
    .eq('organisation_id', orgId)
    .eq('aemtli_id', props.aemtliId)
}

function hinweisHtml(md: string) {
  return md
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\n/g, '<br>')
}
</script>

<template>
  <section class="aemtli-bereich">
    <h2>{{ aemtliName }}</h2>
    <p v-if="beschreibung" class="beschreibung">{{ beschreibung }}</p>
    <div v-if="hinweise" class="hinweis-box" v-html="hinweisHtml(hinweise)" />

    <AemtliTodos :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName" />

    <form class="extra-form" @submit.prevent="speichernExtra">
      <h3>Notizen &amp; Tools</h3>
      <label v-for="key in sichtbareFelder" :key="key">
        {{ FELD_LABELS[key] ?? key }}
        <textarea v-model="feldWerte[key]" rows="key === 'learnings' ? 4 : 3" />
      </label>
      <button type="submit">Speichern</button>
    </form>
  </section>
</template>

<style scoped>
.aemtli-bereich h2 { margin: 0 0 0.5rem; }
.beschreibung { color: var(--color-text-muted); font-size: 0.92rem; margin: 0 0 0.75rem; }
.hinweis-box {
  background: var(--color-surface-muted);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 0.75rem 1rem;
  font-size: 0.88rem;
  line-height: 1.45;
  margin-bottom: 1rem;
}
.extra-form { margin-top: 1.25rem; display: flex; flex-direction: column; gap: 0.65rem; }
.extra-form h3 { margin: 0; font-size: 0.95rem; }
.extra-form label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.82rem; color: var(--color-text-muted); }
</style>
