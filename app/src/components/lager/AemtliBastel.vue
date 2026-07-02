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
}

const items = ref<Item[]>([])
const form = ref({ name: '', bestand: 0, min_bestand: 1, einheit: 'Stk', notiz: '' })

const niedrig = computed(() => items.value.filter((i) => i.bestand < i.min_bestand))

async function laden() {
  const { data: org } = await supabase.from('organisation').select('id').eq('slug', 'stoeckli').single()
  if (!org) return
  const { data } = await supabase
    .from('org_bastel_inventar')
    .select('id, name, bestand, min_bestand, einheit, notiz, updated_at')
    .eq('organisation_id', org.id)
    .order('name')
  items.value = data ?? []
}

onMounted(laden)

async function hinzufuegen() {
  const { data: org } = await supabase.from('organisation').select('id').eq('slug', 'stoeckli').single()
  if (!org) return
  await supabase.from('org_bastel_inventar').insert({
    organisation_id: org.id,
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
</style>
