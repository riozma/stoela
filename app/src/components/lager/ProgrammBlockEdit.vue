<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../../supabaseClient'
import { CODE_LABELS, formatProgrammTag, type BlockCode } from '../../lib/programmUtils'

interface BlockForm {
  code: BlockCode
  nummer: string
  titel: string
  tag: string
  startZeit: string
  endZeit: string
  ist_essen: boolean
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
const laden = ref(!istNeu.value)
const speichern = ref(false)
const fehler = ref('')
const loeschenLade = ref(false)

const form = ref<BlockForm>({
  code: 'LP',
  nummer: '',
  titel: '',
  tag: '',
  startZeit: '09:00',
  endZeit: '10:00',
  ist_essen: false,
})

function tagAusRoute(): string {
  const q = route.query.tag
  if (typeof q === 'string' && q) return q
  return props.defaultTag ?? ''
}

onMounted(async () => {
  if (tagAusRoute()) form.value.tag = tagAusRoute()

  if (props.blockId && !istNeu.value) {
    const { data } = await supabase
      .from('programmbloecke')
      .select('*')
      .eq('id', props.blockId)
      .single()
    if (data) {
      form.value = {
        code: data.code,
        nummer: data.nummer ?? '',
        titel: data.titel ?? '',
        tag: data.tag ?? '',
        startZeit: data.start_zeit ? data.start_zeit.slice(11, 16) : '09:00',
        endZeit: data.end_zeit ? data.end_zeit.slice(11, 16) : '10:00',
        ist_essen: data.ist_essen ?? false,
      }
    }
  }
  laden.value = false
})

function codeClass(code: BlockCode) {
  return `code-${code}`
}

function zurueck() {
  if (form.value.tag) {
    router.push(`/lager/${props.lagerId}/programm/tag/${form.value.tag}`)
  } else {
    router.push(`/lager/${props.lagerId}/programm`)
  }
}

async function speichernBlock() {
  fehler.value = ''
  speichern.value = true

  const tag = form.value.tag
  const startIso = tag ? `${tag}T${form.value.startZeit}:00` : null
  const endIso = tag ? `${tag}T${form.value.endZeit}:00` : null

  const payload = {
    code: form.value.code,
    nummer: form.value.nummer || null,
    titel: form.value.titel,
    tag: tag || null,
    start_zeit: startIso,
    end_zeit: endIso,
    ist_essen: form.value.ist_essen,
  }

  let err: any = null
  if (istNeu.value) {
    const { error } = await supabase.from('programmbloecke').insert({ ...payload, lager_id: props.lagerId })
    err = error
  } else if (props.blockId) {
    const { error } = await supabase.from('programmbloecke').update(payload).eq('id', props.blockId)
    err = error
  }

  speichern.value = false
  if (err) { fehler.value = err.message; return }
  emit('saved')
  zurueck()
}

async function loeschen() {
  if (!props.blockId || istNeu.value) return
  if (!window.confirm('Diesen Block wirklich löschen?')) return
  loeschenLade.value = true
  await supabase.from('programmbloecke').delete().eq('id', props.blockId)
  emit('saved')
  zurueck()
}

const CODE_OPTIONS: { value: BlockCode; label: string; color: string }[] = [
  { value: 'LP', label: 'LP – Lagerprogramm', color: 'var(--lp-color, #6b7fa8)' },
  { value: 'LS', label: 'LS – Lagersport', color: 'var(--ls-color, #6bb87f)' },
  { value: 'LA', label: 'LA – Lageraktivität', color: 'var(--la-color, #c98a3f)' },
  { value: 'ES', label: 'ES – Essen', color: 'var(--es-color, #8a7f68)' },
]
</script>

<template>
  <div class="block-edit">
    <div class="edit-kopf">
      <button type="button" class="secondary" @click="zurueck">← Zurück</button>
      <h3>{{ istNeu ? 'Neuer Programmblock' : 'Programmblock bearbeiten' }}</h3>
      <button v-if="!istNeu" type="button" class="secondary loeschen" :disabled="loeschenLade" @click="loeschen">
        {{ loeschenLade ? 'Lösche...' : 'Löschen' }}
      </button>
    </div>

    <p v-if="fehler" class="error">{{ fehler }}</p>

    <div v-if="laden" class="hint">Lade...</div>

    <form v-else class="block-form" @submit.prevent="speichernBlock">
      <div class="form-row">
        <label>Code / Art</label>
        <div class="code-options">
          <button
            v-for="opt in CODE_OPTIONS"
            :key="opt.value"
            type="button"
            class="code-btn"
            :class="{ aktiv: form.code === opt.value }"
            :style="{ '--code-color': opt.color }"
            @click="form.code = opt.value"
          >
            {{ opt.label }}
          </button>
        </div>
      </div>

      <div class="form-row">
        <label>Titel</label>
        <input v-model="form.titel" placeholder="z.B. Geländespiel" required />
      </div>

      <div class="form-row">
        <label>Nummer (optional)</label>
        <input v-model="form.nummer" placeholder="z.B. 1.2" />
      </div>

      <div class="form-row">
        <label>Tag</label>
        <input v-model="form.tag" type="date" required />
      </div>

      <div class="form-row form-row-double">
        <label>
          Start
          <input v-model="form.startZeit" type="time" required />
        </label>
        <label>
          Ende
          <input v-model="form.endZeit" type="time" required />
        </label>
      </div>

      <div class="form-row">
        <label class="checkbox-label">
          <input v-model="form.ist_essen" type="checkbox" />
          Dieser Block ist eine Mahlzeit (🍽️)
        </label>
      </div>

      <div class="form-actions">
        <button type="submit" :disabled="speichern">
          {{ speichern ? 'Speichere...' : 'Speichern' }}
        </button>
      </div>
    </form>
  </div>
</template>

<style scoped>
.edit-kopf { display: flex; flex-wrap: wrap; align-items: center; gap: 0.75rem; margin-bottom: 1.25rem; }
.edit-kopf h3 { margin: 0; flex: 1; }
.block-form { max-width: 500px; }
.form-row { margin-bottom: 1rem; }
.form-row label { display: block; font-size: 0.85rem; font-weight: 600; color: var(--color-text-muted); margin-bottom: 0.3rem; }
.form-row input[type="text"],
.form-row input[type="date"],
.form-row input[type="time"] {
  width: 100%; padding: 0.5rem 0.7rem; border: 1px solid var(--color-border);
  border-radius: var(--radius-md); font-size: 0.9rem; background: var(--color-surface); color: var(--color-text);
  box-sizing: border-box;
}
.form-row-double { display: flex; gap: 1rem; }
.form-row-double label { flex: 1; }
.code-options { display: flex; flex-wrap: wrap; gap: 0.4rem; }
.code-btn {
  padding: 0.4rem 0.7rem; font-size: 0.78rem; border: 2px solid var(--code-color);
  border-radius: var(--radius-pill); background: transparent; color: var(--color-text);
  cursor: pointer; opacity: 0.6;
}
.code-btn.aktiv { opacity: 1; background: var(--code-color); color: #fdfbf3; }
.checkbox-label { display: flex; align-items: center; gap: 0.5rem; font-weight: 400; font-size: 0.9rem; cursor: pointer; }
.form-actions { margin-top: 1.25rem; }
.loeschen { color: var(--color-danger); border-color: var(--color-danger); }
.error { color: var(--color-danger); font-size: 0.88rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>