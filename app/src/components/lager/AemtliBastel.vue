<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

interface Item {
  id: string
  name: string
  bestand: number
  min_bestand: number
  einheit: string | null
  notiz: string | null
  updated_at: string
  nachkaufen: boolean
  letzte_inventur_am: string | null
}

const items = ref<Item[]>([])
const form = ref({ name: '', bestand: 0, min_bestand: 1, einheit: 'Stk', notiz: '' })
const inventurOffen = ref(false)
const inventurBestand = ref<Record<string, number>>({})
const inventurStatus = ref<Record<string, 'genug' | 'nachkaufen'>>({})
const inventurSpeichern = ref(false)
const inventurErfolg = ref(false)

const niedrig = computed(() => items.value.filter((i) => i.bestand < i.min_bestand))

async function ladeOrgId() {
  const { data } = await supabase
    .from('lager')
    .select('organisation_id')
    .eq('id', props.lagerId)
    .single()
  return data?.organisation_id ?? null
}

async function laden() {
  const orgId = await ladeOrgId()
  if (!orgId) return
  const { data } = await supabase
    .from('org_bastel_inventar')
    .select('id, name, bestand, min_bestand, einheit, notiz, updated_at, nachkaufen, letzte_inventur_am')
    .eq('organisation_id', orgId)
    .order('name')
  items.value = data ?? []
  inventurBestand.value = Object.fromEntries(items.value.map((i) => [i.id, i.bestand]))
  inventurStatus.value = Object.fromEntries(
    items.value.map((i) => [i.id, i.nachkaufen ? 'nachkaufen' : 'genug']),
  )
}

onMounted(laden)

async function hinzufuegen() {
  const orgId = await ladeOrgId()
  if (!orgId) return
  await supabase.from('org_bastel_inventar').insert({
    organisation_id: orgId,
    name: form.value.name,
    bestand: form.value.bestand,
    min_bestand: form.value.min_bestand,
    einheit: form.value.einheit || 'Stk',
    notiz: form.value.notiz || null,
  })
  form.value = { name: '', bestand: 0, min_bestand: 1, einheit: 'Stk', notiz: '' }
  await laden()
}

async function bestandAendern(id: string, delta: number) {
  const item = items.value.find((i) => i.id === id)
  if (!item) return
  await supabase
    .from('org_bastel_inventar')
    .update({ bestand: Math.max(0, item.bestand + delta), updated_at: new Date().toISOString() })
    .eq('id', id)
  await laden()
}

async function notizSpeichern(id: string, notiz: string) {
  await supabase.from('org_bastel_inventar').update({ notiz: notiz || null }).eq('id', id)
  await laden()
}

async function loeschen(id: string) {
  if (!confirm('Artikel wirklich löschen?')) return
  await supabase.from('org_bastel_inventar').delete().eq('id', id)
  await laden()
}

async function inventurAbschliessen() {
  inventurSpeichern.value = true
  inventurErfolg.value = false
  await Promise.all(
    items.value.map((item) =>
      supabase
        .from('org_bastel_inventar')
        .update({
          bestand: Math.max(0, inventurBestand.value[item.id] ?? item.bestand),
          nachkaufen: inventurStatus.value[item.id] === 'nachkaufen',
          letzte_inventur_lager_id: props.lagerId,
          letzte_inventur_am: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('id', item.id),
    ),
  )
  inventurSpeichern.value = false
  inventurErfolg.value = true
  inventurOffen.value = false
  await laden()
}

function formatUpdated(iso: string) {
  return new Intl.DateTimeFormat('de-CH', { dateStyle: 'short' }).format(new Date(iso))
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <p v-if="niedrig.length" class="warn-hinweis">
      ⚠ {{ niedrig.length }} Artikel unter Mindestbestand:
      <strong>{{ niedrig.map(i => i.name).join(', ') }}</strong>
    </p>

    <section class="inventur">
      <div class="inventur-kopf">
        <div>
          <h3>Check Ende Lager</h3>
          <p class="hint">Bestand zählen und festhalten, was reicht oder nachgekauft werden muss.</p>
        </div>
        <button type="button" class="secondary" @click="inventurOffen = !inventurOffen">
          {{ inventurOffen ? 'Abbrechen' : 'Inventur starten' }}
        </button>
      </div>
      <div v-if="inventurOffen" class="inventur-liste">
        <div v-for="i in items" :key="i.id" class="inventur-zeile">
          <strong>{{ i.name }}</strong>
          <label>
            Bestand
            <input v-model.number="inventurBestand[i.id]" type="number" min="0" />
          </label>
          <label>
            Ergebnis
            <select v-model="inventurStatus[i.id]">
              <option value="genug">Genug vorhanden</option>
              <option value="nachkaufen">Nachkaufen</option>
            </select>
          </label>
        </div>
        <button type="button" :disabled="inventurSpeichern" @click="inventurAbschliessen">
          {{ inventurSpeichern ? 'Speichere…' : 'Inventur abschliessen' }}
        </button>
      </div>
      <p v-if="inventurErfolg" class="ok">Inventur gespeichert.</p>
    </section>

    <h3>Neuer Artikel</h3>
    <form class="inline-form" @submit.prevent="hinzufuegen">
      <input v-model="form.name" placeholder="Material (z.B. Schere, Farbe)" required />
      <input v-model.number="form.bestand" type="number" min="0" style="width:5rem" />
      <input v-model="form.einheit" placeholder="Einheit" style="width:5rem" />
      <input v-model.number="form.min_bestand" type="number" min="0" placeholder="Min." style="width:5rem" />
      <input v-model="form.notiz" placeholder="Notiz / Beschreibung" style="flex:1" />
      <button type="submit">+ Artikel</button>
    </form>

    <table class="liste">
      <thead>
        <tr>
          <th>Material</th>
          <th>Bestand</th>
          <th>Min.</th>
          <th>Status</th>
          <th>Notiz</th>
          <th>Aktualisiert</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="i in items" :key="i.id" :class="{ warn: i.bestand < i.min_bestand }">
          <td>{{ i.name }}<span v-if="i.einheit" class="einheit"> ({{ i.einheit }})</span></td>
          <td class="bestand-zelle">
            <button class="secondary klein" @click="bestandAendern(i.id, -1)">−</button>
            <strong>{{ i.bestand }}</strong>
            <button class="secondary klein" @click="bestandAendern(i.id, 1)">+</button>
          </td>
          <td>{{ i.min_bestand }}</td>
          <td>
            <span v-if="i.nachkaufen" class="status nachkaufen">Nachkaufen</span>
            <span v-else class="status genug">Genug</span>
          </td>
          <td>
            <input
              class="notiz-input"
              :value="i.notiz ?? ''"
              placeholder="–"
              @blur="notizSpeichern(i.id, ($event.target as HTMLInputElement).value)"
            />
          </td>
          <td class="datum-zelle">{{ formatUpdated(i.updated_at) }}</td>
          <td>
            <button class="secondary klein loeschen-btn" @click="loeschen(i.id)" title="Löschen">✕</button>
          </td>
        </tr>
      </tbody>
    </table>
    <p class="hint">Mehrjahres-Inventar – wächst mit dem Verein. Bestände nach jedem Lager aktualisieren.</p>
  </AemtliShell>
</template>

<style scoped>
h3 { margin: 0 0 0.5rem; font-size: 0.95rem; }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 0.5rem 0 1rem; align-items: end; }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); text-align: left; vertical-align: middle; }
.liste th { font-size: 0.75rem; color: var(--color-text-muted); text-transform: uppercase; }
tr.warn td { background: #fdf6f4; }
.warn-hinweis {
  background: #fdf6f4; border: 1px solid var(--color-danger); border-radius: var(--radius-md);
  padding: 0.5rem 0.85rem; font-size: 0.88rem; margin-bottom: 0.75rem;
}
.bestand-zelle { display: flex; align-items: center; gap: 0.35rem; }
.bestand-zelle strong { min-width: 1.5rem; text-align: center; }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.45rem; }
.loeschen-btn { color: var(--color-danger); }
.einheit { color: var(--color-text-muted); font-size: 0.8rem; }
.notiz-input { width: 100%; min-width: 8rem; border: 1px solid transparent; background: transparent; padding: 0.2rem 0.3rem; font-size: 0.83rem; border-radius: var(--radius-sm); }
.notiz-input:focus { border-color: var(--color-border); background: var(--color-surface); outline: none; }
.datum-zelle { font-size: 0.75rem; color: var(--color-text-muted); white-space: nowrap; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin-top: 0.75rem; }
.inventur { margin: 0 0 1rem; padding: 0.75rem; border: 1px solid var(--color-border); border-radius: var(--radius-md); }
.inventur-kopf { display: flex; justify-content: space-between; gap: 0.75rem; align-items: start; }
.inventur-kopf h3, .inventur-kopf .hint { margin: 0 0 0.25rem; }
.inventur-liste { display: grid; gap: 0.5rem; margin-top: 0.75rem; }
.inventur-zeile { display: grid; grid-template-columns: minmax(130px, 1fr) 100px minmax(150px, 1fr); gap: 0.5rem; align-items: end; }
.inventur-zeile label { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.78rem; color: var(--color-text-muted); }
.status { display: inline-block; padding: 0.1rem 0.4rem; border-radius: var(--radius-pill); font-size: 0.75rem; }
.status.genug { background: #e8f5e9; color: #2e7d32; }
.status.nachkaufen { background: #fdf0ed; color: var(--color-danger); }
.ok { color: #2e7d32; font-size: 0.85rem; }
@media (max-width: 600px) { .inventur-zeile { grid-template-columns: 1fr; } }
</style>
