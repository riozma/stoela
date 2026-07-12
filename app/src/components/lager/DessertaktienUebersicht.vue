<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'

interface Dessertaktie {
  id: string
  name: string
  betrag: number
}

const props = defineProps<{
  lagerId: string
  bearbeitbar?: boolean
}>()

const liste = ref<Dessertaktie[]>([])
const laden = ref(true)
const fehler = ref('')
const form = ref({ name: '', betrag: '' })
const speichern = ref(false)

async function laderListe() {
  laden.value = true
  const { data } = await supabase
    .from('dessertaktien')
    .select('id, name, betrag')
    .eq('lager_id', props.lagerId)
    .order('created_at', { ascending: false })
  liste.value = (data ?? []) as Dessertaktie[]
  laden.value = false
}

onMounted(laderListe)

const sichtbareListe = computed(() => liste.value.filter((d) => d.betrag > 0))
const summe = computed(() => sichtbareListe.value.reduce((acc, d) => acc + Number(d.betrag), 0))

async function hinzufuegen() {
  const betrag = Number(form.value.betrag)
  if (!form.value.name.trim() || !betrag || betrag <= 0) {
    fehler.value = 'Bitte Name/Team und einen Betrag grösser 0 angeben.'
    return
  }
  fehler.value = ''
  speichern.value = true
  const { error } = await supabase.from('dessertaktien').insert({
    lager_id: props.lagerId,
    name: form.value.name.trim(),
    betrag,
  })
  speichern.value = false
  if (error) { fehler.value = error.message; return }
  form.value = { name: '', betrag: '' }
  await laderListe()
}
</script>

<template>
  <div class="dessertaktien">
    <h3>Dessertaktien</h3>
    <p class="hint">
      Zustupf pro Elternteil, mit dem das Dessert finanziert wird.
      Wer nichts gegeben hat, wird hier nicht aufgeführt.
    </p>

    <form v-if="bearbeitbar" class="form-zeile" @submit.prevent="hinzufuegen">
      <input v-model="form.name" placeholder="Name (Elternteil)" />
      <input v-model="form.betrag" type="number" min="0" step="0.05" placeholder="Betrag CHF" />
      <button type="submit" :disabled="speichern">{{ speichern ? 'Speichere…' : 'Erfassen' }}</button>
    </form>
    <p v-if="fehler" class="error">{{ fehler }}</p>

    <p v-if="laden" class="hint">Lade…</p>
    <template v-else>
      <ul v-if="sichtbareListe.length" class="liste">
        <li v-for="d in sichtbareListe" :key="d.id">
          <span>{{ d.name }}</span>
          <strong>CHF {{ d.betrag }}.–</strong>
        </li>
      </ul>
      <p v-else class="hint">Noch keine Dessertaktien erfasst.</p>
      <p v-if="sichtbareListe.length" class="summe">Total: <strong>CHF {{ summe }}.–</strong></p>
    </template>
  </div>
</template>

<style scoped>
.dessertaktien h3 { margin: 0 0 0.35rem; font-size: 1rem; }
.hint { color: var(--color-text-muted); font-size: 0.85rem; margin: 0 0 0.6rem; }
.form-zeile { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 0.75rem; }
.form-zeile input { flex: 1; min-width: 100px; }
.error { color: var(--color-danger); font-size: 0.85rem; }
.liste { list-style: none; padding: 0; margin: 0; }
.liste li {
  display: flex; justify-content: space-between; gap: 0.5rem;
  padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); font-size: 0.9rem;
}
.summe { margin-top: 0.6rem; font-size: 0.95rem; }
</style>
