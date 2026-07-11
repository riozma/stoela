<script setup lang="ts">
import { computed, nextTick, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'
import LagerMap from './LagerMap.vue'
import WiesenKarte from './WiesenKarte.vue'
import { useGooglePlaces, type OrtAuswahl } from '../../composables/useGooglePlaces'

const props = defineProps<{
  lagerId: string
  aemtliId: string
  aemtliName: string
  lat?: number | null
  lng?: number | null
}>()

interface Wiese {
  id: string
  name: string
  lat: number | null
  lng: number | null
  bauer_name: string | null
  bauer_telefon: string | null
  status: string
  notiz: string | null
  created_at: string
}

const wiesen = ref<Wiese[]>([])
const form = ref({ name: '', bauer_name: '', bauer_telefon: '', notiz: '' })
const neueOrtAuswahl = ref<OrtAuswahl | null>(null)
const neuerOrtInput = ref<HTMLInputElement | null>(null)
const ortBearbeitenId = ref<string | null>(null)
const { attachAutocomplete } = useGooglePlaces()

const STATUS_LABELS: Record<string, string> = {
  offen: 'Noch anfragen',
  zusage: '✓ Zusage',
  abgelehnt: '✗ Abgelehnt',
  bedankt: '🍷 Bedankt',
}

const wiesenMitNr = computed(() =>
  wiesen.value.map((w, i) => ({ ...w, nr: i + 1 })),
)

const hatBedankungsAusstehend = computed(() =>
  wiesen.value.some((w) => w.status === 'zusage'),
)

async function laden() {
  const { data } = await supabase
    .from('gelaendespielwiesen')
    .select('*')
    .eq('lager_id', props.lagerId)
    .order('created_at')
  wiesen.value = data ?? []
}

onMounted(async () => {
  await laden()
  await nextTick()
  ortNeuAttach()
})

async function hinzufuegen() {
  await supabase.from('gelaendespielwiesen').insert({
    lager_id: props.lagerId,
    name: form.value.name,
    bauer_name: form.value.bauer_name || null,
    bauer_telefon: form.value.bauer_telefon || null,
    notiz: form.value.notiz || null,
    status: 'offen',
    lat: neueOrtAuswahl.value?.lat ?? null,
    lng: neueOrtAuswahl.value?.lng ?? null,
  })
  form.value = { name: '', bauer_name: '', bauer_telefon: '', notiz: '' }
  neueOrtAuswahl.value = null
  if (neuerOrtInput.value) neuerOrtInput.value.value = ''
  await laden()
}

async function ortBearbeitenStarten(id: string) {
  ortBearbeitenId.value = id
  await nextTick()
  const input = document.getElementById(`ort-input-${id}`) as HTMLInputElement | null
  if (input) {
    await attachAutocomplete(input, async (ort) => {
      await supabase.from('gelaendespielwiesen').update({ lat: ort.lat, lng: ort.lng }).eq('id', id)
      const w = wiesen.value.find((x) => x.id === id)
      if (w) { w.lat = ort.lat; w.lng = ort.lng }
      ortBearbeitenId.value = null
    })
  }
}

function ortNeuAttach() {
  if (neuerOrtInput.value) {
    attachAutocomplete(neuerOrtInput.value, (ort) => {
      neueOrtAuswahl.value = ort
    })
  }
}

async function statusSetzen(id: string, status: string) {
  await supabase.from('gelaendespielwiesen').update({ status }).eq('id', id)
  await laden()
}

async function loeschen(id: string) {
  if (!confirm('Wiese wirklich löschen?')) return
  await supabase.from('gelaendespielwiesen').delete().eq('id', id)
  await laden()
}

async function notizSpeichern(id: string, notiz: string) {
  await supabase.from('gelaendespielwiesen').update({ notiz: notiz || null }).eq('id', id)
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <LagerMap v-if="lat && lng" :lat="lat" :lng="lng" ort="Lager / Umgebung" />

    <p v-if="hatBedankungsAusstehend" class="dankeschoen-hinweis">
      🍷 Du hast Wiesen mit Zusage – nach dem Lager Dankeschön (Flasche Wein) persönlich vorbeibringen und Status auf «Bedankt» setzen!
    </p>

    <WiesenKarte v-if="wiesenMitNr.length" :wiesen="wiesenMitNr" />

    <h3>Neue Wiese erfassen</h3>
    <form class="inline-form" @submit.prevent="hinzufuegen">
      <input v-model="form.name" placeholder="Name / Ort der Wiese" required style="flex:2" />
      <input ref="neuerOrtInput" placeholder="📍 Ort auf Karte suchen..." style="flex:2" />
      <input v-model="form.bauer_name" placeholder="Bauer/in" />
      <input v-model="form.bauer_telefon" placeholder="Telefon" />
      <input v-model="form.notiz" placeholder="Notiz" style="flex:1" />
      <button type="submit">+ Wiese</button>
    </form>
    <p v-if="neueOrtAuswahl" class="hint">📍 {{ neueOrtAuswahl.adresse }}</p>

    <table v-if="wiesenMitNr.length" class="liste">
      <thead>
        <tr>
          <th>Nr.</th>
          <th>Wiese</th>
          <th>Bauer/in</th>
          <th>Kontakt</th>
          <th>Pin</th>
          <th>Notiz</th>
          <th>Status</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="w in wiesenMitNr" :key="w.id" :class="'status-' + w.status">
          <td class="nr">Wiese {{ w.nr }}</td>
          <td><strong>{{ w.name }}</strong></td>
          <td>{{ w.bauer_name ?? '–' }}</td>
          <td>
            <a v-if="w.bauer_telefon" :href="`tel:${w.bauer_telefon}`" class="tel-link">{{ w.bauer_telefon }}</a>
            <span v-else>–</span>
          </td>
          <td>
            <input
              v-if="ortBearbeitenId === w.id"
              :id="`ort-input-${w.id}`"
              placeholder="Ort suchen..."
              class="ort-input"
            />
            <button v-else class="secondary klein" @click="ortBearbeitenStarten(w.id)">
              {{ w.lat && w.lng ? '📍 ändern' : '📍 setzen' }}
            </button>
          </td>
          <td>
            <input
              class="notiz-input"
              :value="w.notiz ?? ''"
              placeholder="–"
              @blur="notizSpeichern(w.id, ($event.target as HTMLInputElement).value)"
            />
          </td>
          <td>
            <span class="status-pill" :class="'s-' + w.status">{{ STATUS_LABELS[w.status] }}</span>
          </td>
          <td class="aktionen-zelle">
            <button v-if="w.status === 'offen'" class="secondary klein" @click="statusSetzen(w.id, 'zusage')">Zusage</button>
            <button v-if="w.status === 'offen'" class="secondary klein" @click="statusSetzen(w.id, 'abgelehnt')">Abgelehnt</button>
            <button v-if="w.status === 'zusage'" class="secondary klein" @click="statusSetzen(w.id, 'bedankt')">Bedankt ✓</button>
            <button class="secondary klein loeschen-btn" @click="loeschen(w.id)" title="Löschen">✕</button>
          </td>
        </tr>
      </tbody>
    </table>
    <p v-else class="hint">Noch keine Wiesen erfasst. Bauern in der Lager-Umgebung persönlich anfragen.</p>
    <p class="hint">Sobald eine Wiese erfasst ist, erscheint für alle Leiter/innen ein «Spielwiesen»-Tab (nur ansehen + kommentieren).</p>

    <p class="hint">Tipp: Nach dem Lager zu jeder Wiese mit Zusage eine Flasche Wein vorbeibringen (Dankeschön).</p>
  </AemtliShell>
</template>

<style scoped>
h3 { margin: 0.75rem 0 0.4rem; font-size: 0.95rem; }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 0.5rem 0 1rem; align-items: end; }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); text-align: left; vertical-align: middle; }
.liste th { font-size: 0.75rem; color: var(--color-text-muted); text-transform: uppercase; }
.nr { font-weight: 700; color: var(--color-text-muted); white-space: nowrap; }
.tel-link { color: var(--color-accent); text-decoration: none; }
.tel-link:hover { text-decoration: underline; }
.notiz-input { width: 100%; min-width: 8rem; border: 1px solid transparent; background: transparent; padding: 0.2rem 0.3rem; font-size: 0.83rem; border-radius: var(--radius-sm); }
.notiz-input:focus { border-color: var(--color-border); background: var(--color-surface); outline: none; }
.ort-input { min-width: 12rem; font-size: 0.82rem; padding: 0.2rem 0.4rem; border: 1px solid var(--color-border); border-radius: var(--radius-sm); }
.aktionen-zelle { display: flex; flex-wrap: wrap; gap: 0.25rem; }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.45rem; }
.loeschen-btn { color: var(--color-danger); }

/* Status-Pills */
.status-pill { font-size: 0.75rem; padding: 0.2rem 0.5rem; border-radius: var(--radius-pill); font-weight: 600; white-space: nowrap; }
.s-offen { background: var(--color-surface-muted); color: var(--color-text-muted); }
.s-zusage { background: #e8f5e9; color: #2e7d32; }
.s-abgelehnt { background: #fdf6f4; color: var(--color-danger); }
.s-bedankt { background: #fdf8f0; color: #c98a3f; }

/* Row tinting */
tr.status-zusage td { background: #f7fdf8; }
tr.status-abgelehnt td { opacity: 0.6; }
tr.status-bedankt td { background: #fdfaf5; }

.dankeschoen-hinweis {
  background: #fdf8f0; border: 1px solid #c98a3f; border-radius: var(--radius-md);
  padding: 0.6rem 0.85rem; font-size: 0.88rem; margin-bottom: 0.75rem;
}
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin-top: 0.5rem; }
</style>
