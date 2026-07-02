<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

const telefonZeiten = ref('')

async function laden() {
  const { data } = await supabase.from('lager').select('telefon_zeiten').eq('id', props.lagerId).single()
  telefonZeiten.value = data?.telefon_zeiten ?? ''
}

onMounted(laden)

async function speichern() {
  await supabase.from('lager').update({ telefon_zeiten: telefonZeiten.value || null }).eq('id', props.lagerId)
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <p class="hint">Telefonzeiten werden in der Elterninfo angezeigt. Parallel zum Kiosk (gerade/ungerade Gruppen).</p>
    <form @submit.prevent="speichern">
      <label>
        Telefonzeiten (für Elterninfo)
        <textarea v-model="telefonZeiten" rows="4" placeholder="z.B. Di+Do 18:00–19:00, Stöla-Handy im Büro" />
      </label>
      <button type="submit">Speichern</button>
    </form>
  </AemtliShell>
</template>

<style scoped>
label { display: flex; flex-direction: column; gap: 0.35rem; font-size: 0.85rem; color: var(--color-text-muted); }
textarea { width: 100%; max-width: 480px; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin-bottom: 0.75rem; }
</style>
