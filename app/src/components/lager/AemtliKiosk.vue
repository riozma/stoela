<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

interface Artikel { id: string; name: string; preis: number; kategorie: string | null }
interface TN { id: string; vorname: string; nachname: string; gruppe_nr: number | null }
interface Guthaben { id: string; anmeldung_tn_id: string; betrag_start: number; betrag_ausgezahlt: number }
interface Kauf { id: string; artikel_name: string; preis: number; menge: number; tag: string; anmeldung_tn_id: string }

const artikel = ref<Artikel[]>([])
const tnListe = ref<TN[]>([])
const guthaben = ref<Guthaben[]>([])
const kaeufe = ref<Kauf[]>([])
const gruppeModus = ref('ungerade')
const artForm = ref({ name: '', preis: 1.5, kategorie: 'Süssigkeit' })
const geldForm = ref({ tnId: '', betrag: 20 })
const kaufForm = ref({ tnId: '', artikelId: '', menge: 1 })

const stats = computed(() => {
  const umsatz = kaeufe.value.reduce((s, k) => s + k.preis * k.menge, 0)
  return { umsatz, anzahl: kaeufe.value.length }
})

async function laden() {
  const [{ data: a }, { data: g }, { data: k }, { data: l }] = await Promise.all([
    supabase.from('kiosk_artikel').select('*').eq('lager_id', props.lagerId).eq('aktiv', true).order('sortierung'),
    supabase.from('kiosk_guthaben').select('*').eq('lager_id', props.lagerId),
    supabase.from('kiosk_kaeufe').select('*').eq('lager_id', props.lagerId).order('created_at', { ascending: false }),
    supabase.from('lager').select('kiosk_gruppe_modus').eq('id', props.lagerId).single(),
  ])
  artikel.value = a ?? []
  guthaben.value = g ?? []
  kaeufe.value = k ?? []
  if (l?.kiosk_gruppe_modus) gruppeModus.value = l.kiosk_gruppe_modus

  const { data: tn } = await supabase.from('anmeldungen_tn').select('id, vorname, nachname').eq('lager_id', props.lagerId)
  const { data: gruppen } = await supabase.from('lagergruppen').select('id, name').eq('lager_id', props.lagerId).order('name')
  const gruppenMap = new Map((gruppen ?? []).map((g, i) => [g.id, i + 1]))
  const { data: mitglieder } = await supabase.from('gruppen_mitglieder').select('anmeldung_tn_id, lagergruppe_id').not('anmeldung_tn_id', 'is', null)
  const tnGruppe = new Map((mitglieder ?? []).map((m) => [m.anmeldung_tn_id, gruppenMap.get(m.lagergruppe_id) ?? null]))
  tnListe.value = (tn ?? []).map((t) => ({ ...t, gruppe_nr: tnGruppe.get(t.id) ?? null }))
}

onMounted(laden)

function guthabenFuer(tnId: string) {
  const g = guthaben.value.find((x) => x.anmeldung_tn_id === tnId)
  const start = g?.betrag_start ?? 0
  const ausgegeben = kaeufe.value.filter((k) => k.anmeldung_tn_id === tnId).reduce((s, k) => s + k.preis * k.menge, 0)
  const ausgezahlt = g?.betrag_ausgezahlt ?? 0
  return { start, ausgegeben, rest: start - ausgegeben - ausgezahlt }
}

async function artikelHinzufuegen() {
  await supabase.from('kiosk_artikel').insert({
    lager_id: props.lagerId, name: artForm.value.name, preis: artForm.value.preis, kategorie: artForm.value.kategorie,
  })
  artForm.value.name = ''
  await laden()
}

async function geldErfassen() {
  if (!geldForm.value.tnId) return
  await supabase.from('kiosk_guthaben').upsert({
    lager_id: props.lagerId,
    anmeldung_tn_id: geldForm.value.tnId,
    betrag_start: geldForm.value.betrag,
  }, { onConflict: 'lager_id,anmeldung_tn_id' })
  await laden()
}

async function kaufErfassen() {
  const art = artikel.value.find((a) => a.id === kaufForm.value.artikelId)
  if (!art || !kaufForm.value.tnId) return
  await supabase.from('kiosk_kaeufe').insert({
    lager_id: props.lagerId,
    anmeldung_tn_id: kaufForm.value.tnId,
    artikel_id: art.id,
    artikel_name: art.name,
    preis: art.preis,
    menge: kaufForm.value.menge,
  })
  await laden()
}

async function modusSpeichern() {
  await supabase.from('lager').update({ kiosk_gruppe_modus: gruppeModus.value }).eq('id', props.lagerId)
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <div class="kiosk-stats">
      <span>Umsatz: CHF {{ stats.umsatz.toFixed(2) }}</span>
      <span>{{ stats.anzahl }} Käufe</span>
      <label>Gruppe heute
        <select v-model="gruppeModus" @change="modusSpeichern">
          <option value="gerade">Gerade Gruppennummern</option>
          <option value="ungerade">Ungerade Gruppennummern</option>
          <option value="alle">Alle</option>
        </select>
      </label>
    </div>

    <h3>Artikel</h3>
    <form class="inline-form" @submit.prevent="artikelHinzufuegen">
      <input v-model="artForm.name" placeholder="Artikel" required />
      <input v-model.number="artForm.preis" type="number" step="0.1" min="0" />
      <input v-model="artForm.kategorie" placeholder="Kategorie" />
      <button type="submit">+ Artikel</button>
    </form>
    <ul class="liste-kompakt">
      <li v-for="a in artikel" :key="a.id">{{ a.name }} – CHF {{ a.preis.toFixed(2) }}</li>
    </ul>

    <h3>Geld erfassen (Anreise)</h3>
    <form class="inline-form" @submit.prevent="geldErfassen">
      <select v-model="geldForm.tnId" required>
        <option value="">Kind wählen</option>
        <option v-for="t in tnListe" :key="t.id" :value="t.id">{{ t.vorname }} {{ t.nachname }}</option>
      </select>
      <input v-model.number="geldForm.betrag" type="number" step="0.5" min="0" />
      <button type="submit">Speichern</button>
    </form>

    <h3>Kauf erfassen</h3>
    <form class="inline-form" @submit.prevent="kaufErfassen">
      <select v-model="kaufForm.tnId" required>
        <option value="">Kind</option>
        <option v-for="t in tnListe" :key="t.id" :value="t.id">{{ t.vorname }} {{ t.nachname }} (Rest: CHF {{ guthabenFuer(t.id).rest.toFixed(2) }})</option>
      </select>
      <select v-model="kaufForm.artikelId" required>
        <option value="">Artikel</option>
        <option v-for="a in artikel" :key="a.id" :value="a.id">{{ a.name }}</option>
      </select>
      <input v-model.number="kaufForm.menge" type="number" min="1" />
      <button type="submit">Kauf</button>
    </form>

    <h3>Übersicht Kinder</h3>
    <table class="liste">
      <thead><tr><th>Kind</th><th>Gruppe</th><th>Start</th><th>Ausgegeben</th><th>Rest</th></tr></thead>
      <tbody>
        <tr v-for="t in tnListe" :key="t.id">
          <td>{{ t.vorname }} {{ t.nachname }}</td>
          <td>{{ t.gruppe_nr ?? '–' }}</td>
          <td>{{ guthabenFuer(t.id).start.toFixed(2) }}</td>
          <td>{{ guthabenFuer(t.id).ausgegeben.toFixed(2) }}</td>
          <td><strong>{{ guthabenFuer(t.id).rest.toFixed(2) }}</strong></td>
        </tr>
      </tbody>
    </table>
  </AemtliShell>
</template>

<style scoped>
.kiosk-stats { display: flex; flex-wrap: wrap; gap: 1rem; margin-bottom: 1rem; font-size: 0.9rem; align-items: end; }
.kiosk-stats label { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.82rem; color: var(--color-text-muted); }
h3 { margin: 1rem 0 0.4rem; font-size: 0.95rem; }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 0.4rem 0; align-items: end; }
.liste-kompakt { list-style: none; padding: 0; font-size: 0.88rem; }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; margin-top: 0.5rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); text-align: left; }
</style>
