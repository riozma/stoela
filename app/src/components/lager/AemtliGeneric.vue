<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'
import AemtliOrgRessourcen from './AemtliOrgRessourcen.vue'
import { filterSocialMediaLogins } from '../../lib/aemtliOrgInfos'

const props = defineProps<{
  lagerId: string
  aemtliId: string
  aemtliName: string
}>()

const organisationId = ref<string | null>(null)
const feldKeys = ref<string[]>([])
const feldWerte = ref<Record<string, string>>({})

const FELD_LABELS: Record<string, string> = {
  social_media: 'Social-Media-Notizen',
  content_plan: 'Content- / Werbeplan',
  flyer_link: 'Flyer (Link)',
  learnings: 'Learnings vom letzten Lager',
}

const istSocialMedia = computed(() =>
  ['social', 'werbung', 'publicity'].some((wort) =>
    props.aemtliName.toLowerCase().includes(wort),
  ),
)

const sichtbareFelder = computed(() => {
  const keys = new Set([...feldKeys.value, 'learnings'])
  if (istSocialMedia.value) keys.delete('social_media')
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
  organisationId.value = orgId
  if (!orgId) return
  const { data: meta } = await supabase
    .from('org_aemtli_meta')
    .select('extra_felder')
    .eq('organisation_id', orgId)
    .eq('aemtli_id', props.aemtliId)
    .maybeSingle()
  if (!meta) return
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
  const orgId = organisationId.value
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
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <AemtliOrgRessourcen
      v-if="istSocialMedia"
      :organisation-id="organisationId"
      titel="Social-Media Logins (aus Verein → Links & Zugänge)"
      :filter="filterSocialMediaLogins"
      leer-hinweis="Keine Social-Media-Zugänge mit Instagram, TikTok etc. unter Verein → Links & Zugänge gefunden."
    />

    <form class="extra-form" @submit.prevent="speichernExtra">
      <h3>Notizen &amp; Planung</h3>
      <label v-for="key in sichtbareFelder" :key="key">
        {{ FELD_LABELS[key] ?? key }}
        <textarea v-model="feldWerte[key]" rows="key === 'learnings' ? 4 : 3" />
      </label>
      <button type="submit">Speichern</button>
    </form>
  </AemtliShell>
</template>

<style scoped>
.extra-form { margin-top: 0.5rem; display: flex; flex-direction: column; gap: 0.65rem; }
.extra-form h3 { margin: 0; font-size: 0.95rem; }
.extra-form label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.82rem; color: var(--color-text-muted); }
</style>
