<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliTodos from './AemtliTodos.vue'

interface TN {
  id: string
  vorname: string
  nachname: string
  status: string
}

interface TnFinanz {
  anmeldung_tn_id: string
  bezahlt: boolean
  bemerkung: string | null
  reduktion: string | null
}

const props = defineProps<{
  lagerId: string
  aemtliId: string
  istKassier: boolean
}>()

const tnListe = ref<TN[]>([])
const finanzen = ref<Record<string, TnFinanz>>({})
const fehler = ref('')
const speichern = ref<string | null>(null)

async function laden() {
  const { data: tn } = await supabase
    .from('anmeldungen_tn')
    .select('id, vorname, nachname, status')
    .eq('lager_id', props.lagerId)
    .order('nachname')
  tnListe.value = tn ?? []

  const tnIds = tnListe.value.map((t) => t.id)
  if (!tnIds.length) {
    finanzen.value = {}
    return
  }

  const { data: fin } = await supabase
    .from('tn_finanzen')
    .select('anmeldung_tn_id, bezahlt, bemerkung, reduktion')
    .in('anmeldung_tn_id', tnIds)

  const map: Record<string, TnFinanz> = {}
  for (const f of fin ?? []) {
    map[f.anmeldung_tn_id] = f
  }
  finanzen.value = map
}

onMounted(laden)

function getFin(tnId: string): TnFinanz {
  return finanzen.value[tnId] ?? { anmeldung_tn_id: tnId, bezahlt: false, bemerkung: null, reduktion: null }
}

async function speichere(tnId: string, patch: Partial<TnFinanz>) {
  speichern.value = tnId
  fehler.value = ''
  const aktuell = getFin(tnId)
  const payload = {
    anmeldung_tn_id: tnId,
    bezahlt: patch.bezahlt ?? aktuell.bezahlt,
    bemerkung: patch.bemerkung !== undefined ? patch.bemerkung : aktuell.bemerkung,
    reduktion: patch.reduktion !== undefined ? patch.reduktion : aktuell.reduktion,
    updated_at: new Date().toISOString(),
  }
  const { error } = await supabase.from('tn_finanzen').upsert(payload, { onConflict: 'anmeldung_tn_id' })
  speichern.value = null
  if (error) { fehler.value = error.message; return }
  finanzen.value[tnId] = payload
}

const bezahltCount = computed(() => Object.values(finanzen.value).filter((f) => f.bezahlt).length)
</script>

<template>
    <section class="finanzen">
    <h2>Finanzen – TN-Anmeldungen</h2>
    <AemtliTodos :lager-id="lagerId" :aemtli-id="aemtliId" aemtli-name="Finanzen" />
    <p class="hint">
      {{ bezahltCount }} / {{ tnListe.length }} als bezahlt markiert.
      <span v-if="istKassier"> Quittungen bearbeitest du unter «Quittungen» → Kassier-Übersicht.</span>
    </p>
    <p v-if="fehler" class="error">{{ fehler }}</p>

    <table v-if="tnListe.length" class="liste">
      <thead>
        <tr>
          <th>Name</th>
          <th>Status</th>
          <th>Bezahlt</th>
          <th>Reduktion</th>
          <th>Bemerkung</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="tn in tnListe" :key="tn.id">
          <td>{{ tn.vorname }} {{ tn.nachname }}</td>
          <td>{{ tn.status }}</td>
          <td>
            <input
              type="checkbox"
              :checked="getFin(tn.id).bezahlt"
              :disabled="speichern === tn.id"
              @change="speichere(tn.id, { bezahlt: ($event.target as HTMLInputElement).checked })"
            />
          </td>
          <td>
            <input
              class="feld-klein"
              :value="getFin(tn.id).reduktion ?? ''"
              placeholder="z.B. 50%"
              @change="speichere(tn.id, { reduktion: ($event.target as HTMLInputElement).value || null })"
            />
          </td>
          <td>
            <input
              class="feld-bemerkung"
              :value="getFin(tn.id).bemerkung ?? ''"
              placeholder="Notiz..."
              @change="speichere(tn.id, { bemerkung: ($event.target as HTMLInputElement).value || null })"
            />
          </td>
        </tr>
      </tbody>
    </table>
    <p v-else class="hint">Noch keine Teilnehmer angemeldet.</p>
  </section>
</template>

<style scoped>
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin-bottom: 1rem; }
.liste { width: 100%; border-collapse: collapse; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); font-size: 0.88rem; }
.liste th, .liste td { text-align: left; padding: 0.5rem 0.65rem; border-bottom: 1px solid var(--color-border); vertical-align: middle; }
.liste th { color: var(--color-text-muted); font-size: 0.78rem; }
.feld-klein { width: 80px; }
.feld-bemerkung { width: 100%; min-width: 140px; }
.error { color: var(--color-danger); }
</style>
