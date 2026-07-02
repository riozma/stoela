<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

const items = ref<{ id: string; name: string; bestand: number; min_bestand: number; einheit: string | null; notiz: string | null }[]>([])
const form = ref({ name: '', bestand: 0, min_bestand: 1, einheit: 'Stk' })

const niedrig = computed(() => items.value.filter((i) => i.bestand <= i.min_bestand))

async function laden() {
  const { data: org } = await supabase.from('organisation').select('id').eq('slug', 'stoeckli').single()
  if (!org) return
  const { data } = await supabase.from('org_bastel_inventar').select('*').eq('organisation_id', org.id).order('name')
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
    einheit: form.value.einheit,
  })
  form.value = { name: '', bestand: 0, min_bestand: 1, einheit: 'Stk' }
  await laden()
}

async function bestandAendern(id: string, delta: number) {
  const item = items.value.find((i) => i.id === id)
  if (!item) return
  await supabase.from('org_bastel_inventar').update({ bestand: Math.max(0, item.bestand + delta), updated_at: new Date().toISOString() }).eq('id', id)
  await laden()
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <p v-if="niedrig.length" class="warn">{{ niedrig.length }} Artikel unter Mindestbestand!</p>
    <form class="inline-form" @submit.prevent="hinzufuegen">
      <input v-model="form.name" placeholder="Material" required />
      <input v-model.number="form.bestand" type="number" min="0" />
      <input v-model.number="form.min_bestand" type="number" min="0" placeholder="Min" />
      <button type="submit">+ Artikel</button>
    </form>
    <table class="liste">
      <thead><tr><th>Material</th><th>Bestand</th><th>Min</th><th></th></tr></thead>
      <tbody>
        <tr v-for="i in items" :key="i.id" :class="{ warn: i.bestand <= i.min_bestand }">
          <td>{{ i.name }}</td>
          <td>{{ i.bestand }} {{ i.einheit }}</td>
          <td>{{ i.min_bestand }}</td>
          <td>
            <button class="secondary klein" @click="bestandAendern(i.id, -1)">−</button>
            <button class="secondary klein" @click="bestandAendern(i.id, 1)">+</button>
          </td>
        </tr>
      </tbody>
    </table>
    <p class="hint">Mehrjahres-Inventar – wächst mit dem Verein.</p>
  </AemtliShell>
</template>

<style scoped>
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 0.5rem 0; }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); }
tr.warn, .warn { background: #fdf6f4; color: var(--color-danger); padding: 0.4rem 0.6rem; border-radius: var(--radius-sm); }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.45rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
