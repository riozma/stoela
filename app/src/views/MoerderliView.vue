<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../supabaseClient'

const props = defineProps<{ lagerId: string }>()

interface Spieler { id: string; anmeldung_leiter_id: string; status: string; ziel_ort: string | null; ziel_gegenstand: string | null; ziel_leiter_id: string | null; leiter: { vorname: string; nachname: string } }
interface Ereignis { id: string; bestaetigt: boolean; moerder_id: string; opfer_id: string }

const spiel = ref({ aktiv: false, oeffentlich: false })
const spieler = ref<Spieler[]>([])
const meineId = ref<string | null>(null)
const meinSpieler = ref<Spieler | null>(null)
const zielName = ref('')
const fehler = ref('')

async function laden() {
  const { data: session } = await supabase.auth.getSession()
  const email = session.session?.user.email
  if (email) {
    const { data: me } = await supabase.from('anmeldungen_leiter').select('id').eq('lager_id', props.lagerId).ilike('email', email).maybeSingle()
    meineId.value = me?.id ?? null
  }
  const [{ data: s }, { data: sp }] = await Promise.all([
    supabase.from('gute_fee_spiel').select('aktiv, oeffentlich').eq('lager_id', props.lagerId).maybeSingle(),
    supabase.from('gute_fee_spieler').select('*, leiter:anmeldung_leiter_id(vorname, nachname)').eq('lager_id', props.lagerId),
  ])
  if (s) spiel.value = s
  spieler.value = (sp ?? []) as Spieler[]
  meinSpieler.value = spieler.value.find((x) => x.anmeldung_leiter_id === meineId.value) ?? null
  if (meinSpieler.value?.ziel_leiter_id) {
    const z = spieler.value.find((x) => x.anmeldung_leiter_id === meinSpieler.value!.ziel_leiter_id)
    zielName.value = z ? `${z.leiter?.vorname} ${z.leiter?.nachname}` : '?'
  }
}

onMounted(laden)

async function mordMelden() {
  if (!meineId.value || !meinSpieler.value?.ziel_leiter_id) return
  await supabase.from('gute_fee_ereignisse').insert({
    lager_id: props.lagerId,
    moerder_id: meineId.value,
    opfer_id: meinSpieler.value.ziel_leiter_id,
    bestaetigt: false,
  })
  fehler.value = 'Mord gemeldet – Opfer muss bestätigen oder Gute Fee entscheidet.'
  await laden()
}

async function mordBestaetigen(ereignisId: string) {
  await supabase.from('gute_fee_ereignisse').update({ bestaetigt: true }).eq('id', ereignisId)
  const { data: e } = await supabase.from('gute_fee_ereignisse').select('opfer_id').eq('id', ereignisId).single()
  if (e?.opfer_id) {
    await supabase.from('gute_fee_spieler').update({ status: 'tot' }).eq('lager_id', props.lagerId).eq('anmeldung_leiter_id', e.opfer_id)
    // Mörder übernimmt Aufgabe des Opfers
    const { data: opferSp } = await supabase.from('gute_fee_spieler').select('ziel_ort, ziel_gegenstand, ziel_leiter_id').eq('lager_id', props.lagerId).eq('anmeldung_leiter_id', e.opfer_id).single()
    const { data: ereignis } = await supabase.from('gute_fee_ereignisse').select('moerder_id').eq('id', ereignisId).single()
    if (opferSp && ereignis?.moerder_id) {
      await supabase.from('gute_fee_spieler').update({
        ziel_ort: opferSp.ziel_ort,
        ziel_gegenstand: opferSp.ziel_gegenstand,
        ziel_leiter_id: opferSp.ziel_leiter_id,
      }).eq('lager_id', props.lagerId).eq('anmeldung_leiter_id', ereignis.moerder_id)
    }
  }
  await laden()
}
</script>

<template>
  <main class="moerderli-page">
    <router-link :to="`/lager/${lagerId}/dashboard`" class="zurueck">← Lager</router-link>
    <h1>Mörderli</h1>

    <p v-if="!spiel.oeffentlich" class="hint">Das Spiel ist noch nicht freigeschaltet.</p>

    <section v-if="meinSpieler && meinSpieler.status === 'lebend' && spiel.aktiv" class="meine-karte">
      <h2>Deine Aufgabe</h2>
      <p><strong>Ort:</strong> {{ meinSpieler.ziel_ort ?? '–' }}</p>
      <p><strong>Gegenstand:</strong> {{ meinSpieler.ziel_gegenstand ?? '–' }}</p>
      <p><strong>Person:</strong> {{ zielName }}</p>
      <button @click="mordMelden">Ermordet melden</button>
    </section>

    <section class="board">
      <h2>Status</h2>
      <ul>
        <li v-for="s in spieler" :key="s.id" :class="s.status">
          {{ s.leiter?.vorname }} {{ s.leiter?.nachname }}
          <span class="badge">{{ s.status === 'lebend' ? 'lebt' : 'tot' }}</span>
        </li>
      </ul>
    </section>
    <p v-if="fehler" class="hint">{{ fehler }}</p>
  </main>
</template>

<style scoped>
main { max-width: 560px; margin: 2rem auto; padding: 0 1rem; }
.zurueck { color: var(--color-accent); text-decoration: none; font-size: 0.88rem; }
.meine-karte { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 1rem; margin: 1rem 0; }
.board ul { list-style: none; padding: 0; }
.board li { padding: 0.35rem 0; display: flex; justify-content: space-between; }
.board li.tot { opacity: 0.45; text-decoration: line-through; }
.badge { font-size: 0.75rem; background: var(--color-pill-bg); padding: 0.1rem 0.4rem; border-radius: var(--radius-pill); }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
