<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { featureAktiv } from '../../lib/lagerTimeline'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{
  lagerId: string
  aemtliId: string
  aemtliName: string
  isGuteFee?: boolean
  startDatum?: string | null
  endDatum?: string | null
}>()

const moerderliAktiv = computed(() =>
  featureAktiv('moerderli', props.startDatum ?? null, props.endDatum ?? null),
)

interface Spieler { id: string; anmeldung_leiter_id: string; status: string; leiter: { vorname: string; nachname: string } }
interface Ereignis { id: string; bestaetigt: boolean; created_at: string; moerder: { vorname: string; nachname: string }; opfer: { vorname: string; nachname: string } }

const orte = ref<{ id: string; wert: string }[]>([])
const gegenstaende = ref<{ id: string; wert: string }[]>([])
const spieler = ref<Spieler[]>([])
const ereignisse = ref<Ereignis[]>([])
const spiel = ref({ aktiv: false, oeffentlich: false })
const ortInput = ref('')
const gegenInput = ref('')
const fehler = ref('')

async function laden() {
  const [{ data: l }, { data: s }, { data: sp }, { data: e }] = await Promise.all([
    supabase.from('gute_fee_liste').select('id, typ, wert').eq('lager_id', props.lagerId).order('sortierung'),
    supabase.from('gute_fee_spiel').select('aktiv, oeffentlich').eq('lager_id', props.lagerId).maybeSingle(),
    supabase.from('gute_fee_spieler').select('id, anmeldung_leiter_id, status, leiter:anmeldung_leiter_id(vorname, nachname)').eq('lager_id', props.lagerId),
    supabase.from('gute_fee_ereignisse').select('id, bestaetigt, created_at, moerder:moerder_id(vorname, nachname), opfer:opfer_id(vorname, nachname)').eq('lager_id', props.lagerId).order('created_at', { ascending: false }),
  ])
  orte.value = (l ?? []).filter((x) => x.typ === 'ort')
  gegenstaende.value = (l ?? []).filter((x) => x.typ === 'gegenstand')
  spieler.value = (sp ?? []) as unknown as Spieler[]
  ereignisse.value = (e ?? []) as unknown as Ereignis[]
  if (s) spiel.value = s
}

onMounted(laden)

async function listeHinzufuegen(typ: 'ort' | 'gegenstand', wert: string) {
  if (!wert.trim()) return
  await supabase.from('gute_fee_liste').insert({ lager_id: props.lagerId, typ, wert: wert.trim() })
  ortInput.value = ''; gegenInput.value = ''
  await laden()
}

async function spielerLaden() {
  const { data: leiter } = await supabase.from('anmeldungen_leiter').select('id').eq('lager_id', props.lagerId).eq('status', 'bestaetigt')
  for (const l of leiter ?? []) {
    await supabase.from('gute_fee_spieler').upsert({ lager_id: props.lagerId, anmeldung_leiter_id: l.id, status: 'lebend' }, { onConflict: 'lager_id,anmeldung_leiter_id' })
  }
  await supabase.from('gute_fee_spiel').upsert({ lager_id: props.lagerId, aktiv: false, oeffentlich: false })
  await laden()
}

async function zuweisen() {
  fehler.value = ''
  const { data, error } = await supabase.rpc('gute_fee_zuweisen', { p_lager_id: props.lagerId })
  if (error) { fehler.value = error.message; return }
  fehler.value = `${data} Zuweisungen erstellt.`
  await laden()
}

async function oeffentlichSchalten() {
  await supabase.from('gute_fee_spiel').upsert({ lager_id: props.lagerId, oeffentlich: true, aktiv: true })
  await laden()
}

async function wiederbeleben(leiterId: string) {
  await supabase.from('gute_fee_spieler').update({ status: 'lebend' }).eq('lager_id', props.lagerId).eq('anmeldung_leiter_id', leiterId)
  await laden()
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <p class="regeln">
      So läuft das Mörderli-Spiel ab: 1) Trag unten ein paar <strong>Orte</strong> und <strong>Gegenstände</strong>
      ein, die im Lagerhaus/-gelände vorkommen. 2) Sobald die bestätigten Leiter feststehen, klick
      „Spieler aus Leiter-Liste laden". 3) Klick „Mörderli zuweisen (random)" – jede/r Leiter/in bekommt zufällig
      eine Zielperson plus einen Ort und Gegenstand aus deinen Listen zugewiesen (per Zufalls-Funktion in der
      Datenbank, nicht manuell). 4) Klick „Board für alle freischalten", damit alle ihre Aufgabe unter
      „→ Mörderli-Board" sehen können. Danach läuft alles automatisch: wer meldet, ermordet zu haben, muss vom
      Opfer selbst im Board bestätigt werden – bestätigte Opfer scheiden aus, ihr Ziel geht an den Mörder über.
      Hier siehst du den Verlauf aller Ereignisse und kannst bei Bedarf jemanden „Wiederbeleben".
    </p>

    <p v-if="!moerderliAktiv" class="zeit-hinweis">
      Mörderli-Spiel ist erst <strong>während dem Lager</strong> aktiv (nicht während Programmblöcken).
      Orte und Gegenstände kannst du schon vorbereiten.
    </p>

    <div v-if="moerderliAktiv" class="aktionen">
      <button type="button" class="secondary" @click="spielerLaden">Spieler aus Leiter-Liste laden</button>
      <button type="button" @click="zuweisen">Mörderli zuweisen (random)</button>
      <button type="button" class="secondary" @click="oeffentlichSchalten">Board für alle freischalten</button>
      <router-link :to="`/lager/${lagerId}/moerderli`" class="secondary link-btn">→ Mörderli-Board</router-link>
    </div>
    <p v-if="fehler" class="hint">{{ fehler }}</p>

    <div class="grid-2">
      <div>
        <h3>Orte</h3>
        <form @submit.prevent="listeHinzufuegen('ort', ortInput)"><input v-model="ortInput" placeholder="Ort" /><button type="submit">+</button></form>
        <ul><li v-for="o in orte" :key="o.id">{{ o.wert }}</li></ul>
      </div>
      <div>
        <h3>Gegenstände</h3>
        <form @submit.prevent="listeHinzufuegen('gegenstand', gegenInput)"><input v-model="gegenInput" placeholder="Gegenstand" /><button type="submit">+</button></form>
        <ul><li v-for="g in gegenstaende" :key="g.id">{{ g.wert }}</li></ul>
      </div>
    </div>

    <template v-if="moerderliAktiv">
      <h3>Spieler ({{ spieler.filter(s => s.status === 'lebend').length }} lebend)</h3>
      <ul class="spieler-liste">
        <li v-for="s in spieler" :key="s.id" :class="s.status">
          {{ s.leiter?.vorname }} {{ s.leiter?.nachname }}
          <span class="status">{{ s.status }}</span>
          <button v-if="isGuteFee && s.status === 'tot'" class="secondary klein" @click="wiederbeleben(s.anmeldung_leiter_id)">Wiederbeleben</button>
        </li>
      </ul>

      <h3>Ereignisse</h3>
      <ul v-if="ereignisse.length" class="ereignisse">
        <li v-for="e in ereignisse" :key="e.id">
          {{ e.moerder?.vorname }} → {{ e.opfer?.vorname }}
          <span :class="{ ok: e.bestaetigt }">{{ e.bestaetigt ? 'bestätigt' : 'offen' }}</span>
        </li>
      </ul>
    </template>
  </AemtliShell>
</template>

<style scoped>
.aktionen { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 1rem; }
.link-btn { display: inline-flex; align-items: center; padding: 0.55rem 1rem; text-decoration: none; border-radius: var(--radius-pill); }
.grid-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
h3 { font-size: 0.95rem; margin: 0.75rem 0 0.35rem; }
form { display: flex; gap: 0.35rem; margin-bottom: 0.5rem; }
.spieler-liste { list-style: none; padding: 0; }
.spieler-liste li { padding: 0.35rem 0; display: flex; gap: 0.5rem; align-items: center; }
.spieler-liste li.tot { opacity: 0.5; text-decoration: line-through; }
.status { font-size: 0.75rem; color: var(--color-text-muted); }
.ereignisse { font-size: 0.88rem; }
.ok { color: var(--color-accent); }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.45rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.regeln {
  background: var(--color-surface-muted); border-radius: var(--radius-md);
  padding: 0.75rem 1rem; font-size: 0.88rem; line-height: 1.5; color: var(--color-text-muted); margin-bottom: 1rem;
}
.zeit-hinweis {
  background: var(--color-surface-muted); padding: 0.6rem 0.85rem;
  border-radius: var(--radius-md); margin-bottom: 1rem; font-size: 0.88rem;
}
</style>
