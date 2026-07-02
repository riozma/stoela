<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../supabaseClient'
import { CODE_LABELS, formatProgrammTag, type BlockCode } from '../../lib/programmUtils'
import type { MaterialMitZuordnung, NamensZuordnung, ProgrammabschnittMitZuordnung } from '../../lib/nameMatching'

interface AbschnittZeile {
  zeit: string
  programm: string
  verantwortlich: string
}

interface MaterialZeile {
  name: string
  wer: string
}

const props = defineProps<{
  lagerId: string
  blockId?: string
  defaultTag?: string | null
}>()

const emit = defineEmits<{ saved: [] }>()

const route = useRoute()
const router = useRouter()
const istNeu = computed(() => !props.blockId || route.name === 'programm-neu')
const laden = ref(true)
const speichern = ref(false)
const fehler = ref('')
const loeschenLade = ref(false)

const form = ref({
  code: 'LP' as BlockCode,
  nummer: '',
  titel: '',
  tag: '',
  startZeit: '09:00',
  endZeit: '10:00',
  ort: '',
  verantwortlich: '',
  geschichte: '',
  sicherheitsueberlegungen: '',
  notizen: '',
})

const abschnitte = ref<AbschnittZeile[]>([])
const material = ref<MaterialZeile[]>([])

function tagAusRoute(): string {
  const q = route.query.tag
  if (typeof q === 'string' && q) return q
  return props.defaultTag ?? ''
}

function isoZuTimeInput(iso: string | null): string {
  if (!iso) return '09:00'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) {
    const m = iso.match(/(\d{1,2}):(\d{2})/)
    if (m) return `${m[1].padStart(2, '0')}:${m[2]}`
    return '09:00'
  }
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

function tagUndZeitZuIso(tag: string, zeit: string): string | null {
  if (!tag || !zeit) return null
  return `${tag}T${zeit}:00`
}

function abschnitteAusJson(rows: ProgrammabschnittMitZuordnung[]): AbschnittZeile[] {
  return rows.map((a) => ({
    zeit: a.zeit ?? '',
    programm: a.programm ?? '',
    verantwortlich: a.verantwortlich ?? '',
  }))
}

function materialAusJson(rows: MaterialMitZuordnung[]): MaterialZeile[] {
  return rows.map((m) => ({ name: m.name ?? '', wer: m.wer ?? '' }))
}

async function ladenBlock() {
  laden.value = true
  fehler.value = ''
  if (istNeu.value) {
    form.value.tag = tagAusRoute()
    abschnitte.value = [{ zeit: '', programm: '', verantwortlich: '' }]
    material.value = [{ name: '', wer: '' }]
    laden.value = false
    return
  }
  const { data, error } = await supabase
    .from('programmbloecke')
    .select('*')
    .eq('id', props.blockId!)
    .eq('lager_id', props.lagerId)
    .single()
  if (error || !data) {
    fehler.value = error?.message ?? 'Block nicht gefunden.'
    laden.value = false
    return
  }
  form.value = {
    code: data.code as BlockCode,
    nummer: data.nummer ?? '',
    titel: data.titel ?? '',
    tag: data.tag ?? '',
    startZeit: isoZuTimeInput(data.start_zeit),
    endZeit: isoZuTimeInput(data.end_zeit),
    ort: data.ort ?? '',
    verantwortlich: data.verantwortlich ?? '',
    geschichte: data.geschichte ?? '',
    sicherheitsueberlegungen: data.sicherheitsueberlegungen ?? '',
    notizen: data.notizen ?? '',
  }
  abschnitte.value = abschnitteAusJson((data.programmabschnitt as ProgrammabschnittMitZuordnung[]) ?? [])
  if (!abschnitte.value.length) abschnitte.value = [{ zeit: '', programm: '', verantwortlich: '' }]
  material.value = materialAusJson((data.material as MaterialMitZuordnung[]) ?? [])
  if (!material.value.length) material.value = [{ name: '', wer: '' }]
  laden.value = false
}

onMounted(ladenBlock)

function abschnittHinzufuegen() {
  abschnitte.value.push({ zeit: '', programm: '', verantwortlich: '' })
}

function materialHinzufuegen() {
  material.value.push({ name: '', wer: '' })
}

async function speichernBlock() {
  fehler.value = ''
  if (!form.value.titel.trim()) {
    fehler.value = 'Titel ist Pflicht.'
    return
  }
  speichern.value = true
  const payload = {
    lager_id: props.lagerId,
    code: form.value.code,
    nummer: form.value.nummer || null,
    titel: form.value.titel.trim(),
    tag: form.value.tag || null,
    start_zeit: tagUndZeitZuIso(form.value.tag, form.value.startZeit),
    end_zeit: tagUndZeitZuIso(form.value.tag, form.value.endZeit),
    ort: form.value.ort || null,
    verantwortlich: form.value.verantwortlich || null,
    geschichte: form.value.geschichte || null,
    sicherheitsueberlegungen: form.value.sicherheitsueberlegungen || null,
    notizen: form.value.notizen || null,
    programmabschnitt: abschnitte.value
      .filter((a) => a.programm.trim())
      .map((a) => ({ zeit: a.zeit || null, programm: a.programm, verantwortlich: a.verantwortlich || null })),
    material: material.value
      .filter((m) => m.name.trim())
      .map((m) => ({ name: m.name, wer: m.wer || null })),
    quelle: 'manuell' as const,
  }

  if (istNeu.value) {
    const { data, error } = await supabase.from('programmbloecke').insert(payload).select('id').single()
    speichern.value = false
    if (error) { fehler.value = error.message; return }
    emit('saved')
    await router.push(`/lager/${props.lagerId}/programm/block/${data.id}`)
    return
  }

  const { error } = await supabase.from('programmbloecke').update(payload).eq('id', props.blockId!)
  speichern.value = false
  if (error) { fehler.value = error.message; return }
  emit('saved')
}

async function blockLoeschen() {
  if (istNeu.value || !props.blockId) return
  if (!confirm('Programmblock wirklich löschen?')) return
  loeschenLade.value = true
  const tag = form.value.tag
  await supabase.from('programmbloecke').delete().eq('id', props.blockId)
  loeschenLade.value = false
  emit('saved')
  if (tag) await router.push(`/lager/${props.lagerId}/programm/tag/${tag}`)
  else await router.push(`/lager/${props.lagerId}/programm`)
}

function zurueck() {
  if (form.value.tag) router.push(`/lager/${props.lagerId}/programm/tag/${form.value.tag}`)
  else router.push(`/lager/${props.lagerId}/programm`)
}
</script>

<template>
  <div class="block-edit">
    <button type="button" class="secondary klein zurueck-btn" @click="zurueck">← Zurück</button>

    <h3>{{ istNeu ? 'Neues Programm' : 'Programm bearbeiten' }}</h3>
    <p v-if="form.tag" class="hint">{{ formatProgrammTag(form.tag) }}</p>

    <p v-if="laden">Lade...</p>
    <template v-else>
      <p v-if="fehler" class="error">{{ fehler }}</p>

      <form class="edit-form" @submit.prevent="speichernBlock">
        <label>Typ
          <select v-model="form.code">
            <option v-for="(label, code) in CODE_LABELS" :key="code" :value="code">{{ code }} – {{ label }}</option>
          </select>
        </label>
        <label>Nummer <input v-model="form.nummer" placeholder="z.B. 1.2" /></label>
        <label class="full">Titel <input v-model="form.titel" required /></label>
        <label>Tag <input v-model="form.tag" type="date" required /></label>
        <label>Start <input v-model="form.startZeit" type="time" required /></label>
        <label>Ende <input v-model="form.endZeit" type="time" required /></label>
        <label>Ort <input v-model="form.ort" /></label>
        <label class="full">Verantwortlich <input v-model="form.verantwortlich" /></label>
        <label class="full">Geschichte <textarea v-model="form.geschichte" rows="3" /></label>
        <label class="full">Sicherheitsüberlegungen <textarea v-model="form.sicherheitsueberlegungen" rows="3" /></label>
        <label class="full">Notizen <textarea v-model="form.notizen" rows="2" /></label>

        <div class="full abschnitt-block">
          <strong>Programmabschnitte</strong>
          <div v-for="(a, i) in abschnitte" :key="'a-' + i" class="zeile-grid">
            <input v-model="a.zeit" placeholder="Zeit" />
            <input v-model="a.programm" placeholder="Programm" />
            <input v-model="a.verantwortlich" placeholder="Verantwortlich" />
            <button type="button" class="secondary klein" @click="abschnitte.splice(i, 1)">×</button>
          </div>
          <button type="button" class="secondary klein" @click="abschnittHinzufuegen">+ Abschnitt</button>
        </div>

        <div class="full abschnitt-block">
          <strong>Material</strong>
          <div v-for="(m, i) in material" :key="'m-' + i" class="zeile-grid material-grid">
            <input v-model="m.name" placeholder="Material" />
            <input v-model="m.wer" placeholder="Wer bringt mit" />
            <button type="button" class="secondary klein" @click="material.splice(i, 1)">×</button>
          </div>
          <button type="button" class="secondary klein" @click="materialHinzufuegen">+ Material</button>
        </div>

        <div class="form-aktionen full">
          <button type="submit" :disabled="speichern">{{ speichern ? 'Speichere...' : 'Speichern' }}</button>
          <button v-if="!istNeu" type="button" class="secondary" :disabled="loeschenLade" @click="blockLoeschen">
            Löschen
          </button>
        </div>
      </form>
    </template>
  </div>
</template>

<style scoped>
.block-edit { margin-bottom: 2rem; }
.zurueck-btn { margin-bottom: 0.75rem; }
.block-edit h3 { margin: 0 0 0.25rem; }
.edit-form { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 0.75rem; margin-top: 1rem; }
.edit-form label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.82rem; color: var(--color-text-muted); }
.edit-form .full { grid-column: 1 / -1; }
.abschnitt-block { padding: 0.75rem; background: var(--color-surface-muted); border-radius: var(--radius-md); }
.zeile-grid { display: grid; grid-template-columns: 5rem 1fr 1fr auto; gap: 0.4rem; margin: 0.4rem 0; align-items: center; }
.material-grid { grid-template-columns: 1fr 1fr auto; }
.form-aktionen { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 0.5rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.error { color: var(--color-danger); }
button.klein { font-size: 0.75rem; padding: 0.25rem 0.55rem; }
</style>
