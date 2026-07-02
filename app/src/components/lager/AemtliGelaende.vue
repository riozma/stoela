<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'
import LagerMap from './LagerMap.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string; lat?: number | null; lng?: number | null }>()

const wiesen = ref<{ id: string; name: string; lat: number | null; lng: number | null; bauer_name: string | null; bauer_telefon: string | null; status: string; notiz: string | null }[]>([])
const form = ref({ name: '', bauer_name: '', bauer_telefon: '', notiz: '' })

async function laden() {
  const { data } = await supabase.from('gelaendespielwiesen').select('*').eq('lager_id', props.lagerId)
  wiesen.value = data ?? []
}

onMounted(laden)

async function hinzufuegen() {
  await supabase.from('gelaendespielwiesen').insert({
    lager_id: props.lagerId,
    name: form.value.name,
    bauer_name: form.value.bauer_name || null,
    bauer_telefon: form.value.bauer_telefon || null,
    notiz: form.value.notiz || null,
    lat: props.lat ?? null,
    lng: props.lng ?? null,
  })
  form.value = { name: '', bauer_name: '', bauer_telefon: '', notiz: '' }
  await laden()
}

async function statusSetzen(id: string, status: string) {
  await supabase.from('gelaendespielwiesen').update({ status }).eq('id', id)
  await laden()
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <LagerMap v-if="lat && lng" :lat="lat" :lng="lng" ort="Lager / Umgebung" />
    <form class="inline-form" @submit.prevent="hinzufuegen">
      <input v-model="form.name" placeholder="Wiese / Ort" required />
      <input v-model="form.bauer_name" placeholder="Bauer/in" />
      <input v-model="form.bauer_telefon" placeholder="Telefon" />
      <input v-model="form.notiz" placeholder="Notiz" />
      <button type="submit">+ Wiese</button>
    </form>
    <table class="liste">
      <thead><tr><th>Wiese</th><th>Bauer/in</th><th>Kontakt</th><th>Status</th><th></th></tr></thead>
      <tbody>
        <tr v-for="w in wiesen" :key="w.id">
          <td>{{ w.name }}</td>
          <td>{{ w.bauer_name ?? '–' }}</td>
          <td>{{ w.bauer_telefon ?? '–' }}</td>
          <td>{{ w.status }}</td>
          <td>
            <button class="secondary klein" @click="statusSetzen(w.id, 'zusage')">Zusage</button>
            <button class="secondary klein" @click="statusSetzen(w.id, 'bedankt')">Bedankt</button>
          </td>
        </tr>
      </tbody>
    </table>
    <p class="hint">Am Schluss Flasche Wein als Dankeschön vorbeibringen.</p>
  </AemtliShell>
</template>

<style scoped>
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 0.75rem 0; }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.45rem; margin-right: 0.25rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
