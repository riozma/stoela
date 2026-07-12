<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

const eintraege = ref<{ id: string; jahr: number; sponsor: string; betrag: number | null; material: string | null; danke_gesendet: boolean }[]>([])
const form = ref({ jahr: new Date().getFullYear(), sponsor: '', betrag: null as number | null, material: '' })

const STANDARD_MAIL = `Betreff: Sponsoring Stöcklilager [JAHR]

Guten Tag

Wir organisieren jedes Jahr das Stöcklilager für Kinder und Jugendliche und suchen Partner/innen für Material- oder Geldspenden.

Könnten Sie uns unterstützen? Gerne senden wir Ihnen Infos und unsere Quittung.

Herzlichen Dank!
[Lagerleitung]
Stöcklilager`

const orgId = ref<string | null>(null)
const beispielMail = ref('')
const mailBearbeiten = ref(false)
const mailSpeichern = ref(false)

async function ladeOrgId() {
  const { data } = await supabase
    .from('lager')
    .select('organisation_id')
    .eq('id', props.lagerId)
    .single()
  return data?.organisation_id ?? null
}

async function laden() {
  orgId.value = await ladeOrgId()
  if (!orgId.value) return
  const [{ data }, { data: org }] = await Promise.all([
    supabase.from('org_sponsoring').select('*').eq('organisation_id', orgId.value).order('jahr', { ascending: false }),
    supabase.from('organisation').select('sponsoring_mail_vorlage').eq('id', orgId.value).single(),
  ])
  eintraege.value = data ?? []
  beispielMail.value = org?.sponsoring_mail_vorlage ?? STANDARD_MAIL
}

onMounted(laden)

async function mailSpeichernHandler() {
  if (!orgId.value) return
  mailSpeichern.value = true
  await supabase.from('organisation').update({ sponsoring_mail_vorlage: beispielMail.value }).eq('id', orgId.value)
  mailSpeichern.value = false
  mailBearbeiten.value = false
}

async function hinzufuegen() {
  const orgId = await ladeOrgId()
  if (!orgId) return
  await supabase.from('org_sponsoring').insert({
    organisation_id: orgId,
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
    <pre v-if="!mailBearbeiten" class="mail">{{ beispielMail }}</pre>
    <textarea v-else v-model="beispielMail" rows="10" class="mail-edit"></textarea>
    <div class="inline-aktionen">
      <button v-if="!mailBearbeiten" type="button" class="secondary klein" @click="mailBearbeiten = true">Bearbeiten</button>
      <template v-else>
        <button type="button" class="klein" :disabled="mailSpeichern" @click="mailSpeichernHandler">{{ mailSpeichern ? 'Speichere…' : 'Speichern' }}</button>
        <button type="button" class="secondary klein" @click="mailBearbeiten = false">Abbrechen</button>
      </template>
    </div>

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
.mail-edit { width: 100%; max-width: 480px; font-size: 0.82rem; font-family: inherit; }
.inline-aktionen { display: flex; gap: 0.5rem; margin: 0.5rem 0 1rem; }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 0.5rem 0; }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; margin-top: 0.5rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); text-align: left; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin-top: 0.75rem; }
</style>
