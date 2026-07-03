<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../supabaseClient'

const props = defineProps<{ lagerId: string }>()

interface Spieler { id: string; anmeldung_leiter_id: string; status: string; ziel_ort: string | null; ziel_gegenstand: string | null; ziel_leiter_id: string | null; leiter: { vorname: string; nachname: string } }
interface Ereignis { id: string; bestaetigt: boolean; moerder_id: string; opfer_id: string; moerder: { vorname: string; nachname: string } }

const spiel = ref({ aktiv: false, oeffentlich: false })
const spieler = ref<Spieler[]>([])
const ereignisse = ref<Ereignis[]>([])
const meineId = ref<string | null>(null)
const meinSpieler = ref<Spieler | null>(null)
const zielName = ref('')
const fehler = ref('')
const bestaetigen = ref(false)

const meinOffenesEreignis = computed(() =>
  ereignisse.value.find((e) => e.opfer_id === meineId.value && !e.bestaetigt) ?? null,
)

async function laden() {
  const { data: session } = await supabase.auth.getSession()
  const email = session.session?.user.email
  if (email) {
    const { data: me } = await supabase.from('anmeldungen_leiter').select('id').eq('lager_id', props.lagerId).ilike('email', email).maybeSingle()
    meineId.value = me?.id ?? null
  }
  const [{ data: s }, { data: sp }, { data: e }] = await Promise.all([
    supabase.from('gute_fee_spiel').select('aktiv, oeffentlich').eq('lager_id', props.lagerId).maybeSingle(),
    supabase.from('gute_fee_spieler').select('*, leiter:anmeldung_leiter_id(vorname, nachname)').eq('lager_id', props.lagerId),
    supabase.from('gute_fee_ereignisse').select('id, bestaetigt, moerder_id, opfer_id, moerder:moerder_id(vorname, nachname)').eq('lager_id', props.lagerId),
  ])
  if (s) spiel.value = s
  spieler.value = (sp ?? []) as Spieler[]
  ereignisse.value = (e ?? []) as unknown as Ereignis[]
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
  fehler.value = 'Mord gemeldet – dein Opfer muss ihn jetzt hier in der App bestätigen.'
  await laden()
}

async function mordBestaetigen(ereignisId: string) {
  bestaetigen.value = true
  await supabase.from('gute_fee_ereignisse').update({ bestaetigt: true }).eq('id', ereignisId)
  const { data: e } = await supabase.from('gute_fee_ereignisse').select('opfer_id, moerder_id').eq('id', ereignisId).single()
  if (e?.opfer_id) {
    await supabase.from('gute_fee_spieler').update({ status: 'tot' }).eq('lager_id', props.lagerId).eq('anmeldung_leiter_id', e.opfer_id)
    // Mörder übernimmt Ziel (Ort, Gegenstand, Person) des Opfers
    const { data: opferSp } = await supabase.from('gute_fee_spieler').select('ziel_ort, ziel_gegenstand, ziel_leiter_id').eq('lager_id', props.lagerId).eq('anmeldung_leiter_id', e.opfer_id).single()
    if (opferSp && e.moerder_id) {
      await supabase.from('gute_fee_spieler').update({
        ziel_ort: opferSp.ziel_ort,
        ziel_gegenstand: opferSp.ziel_gegenstand,
        ziel_leiter_id: opferSp.ziel_leiter_id,
      }).eq('lager_id', props.lagerId).eq('anmeldung_leiter_id', e.moerder_id)
    }
  }
  bestaetigen.value = false
  await laden()
}
</script>

<template>
  <main class="moerderli-page">
    <router-link :to="`/lager/${lagerId}/dashboard`" class="zurueck">← Lager</router-link>
    <h1>Mörderli</h1>

    <p class="regeln">
      So funktioniert's: Jede/r Leiter/in bekommt insgeheim eine Zielperson zugewiesen, dazu einen Ort und einen
      Gegenstand. Triffst du deine Zielperson genau an diesem Ort mit genau diesem Gegenstand an, hast du sie
      „ermordet" – klick unten auf „Ermordet melden". Deine Zielperson muss den Mord dann selbst hier bestätigen
      (siehe unten, sobald jemand dich meldet). Sobald bestätigt: die Zielperson scheidet aus, und du übernimmst
      automatisch ihr Ziel (Person, Ort, Gegenstand) als deine neue Aufgabe. Wer als Letzte/r übrig bleibt, gewinnt.
    </p>

    <p v-if="!spiel.oeffentlich" class="hint">Das Spiel ist noch nicht freigeschaltet.</p>

    <section v-if="meinOffenesEreignis" class="bestaetigen-karte">
      <h2>Wurdest du ermordet?</h2>
      <p>
        <strong>{{ meinOffenesEreignis.moerder?.vorname }} {{ meinOffenesEreignis.moerder?.nachname }}</strong>
        behauptet, dich an deinem Ort mit deinem Gegenstand erwischt zu haben.
      </p>
      <button @click="mordBestaetigen(meinOffenesEreignis.id)" :disabled="bestaetigen">
        {{ bestaetigen ? 'Bestätige...' : 'Ja, bestätigen' }}
      </button>
    </section>

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
.regeln {
  background: var(--color-surface-muted); border-radius: var(--radius-md);
  padding: 0.75rem 1rem; font-size: 0.88rem; line-height: 1.5; color: var(--color-text-muted); margin: 0.75rem 0 1.25rem;
}
.bestaetigen-karte {
  background: var(--color-pill-bg); border-radius: var(--radius-md); padding: 1rem; margin: 1rem 0;
}
.meine-karte { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 1rem; margin: 1rem 0; }
.board ul { list-style: none; padding: 0; }
.board li { padding: 0.35rem 0; display: flex; justify-content: space-between; }
.board li.tot { opacity: 0.45; text-decoration: line-through; }
.badge { font-size: 0.75rem; background: var(--color-pill-bg); padding: 0.1rem 0.4rem; border-radius: var(--radius-pill); }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
