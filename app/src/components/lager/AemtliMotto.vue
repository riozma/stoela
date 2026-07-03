<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

interface Vorschlag {
  id: string
  vorschlag: string
  stimmen: number
}

const gewaehltesMotto = ref('')
const vorschlaege = ref<Vorschlag[]>([])
const neuerVorschlag = ref('')

const topVorschlaege = computed(() => [...vorschlaege.value].sort((a, b) => b.stimmen - a.stimmen))

async function laden() {
  const [{ data: lager }, { data: liste }] = await Promise.all([
    supabase.from('lager').select('motto').eq('id', props.lagerId).single(),
    supabase.from('motto_vorschlaege').select('id, vorschlag, stimmen').eq('lager_id', props.lagerId).order('stimmen', { ascending: false }),
  ])
  gewaehltesMotto.value = lager?.motto ?? ''
  vorschlaege.value = liste ?? []
}

onMounted(laden)

async function vorschlagHinzufuegen() {
  const text = neuerVorschlag.value.trim()
  if (!text) return
  await supabase.from('motto_vorschlaege').insert({ lager_id: props.lagerId, vorschlag: text })
  neuerVorschlag.value = ''
  await laden()
}

async function abstimmen(id: string) {
  const v = vorschlaege.value.find((x) => x.id === id)
  if (!v) return
  await supabase.from('motto_vorschlaege').update({ stimmen: v.stimmen + 1 }).eq('id', id)
  await laden()
}

async function alsMottoFestlegen(text: string) {
  await supabase.from('lager').update({ motto: text }).eq('id', props.lagerId)
  gewaehltesMotto.value = text
}

async function vorschlagLoeschen(id: string) {
  await supabase.from('motto_vorschlaege').delete().eq('id', id)
  await laden()
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <div class="gewaehlt-box">
      <span class="label">Gewähltes Motto</span>
      <strong v-if="gewaehltesMotto">{{ gewaehltesMotto }}</strong>
      <span v-else class="hint">Noch nicht festgelegt</span>
    </div>

    <h3>Vorschläge &amp; Abstimmung</h3>
    <form class="inline-form" @submit.prevent="vorschlagHinzufuegen">
      <input v-model="neuerVorschlag" placeholder="Neuer Motto-Vorschlag" required />
      <button type="submit">+ Vorschlag</button>
    </form>

    <ul v-if="topVorschlaege.length" class="liste">
      <li v-for="v in topVorschlaege" :key="v.id" :class="{ aktiv: v.vorschlag === gewaehltesMotto }">
        <span class="vorschlag-text">{{ v.vorschlag }}</span>
        <span class="stimmen">{{ v.stimmen }} Stimmen</span>
        <button type="button" class="secondary klein" @click="abstimmen(v.id)">+1</button>
        <button type="button" class="secondary klein" @click="alsMottoFestlegen(v.vorschlag)">Als Motto festlegen</button>
        <button type="button" class="secondary klein loeschen-btn" @click="vorschlagLoeschen(v.id)">✕</button>
      </li>
    </ul>
    <p v-else class="hint">Noch keine Vorschläge. Mindestens 3 ausarbeiten und im Leiterteam abstimmen.</p>
  </AemtliShell>
</template>

<style scoped>
.gewaehlt-box {
  display: flex; flex-direction: column; gap: 0.15rem;
  background: var(--color-surface-muted); border: 1px solid var(--color-border);
  border-radius: var(--radius-md); padding: 0.65rem 0.9rem; margin-bottom: 1rem;
}
.gewaehlt-box .label { font-size: 0.7rem; text-transform: uppercase; color: var(--color-text-muted); }
.gewaehlt-box strong { font-size: 1.1rem; }
h3 { margin: 0 0 0.5rem; font-size: 0.95rem; }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 0.75rem; }
.inline-form input { flex: 1; min-width: 180px; }
.liste { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 0.35rem; }
.liste li {
  display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem;
  padding: 0.45rem 0.65rem; border: 1px solid var(--color-border); border-radius: var(--radius-md);
}
.liste li.aktiv { border-color: var(--color-accent); background: var(--color-surface-muted); }
.vorschlag-text { flex: 1; min-width: 8rem; }
.stimmen { font-size: 0.78rem; color: var(--color-text-muted); }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.45rem; }
.loeschen-btn { color: var(--color-danger); }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
