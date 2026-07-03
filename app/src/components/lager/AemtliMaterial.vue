<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

interface Bestellung {
  id: string
  artikel: string
  menge: string | null
  kategorie: string
  notiz: string | null
}

const KATEGORIEN: { wert: string; label: string }[] = [
  { wert: 'zu_bestellen', label: 'Zu bestellen' },
  { wert: 'bestellt', label: 'Bestellt' },
  { wert: 'geliefert', label: 'Geliefert' },
  { wert: 'zurueckgesendet', label: 'Zurückgesendet' },
]

const items = ref<Bestellung[]>([])
const form = ref({ artikel: '', menge: '', notiz: '' })

function labelFor(kategorie: string) {
  return KATEGORIEN.find((k) => k.wert === kategorie)?.label ?? kategorie
}

const offeneBestellungen = computed(() => items.value.filter((i) => i.kategorie === 'zu_bestellen').length)

async function laden() {
  const { data } = await supabase
    .from('material_bestellungen')
    .select('id, artikel, menge, kategorie, notiz')
    .eq('lager_id', props.lagerId)
    .order('created_at')
  items.value = data ?? []
}

onMounted(laden)

async function hinzufuegen() {
  if (!form.value.artikel.trim()) return
  await supabase.from('material_bestellungen').insert({
    lager_id: props.lagerId,
    artikel: form.value.artikel,
    menge: form.value.menge || null,
    notiz: form.value.notiz || null,
  })
  form.value = { artikel: '', menge: '', notiz: '' }
  await laden()
}

async function kategorieAendern(id: string, kategorie: string) {
  await supabase.from('material_bestellungen').update({ kategorie }).eq('id', id)
  await laden()
}

async function loeschen(id: string) {
  if (!confirm('Eintrag wirklich löschen?')) return
  await supabase.from('material_bestellungen').delete().eq('id', id)
  await laden()
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <p v-if="offeneBestellungen" class="warn-hinweis">
      ⚠ {{ offeneBestellungen }} Artikel noch «zu bestellen»
    </p>

    <h3>Material / TJ+S-Bestellung</h3>
    <form class="inline-form" @submit.prevent="hinzufuegen">
      <input v-model="form.artikel" placeholder="Material (z.B. Seile, Zelte)" required />
      <input v-model="form.menge" placeholder="Menge" style="width:6rem" />
      <input v-model="form.notiz" placeholder="Notiz" style="flex:1" />
      <button type="submit">+ Artikel</button>
    </form>

    <table class="liste">
      <thead>
        <tr>
          <th>Artikel</th>
          <th>Menge</th>
          <th>Status</th>
          <th>Notiz</th>
          <th></th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="i in items" :key="i.id">
          <td>{{ i.artikel }}</td>
          <td>{{ i.menge ?? '–' }}</td>
          <td>
            <select :value="i.kategorie" @change="kategorieAendern(i.id, ($event.target as HTMLSelectElement).value)">
              <option v-for="k in KATEGORIEN" :key="k.wert" :value="k.wert">{{ k.label }}</option>
            </select>
          </td>
          <td>{{ i.notiz ?? '–' }}</td>
          <td>
            <button class="secondary klein loeschen-btn" @click="loeschen(i.id)" title="Löschen">✕</button>
          </td>
        </tr>
      </tbody>
    </table>
    <p v-if="!items.length" class="hint">Noch keine Materialliste erfasst.</p>
    <p class="hint">Deckt TJ+S-Bestellung, Lieferkontrolle und Rückversand nach Lager ab.</p>
  </AemtliShell>
</template>

<style scoped>
h3 { margin: 0 0 0.5rem; font-size: 0.95rem; }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 0.5rem 0 1rem; }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); text-align: left; vertical-align: middle; }
.liste th { font-size: 0.75rem; color: var(--color-text-muted); text-transform: uppercase; }
.warn-hinweis {
  background: #fdf6f4; border: 1px solid var(--color-danger); border-radius: var(--radius-md);
  padding: 0.5rem 0.85rem; font-size: 0.88rem; margin-bottom: 0.75rem;
}
.loeschen-btn { color: var(--color-danger); }
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin-top: 0.5rem; }
</style>
