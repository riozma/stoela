<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

const tnListe = ref<{ id: string; vorname: string; nachname: string; allergien: string | null; medikamente: string | null; gesundheit_bemerkungen: string | null; essensgewohnheiten: string | null }[]>([])

async function laden() {
  const { data } = await supabase.from('anmeldungen_tn')
    .select('id, vorname, nachname, allergien, medikamente, gesundheit_bemerkungen, essensgewohnheiten')
    .eq('lager_id', props.lagerId).order('nachname')
  tnListe.value = data ?? []
}

onMounted(laden)

const mitMedikamenten = () => tnListe.value.filter((t) => t.medikamente?.trim())
const mitAllergien = () => tnListe.value.filter((t) => t.allergien?.trim())
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <div class="stats">
      <span>{{ tnListe.length }} TN</span>
      <span>{{ mitMedikamenten().length }} mit Medikamenten</span>
      <span>{{ mitAllergien().length }} mit Allergien</span>
    </div>
    <table class="liste">
      <thead><tr><th>Name</th><th>Allergien</th><th>Medikamente</th><th>Bemerkungen</th><th>Essen</th></tr></thead>
      <tbody>
        <tr v-for="t in tnListe" :key="t.id" :class="{ warn: t.medikamente || t.allergien }">
          <td>{{ t.vorname }} {{ t.nachname }}</td>
          <td>{{ t.allergien ?? '–' }}</td>
          <td>{{ t.medikamente ?? '–' }}</td>
          <td>{{ t.gesundheit_bemerkungen ?? '–' }}</td>
          <td>{{ t.essensgewohnheiten ?? '–' }}</td>
        </tr>
      </tbody>
    </table>
    <p class="hint">Apotheke/Arzt/Krankenhaus vor Lager informieren. Impfausweise am Elternabend einsammeln.</p>
  </AemtliShell>
</template>

<style scoped>
.stats { display: flex; gap: 1rem; margin-bottom: 0.75rem; font-size: 0.88rem; color: var(--color-text-muted); }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); text-align: left; vertical-align: top; }
tr.warn { background: #fdf8f0; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin-top: 0.75rem; }
</style>
