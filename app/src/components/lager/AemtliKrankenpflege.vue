<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

interface TnGesundheit {
  id: string
  vorname: string
  nachname: string
  status: string
  allergien: string | null
  medikamente: string | null
  gesundheit_bemerkungen: string | null
  essensgewohnheiten: string | null
  essensgewohnheiten_sonstiges: string | null
  sonstige_info: string | null
}

const tnListe = ref<TnGesundheit[]>([])
const nurMitAngaben = ref(false)

async function laden() {
  const { data } = await supabase
    .from('anmeldungen_tn')
    .select(
      'id, vorname, nachname, status, allergien, medikamente, gesundheit_bemerkungen, essensgewohnheiten, essensgewohnheiten_sonstiges, sonstige_info',
    )
    .eq('lager_id', props.lagerId)
    .order('nachname')
  tnListe.value = (data ?? []) as TnGesundheit[]
}

onMounted(laden)

function hatGesundheitsangaben(t: TnGesundheit) {
  return Boolean(
    t.allergien?.trim()
    || t.medikamente?.trim()
    || t.gesundheit_bemerkungen?.trim()
    || t.essensgewohnheiten?.trim()
    || t.essensgewohnheiten_sonstiges?.trim()
    || t.sonstige_info?.trim(),
  )
}

const angezeigt = computed(() =>
  nurMitAngaben.value ? tnListe.value.filter(hatGesundheitsangaben) : tnListe.value,
)

const mitMedikamenten = computed(() => tnListe.value.filter((t) => t.medikamente?.trim()))
const mitAllergien = computed(() => tnListe.value.filter((t) => t.allergien?.trim()))
const mitBemerkungen = computed(() => tnListe.value.filter((t) => t.gesundheit_bemerkungen?.trim()))
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <div class="stats">
      <span>{{ tnListe.length }} TN angemeldet</span>
      <span>{{ mitMedikamenten.length }} mit Medikamenten</span>
      <span>{{ mitAllergien.length }} mit Allergien</span>
      <span>{{ mitBemerkungen.length }} mit Gesundheitsbemerkungen</span>
    </div>
    <p class="hint hinweis-oben">Apotheke/Arzt vor Lager informieren. Impfausweise am Elternabend einsammeln.</p>
    <label class="filter">
      <input v-model="nurMitAngaben" type="checkbox" />
      Nur TN mit Gesundheitsangaben anzeigen
    </label>
    <table v-if="angezeigt.length" class="liste">
      <thead>
        <tr>
          <th>Name</th>
          <th>Status</th>
          <th>Allergien</th>
          <th>Medikamente</th>
          <th>Gesundheit</th>
          <th>Essen</th>
          <th>Sonstiges</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="t in angezeigt" :key="t.id" :class="{ warn: hatGesundheitsangaben(t) }">
          <td>{{ t.vorname }} {{ t.nachname }}</td>
          <td>{{ t.status }}</td>
          <td>{{ t.allergien?.trim() || '–' }}</td>
          <td>{{ t.medikamente?.trim() || '–' }}</td>
          <td>{{ t.gesundheit_bemerkungen?.trim() || '–' }}</td>
          <td>
            {{ t.essensgewohnheiten?.trim() || '–' }}
            <span v-if="t.essensgewohnheiten_sonstiges?.trim()" class="klein">({{ t.essensgewohnheiten_sonstiges }})</span>
          </td>
          <td>{{ t.sonstige_info?.trim() || '–' }}</td>
        </tr>
      </tbody>
    </table>
    <p v-else class="hint">Noch keine Gesundheitsangaben aus der TN-Anmeldung.</p>
    <p class="hint">Daten stammen aus der TN-Anmeldung.</p>
  </AemtliShell>
</template>

<style scoped>
.stats { display: flex; flex-wrap: wrap; gap: 0.75rem 1rem; margin-bottom: 0.65rem; font-size: 0.88rem; color: var(--color-text-muted); }
.filter { display: flex; align-items: center; gap: 0.4rem; font-size: 0.85rem; margin-bottom: 0.65rem; }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); text-align: left; vertical-align: top; }
tr.warn { background: #fdf8f0; }
.klein { color: var(--color-text-muted); font-size: 0.78rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin-top: 0.75rem; }
.hinweis-oben { background: var(--color-surface-muted); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.5rem 0.75rem; margin-top: 0; }
</style>
