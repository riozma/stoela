<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'

interface Leiter {
  id: string
  vorname: string
  nachname: string
  anwesend_von: string | null
  anwesend_bis: string | null
  status: string
}

const props = defineProps<{
  lagerId: string
  startDatum: string | null
  endDatum: string | null
}>()

const leiter = ref<Leiter[]>([])

function tageZwischen(von: string, bis: string) {
  const out: string[] = []
  const d = new Date(von + 'T00:00:00')
  const end = new Date(bis + 'T00:00:00')
  while (d <= end) {
    out.push(d.toISOString().slice(0, 10))
    d.setDate(d.getDate() + 1)
  }
  return out
}

const tage = computed(() => {
  if (!props.startDatum || !props.endDatum) return []
  return tageZwischen(props.startDatum, props.endDatum)
})

function istAnwesend(l: Leiter, tag: string) {
  if (l.status !== 'bestaetigt' && l.status !== 'angemeldet') return false
  const von = l.anwesend_von ?? props.startDatum
  const bis = l.anwesend_bis ?? props.endDatum
  if (!von || !bis) return true
  return tag >= von && tag <= bis
}

const matrix = computed(() =>
  leiter.value
    .filter((l) => l.status === 'bestaetigt' || l.status === 'angemeldet')
    .map((l) => ({
      leiter: l,
      tage: tage.value.map((tag) => istAnwesend(l, tag)),
      anzahl: tage.value.filter((tag) => istAnwesend(l, tag)).length,
    })),
)

const tagLabels = computed(() =>
  tage.value.map((tag) =>
    new Intl.DateTimeFormat('de-CH', { weekday: 'short', day: 'numeric', month: 'numeric' }).format(
      new Date(tag + 'T00:00:00'),
    ),
  ),
)

async function laden() {
  const { data } = await supabase
    .from('anmeldungen_leiter')
    .select('id, vorname, nachname, anwesend_von, anwesend_bis, status')
    .eq('lager_id', props.lagerId)
    .in('status', ['bestaetigt', 'angemeldet'])
    .order('nachname')
  leiter.value = data ?? []
}

onMounted(laden)
</script>

<template>
  <section class="zeitstrahl">
    <header>
      <h3>Leiter-Anwesenheit</h3>
      <p class="hint">Grafischer Überblick: Wer ist an welchem Lager-Tag vor Ort?</p>
    </header>

    <p v-if="!tage.length" class="hint">Lager-Start und -Ende müssen gesetzt sein.</p>

    <div v-else class="matrix-wrap">
      <table class="matrix">
        <thead>
          <tr>
            <th>Leiter/in</th>
            <th v-for="(label, i) in tagLabels" :key="tage[i]" class="tag-th">{{ label }}</th>
            <th>Tage</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="m in matrix" :key="m.leiter.id">
            <td class="name">{{ m.leiter.vorname }} {{ m.leiter.nachname }}</td>
            <td v-for="(anw, i) in m.tage" :key="i" class="zelle" :class="{ da: anw }">
              <span v-if="anw" title="Anwesend">●</span>
            </td>
            <td class="summe">{{ m.anzahl }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </section>
</template>

<style scoped>
.zeitstrahl { margin: 1rem 0; }
.zeitstrahl h3 { margin: 0 0 0.25rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin: 0 0 0.75rem; }
.matrix-wrap { overflow-x: auto; }
.matrix { border-collapse: collapse; font-size: 0.82rem; min-width: 100%; }
.matrix th, .matrix td { border: 1px solid var(--color-border); padding: 0.35rem 0.45rem; text-align: center; }
.matrix .name { text-align: left; white-space: nowrap; font-weight: 600; }
.tag-th { writing-mode: vertical-rl; transform: rotate(180deg); font-size: 0.72rem; min-width: 2rem; }
.zelle.da { background: rgba(46, 125, 50, 0.15); color: #2e7d32; }
.summe { font-weight: 600; }
</style>
