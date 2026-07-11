<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

interface Hl {
  id: string
  vorname: string
  nachname: string
  geburtsdatum: string | null
  status: string
  anwesend_von: string | null
  anwesend_bis: string | null
}

const hlListe = ref<Hl[]>([])
const laden = ref(true)

function berechneAlter(geburtsdatum: string | null): number | null {
  if (!geburtsdatum) return null
  const geburt = new Date(geburtsdatum)
  const heute = new Date()
  let alter = heute.getFullYear() - geburt.getFullYear()
  const monatDiff = heute.getMonth() - geburt.getMonth()
  if (monatDiff < 0 || (monatDiff === 0 && heute.getDate() < geburt.getDate())) alter--
  return alter
}

async function laden_() {
  laden.value = true
  const { data } = await supabase
    .from('anmeldungen_tn')
    .select('id, vorname, nachname, geburtsdatum, status, anwesend_von, anwesend_bis')
    .eq('lager_id', props.lagerId)
    .eq('rolle', 'HL')
    .neq('status', 'abgesagt')
    .order('nachname')
  hlListe.value = data ?? []
  laden.value = false
}

onMounted(laden_)
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <h3>HL ({{ hlListe.length }})</h3>
    <p class="hint">Alle Teilnehmer/innen, die aufgrund ihres Jahrgangs als HL eingeteilt wurden.</p>

    <p v-if="laden" class="hint">Lade...</p>
    <table v-else-if="hlListe.length" class="liste">
      <thead>
        <tr><th>Name</th><th>Alter</th><th>Status</th><th>Anwesend</th></tr>
      </thead>
      <tbody>
        <tr v-for="h in hlListe" :key="h.id">
          <td><strong>{{ h.vorname }} {{ h.nachname }}</strong></td>
          <td>{{ berechneAlter(h.geburtsdatum) ?? '–' }}</td>
          <td>{{ h.status }}</td>
          <td>{{ h.anwesend_von ?? '–' }} – {{ h.anwesend_bis ?? '–' }}</td>
        </tr>
      </tbody>
    </table>
    <p v-else class="hint">Noch keine HL angemeldet.</p>
  </AemtliShell>
</template>

<style scoped>
h3 { margin: 0 0 0.25rem; }
.liste { width: 100%; border-collapse: collapse; font-size: 0.88rem; margin-top: 0.75rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); text-align: left; }
.liste th { font-size: 0.75rem; color: var(--color-text-muted); text-transform: uppercase; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
