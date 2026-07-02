<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

const eintraege = ref<{ id: string; jahr: number; sponsor: string; betrag: number | null; material: string | null; danke_gesendet: boolean }[]>([])
const form = ref({ jahr: new Date().getFullYear(), sponsor: '', betrag: null as number | null, material: '' })

const BEISPIEL_MAIL = `Betreff: Sponsoring Stöcklilager [JAHR]

Guten Tag

Wir organisieren jedes Jahr das Stöcklilager für Kinder und Jugendliche und suchen Partner/innen für Material- oder Geldspenden.

Könnten Sie uns unterstützen? Gerne senden wir Ihnen Infos und unsere Quittung.

Herzlichen Dank!
[Lagerleitung]
Stöcklilager`

async function laden() {
  const { data: org } = await supabase.from('organisation').select('id').eq('slug', 'stoeckli').single()
  if (!org) return
  const { data } = await supabase.from('org_sponsoring').select('*').eq('organisation_id', org.id).order('jahr', { ascending: false })
  eintraege.value = data ?? []
}

onMounted(laden)

async function hinzufuegen() {
  const { data: org } = await supabase.from('organisation').select('id').eq('slug', 'stoeckli').single()
  if (!org) return
  await supabase.from('org_sponsoring').insert({
    organisation_id: org.id,
    jahr: form.value.jahr,
    sponsor: form.value.sponsor,
    betrag: form.value.betrag,
    material: form.value.material || null,
  })
  form.value.sponsor = ''
  await laden()
}

async function dankeToggle(id: string, wert: boolean) {
  await supabase.from('org_sponsoring').update({ danke_gesendet: wert }).eq('id', id)
  await laden()
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <h3>Beispiel-Mail</h3>
    <pre class="mail">{{ BEISPIEL_MAIL }}</pre>

    <h3>Sponsoring-Liste (mehrjährig)</h3>
    <form class="inline-form" @submit.prevent="hinzufuegen">
      <input v-model.number="form.jahr" type="number" />
      <input v-model="form.sponsor" placeholder="Sponsor" required />
      <input v-model.number="form.betrag" type="number" placeholder="CHF" />
      <input v-model="form.material" placeholder="Material" />
      <button type="submit">+ Eintrag</button>
    </form>
    <table class="liste">
      <thead><tr><th>Jahr</th><th>Sponsor</th><th>Betrag</th><th>Material</th><th>Danke</th></tr></thead>
      <tbody>
        <tr v-for="e in eintraege" :key="e.id">
          <td>{{ e.jahr }}</td>
          <td>{{ e.sponsor }}</td>
          <td>{{ e.betrag ?? '–' }}</td>
          <td>{{ e.material ?? '–' }}</td>
          <td><input type="checkbox" :checked="e.danke_gesendet" @change="dankeToggle(e.id, ($event.target as HTMLInputElement).checked)" /></td>
        </tr>
      </tbody>
    </table>
    <p class="hint">Todo: Dankeskarte mit Lagerfoto nach dem Lager verschicken.</p>
  </AemtliShell>
</template>

<style scoped>
.mail { background: var(--color-surface-muted); padding: 0.75rem; border-radius: var(--radius-md); font-size: 0.82rem; white-space: pre-wrap; }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 0.5rem 0; }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; margin-top: 0.5rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); text-align: left; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin-top: 0.75rem; }
</style>
