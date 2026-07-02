<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'

const props = defineProps<{ lagerId: string }>()

interface AemtliStatus {
  name: string
  status: string
}

interface ProgrammEintrag {
  leiter_id: string
  name: string
  bloecke_absolut: number
  bloecke_total: number
  anteil_prozent: number
  anwesend_tage: number | null
}

const laden = ref(true)
const aemtliStatus = ref<AemtliStatus[]>([])
const programmStatistik = ref<ProgrammEintrag[]>([])
const tnStatusZaehler = ref<Record<string, number>>({})
const tnBezahltCount = ref(0)
const tnGesamt = ref(0)

const STATUS_LABEL: Record<string, string> = { offen: 'Offen', in_arbeit: 'In Arbeit', erledigt: 'Erledigt' }

const aemtliZaehler = computed(() => {
  const z: Record<string, number> = { offen: 0, in_arbeit: 0, erledigt: 0 }
  for (const a of aemtliStatus.value) z[a.status] = (z[a.status] ?? 0) + 1
  return z
})

async function ladenAlle() {
  laden.value = true
  const [{ data: aemtli }, { data: prog }, { data: tn }] = await Promise.all([
    supabase
      .from('aemtli_zuweisungen')
      .select('status, aemtli:aemtli_id(name)')
      .eq('lager_id', props.lagerId),
    supabase.rpc('lager_programm_statistik', { p_lager_id: props.lagerId }),
    supabase.from('anmeldungen_tn').select('status, tn_finanzen(bezahlt)').eq('lager_id', props.lagerId),
  ])

  aemtliStatus.value = (aemtli ?? []).map((a: any) => ({
    name: a.aemtli?.name ?? '–',
    status: a.status ?? 'offen',
  }))
  programmStatistik.value = (prog as ProgrammEintrag[]) ?? []

  const zaehler: Record<string, number> = {}
  let bezahlt = 0
  for (const t of tn ?? []) {
    zaehler[t.status] = (zaehler[t.status] ?? 0) + 1
    const fin = Array.isArray(t.tn_finanzen) ? t.tn_finanzen[0] : t.tn_finanzen
    if (fin?.bezahlt) bezahlt += 1
  }
  tnStatusZaehler.value = zaehler
  tnBezahltCount.value = bezahlt
  tnGesamt.value = (tn ?? []).length

  laden.value = false
}

onMounted(ladenAlle)
</script>

<template>
  <section class="statistik">
    <h2>Statistik (Lalei)</h2>
    <p v-if="laden" class="hint">Lade Statistik...</p>

    <template v-else>
      <div class="karten">
        <div class="karte">
          <span class="label">Ämtli-Status</span>
          <div class="balken">
            <span class="segment erledigt" :style="{ flex: aemtliZaehler.erledigt || 0.001 }" />
            <span class="segment in_arbeit" :style="{ flex: aemtliZaehler.in_arbeit || 0.001 }" />
            <span class="segment offen" :style="{ flex: aemtliZaehler.offen || 0.001 }" />
          </div>
          <p class="zeilen">
            {{ aemtliZaehler.erledigt }} erledigt · {{ aemtliZaehler.in_arbeit }} in Arbeit · {{ aemtliZaehler.offen }} offen
          </p>
        </div>

        <div class="karte">
          <span class="label">Anmeldestand TN</span>
          <strong class="gross">{{ tnGesamt }}</strong>
          <p class="zeilen">
            <span v-for="(anzahl, status) in tnStatusZaehler" :key="status">{{ anzahl }} {{ status }} · </span>
          </p>
        </div>

        <div class="karte">
          <span class="label">Zahlungsstand (Budget-Proxy)</span>
          <strong class="gross">{{ tnBezahltCount }} / {{ tnGesamt }}</strong>
          <p class="zeilen">TN-Beiträge als bezahlt markiert</p>
        </div>
      </div>

      <h3>Ämtli im Detail</h3>
      <table class="liste">
        <thead><tr><th>Ämtli</th><th>Status</th></tr></thead>
        <tbody>
          <tr v-for="a in aemtliStatus" :key="a.name">
            <td>{{ a.name }}</td>
            <td><span class="status-badge" :class="a.status">{{ STATUS_LABEL[a.status] ?? a.status }}</span></td>
          </tr>
        </tbody>
      </table>

      <h3>Programm-Beteiligung</h3>
      <table v-if="programmStatistik.length" class="liste">
        <thead><tr><th>Leiter</th><th>Blöcke</th><th>Anteil</th><th>Anwesend (Tage)</th></tr></thead>
        <tbody>
          <tr v-for="p in programmStatistik" :key="p.leiter_id">
            <td>{{ p.name }}</td>
            <td>{{ p.bloecke_absolut }} / {{ p.bloecke_total }}</td>
            <td>{{ p.anteil_prozent }}%</td>
            <td>{{ p.anwesend_tage ?? '–' }}</td>
          </tr>
        </tbody>
      </table>
      <p v-else class="hint">Noch keine Programmblöcke mit Zuordnung erfasst.</p>
    </template>
  </section>
</template>

<style scoped>
.statistik h2 { margin: 0 0 0.75rem; }
.karten { display: flex; flex-wrap: wrap; gap: 0.75rem; margin-bottom: 1.5rem; }
.karte {
  flex: 1; min-width: 14rem; background: var(--color-surface); border: 1px solid var(--color-border);
  border-radius: var(--radius-md); padding: 0.85rem 1rem;
}
.karte .label { display: block; font-size: 0.72rem; text-transform: uppercase; color: var(--color-text-muted); margin-bottom: 0.35rem; }
.karte .gross { font-size: 1.6rem; }
.karte .zeilen { font-size: 0.8rem; color: var(--color-text-muted); margin: 0.35rem 0 0; }
.balken { display: flex; height: 0.6rem; border-radius: var(--radius-pill); overflow: hidden; background: var(--color-surface-muted); }
.balken .segment.erledigt { background: #4a8a5c; }
.balken .segment.in_arbeit { background: #c98a3f; }
.balken .segment.offen { background: var(--color-border); }
h3 { margin: 1.25rem 0 0.5rem; font-size: 0.95rem; }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); text-align: left; }
.liste th { font-size: 0.75rem; color: var(--color-text-muted); text-transform: uppercase; }
.status-badge { padding: 0.1rem 0.5rem; border-radius: var(--radius-pill); font-size: 0.78rem; }
.status-badge.erledigt { background: #eaf3ec; color: #2f6b40; }
.status-badge.in_arbeit { background: #faf0e2; color: #8a5a1f; }
.status-badge.offen { background: var(--color-surface-muted); color: var(--color-text-muted); }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
