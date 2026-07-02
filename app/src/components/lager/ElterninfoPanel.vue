<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { downloadElterninfoPdf } from '../../lib/elterninfoPdf'

const props = defineProps<{
  lagerId: string
  lagerName: string
  jahr: number
  startDatum: string | null
  endDatum: string | null
  ort: string | null
}>()

const vorlage = ref<Record<string, unknown>>({})
const packliste = ref<string[]>([])
const felder = ref({
  lagerleiter_name: '',
  lagerleiter_adresse: '',
  lagerleiter_telefon: '',
  lagerleiter_email: '',
  elternabend_datum: '',
  elternabend_ort: '',
  kennenlernabend_datum: '',
  kennenlernabend_ort: '',
  diashow_datum: '',
  diashow_ort: '',
  lageradresse: '',
  lagertelefon: '',
  reise_besammlung: '',
  reise_abfahrt: '',
  reise_rueckkehr: '',
  telefon_zeiten: '',
  einzahlungsfrist: '',
  lagerbeitrag: 340,
  lagerbeitrag_geschwister: 280,
})

async function laden() {
  const [{ data: org }, { data: lagerCfg }] = await Promise.all([
    supabase.from('org_elterninfo_vorlage').select('felder, packliste').maybeSingle(),
    supabase.from('lager').select('elterninfo_config, telefon_zeiten').eq('id', props.lagerId).single(),
  ])
  vorlage.value = (org?.felder as Record<string, unknown>) ?? {}
  packliste.value = (org?.packliste as string[]) ?? []
  const cfg = (lagerCfg?.elterninfo_config as Record<string, unknown>) ?? {}
  felder.value = { ...felder.value, ...cfg }
  if (lagerCfg?.telefon_zeiten && !felder.value.telefon_zeiten) felder.value.telefon_zeiten = lagerCfg.telefon_zeiten
  if (vorlage.value.lagerbeitrag_tn) felder.value.lagerbeitrag = Number(vorlage.value.lagerbeitrag_tn)
  if (vorlage.value.lagerbeitrag_geschwister) felder.value.lagerbeitrag_geschwister = Number(vorlage.value.lagerbeitrag_geschwister)
}

onMounted(laden)

async function speichern() {
  await supabase.from('lager').update({ elterninfo_config: felder.value }).eq('id', props.lagerId)
}

const brief = computed(() => {
  const f = felder.value
  const v = vorlage.value
  return `${props.lagerName} ${props.jahr}
${props.ort ?? ''}

Liebe Eltern,

wir laden Sie herzlich ein zum Elternabend des ${props.lagerName}.

Elternabend: ${f.elternabend_datum || '___'} 
Ort: ${f.elternabend_ort || '___'}

Kennenlernabend Kinder: ${f.kennenlernabend_datum || '___'}
Ort: ${f.kennenlernabend_ort || '___'}

Diashow: ${f.diashow_datum || '___'}
Ort: ${f.diashow_ort || '___'}

Lagerleiter/in: ${f.lagerleiter_name || '___'}
${f.lagerleiter_telefon || ''} · ${f.lagerleiter_email || ''}

Reise:
Besammlung: ${f.reise_besammlung || '___'}
Abfahrt: ${f.reise_abfahrt || '___'}
Rückkehr: ${f.reise_rueckkehr || '___'}

Lageradresse: ${f.lageradresse || props.ort || '___'}
Lagertelefon: ${f.lagertelefon || '___'}

Lagerbeitrag: CHF ${f.lagerbeitrag}.— (Geschwister CHF ${f.lagerbeitrag_geschwister}.—)
Einzahlung bis: ${f.einzahlungsfrist || '___'}
IBAN: ${v.pfarrei_iban ?? '___'}

Kulturlegi: ${v.kulturlegi_link ?? ''}

Packliste (Auszug):
${packliste.value.map((p) => `• ${p}`).join('\n')}

${v.besuche_hinweis ?? ''}
${v.dessertaktien_hinweis ?? ''}

Herzlichen Dank!
Das ${props.lagerName}-Team`
})

function downloadBrief() {
  downloadElterninfoPdf({
    lagerName: props.lagerName,
    jahr: props.jahr,
    ort: props.ort,
    felder: felder.value as Record<string, string | number>,
    vorlage: vorlage.value,
    packliste: packliste.value,
  })
}
</script>

<template>
  <section class="elterninfo">
    <header class="kopf">
      <div>
        <h3>Elterninfo generieren</h3>
        <p class="hint">Basierend auf der Vereins-Vorlage (wie Kinder_Elterninfos PDF). Felder anpassen, Vorschau, als PDF drucken.</p>
      </div>
      <button type="button" @click="downloadBrief">PDF drucken</button>
    </header>

    <form class="felder-grid" @submit.prevent="speichern">
      <h4>Lagerleitung</h4>
      <label>Name <input v-model="felder.lagerleiter_name" /></label>
      <label>Adresse <input v-model="felder.lagerleiter_adresse" /></label>
      <label>Telefon <input v-model="felder.lagerleiter_telefon" /></label>
      <label>E-Mail <input v-model="felder.lagerleiter_email" type="email" /></label>

      <h4>Termine</h4>
      <label>Elternabend <input v-model="felder.elternabend_datum" placeholder="Mi 26.6.2024, 19:00" /></label>
      <label>Ort Elternabend <input v-model="felder.elternabend_ort" /></label>
      <label>Kennenlernabend <input v-model="felder.kennenlernabend_datum" /></label>
      <label>Ort Kennenlernabend <input v-model="felder.kennenlernabend_ort" /></label>
      <label>Diashow <input v-model="felder.diashow_datum" /></label>
      <label>Ort Diashow <input v-model="felder.diashow_ort" /></label>

      <h4>Reise & Lager</h4>
      <label>Besammlung <input v-model="felder.reise_besammlung" /></label>
      <label>Abfahrt <input v-model="felder.reise_abfahrt" /></label>
      <label>Rückkehr <input v-model="felder.reise_rueckkehr" /></label>
      <label>Lageradresse <input v-model="felder.lageradresse" /></label>
      <label>Lagertelefon <input v-model="felder.lagertelefon" /></label>

      <h4>Beiträge</h4>
      <label>Beitrag TN <input v-model.number="felder.lagerbeitrag" type="number" /></label>
      <label>Beitrag Geschwister <input v-model.number="felder.lagerbeitrag_geschwister" type="number" /></label>
      <label>Einzahlungsfrist <input v-model="felder.einzahlungsfrist" type="date" /></label>

      <button type="submit">Felder speichern</button>
    </form>

    <h4>Vorschau</h4>
    <pre class="vorschau">{{ brief }}</pre>
  </section>
</template>

<style scoped>
.kopf { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 0.75rem; margin-bottom: 1rem; }
.kopf h3 { margin: 0 0 0.25rem; }
.felder-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 0.65rem; margin-bottom: 1.5rem; }
.felder-grid h4 { grid-column: 1 / -1; margin: 0.75rem 0 0.15rem; font-size: 0.9rem; color: var(--color-text-muted); }
.felder-grid label { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.82rem; color: var(--color-text-muted); }
.vorschau {
  background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md);
  padding: 1rem; white-space: pre-wrap; font-size: 0.85rem; line-height: 1.45; max-height: 480px; overflow: auto;
}
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
