<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'

interface Mahlzeit {
  id: string
  tag: string
  mahlzeit: string
  gericht: string
  notizen: string
}

const MAHLZEIT_TYPEN = [
  { key: 'fruehstueck', label: 'Frühstück' },
  { key: 'mittag', label: 'Mittag' },
  { key: 'znueni_zvieri', label: 'Znüni/Zvieri' },
  { key: 'abend', label: 'Abend' },
  { key: 'sonstiges', label: 'Sonstiges' },
] as const

const props = defineProps<{
  lagerId: string
  startDatum: string | null
  endDatum: string | null
  isLeitung: boolean
}>()

const mahlzeiten = ref<Mahlzeit[]>([])
const laden = ref(true)
const speichern = ref<Record<string, boolean>>({})

const tage = computed(() => {
  if (!props.startDatum || !props.endDatum) return []
  const list: string[] = []
  const cur = new Date(props.startDatum + 'T00:00:00')
  const end = new Date(props.endDatum + 'T00:00:00')
  while (cur <= end) {
    list.push(cur.toISOString().slice(0, 10))
    cur.setDate(cur.getDate() + 1)
  }
  return list
})

const mahlzeitMap = computed(() => {
  const map = new Map<string, Mahlzeit>()
  for (const m of mahlzeiten.value) {
    map.set(`${m.tag}-${m.mahlzeit}`, m)
  }
  return map
})

function formatTag(tag: string) {
  return new Intl.DateTimeFormat('de-CH', { weekday: 'short', day: 'numeric', month: 'numeric' }).format(new Date(tag + 'T00:00:00'))
}

function getMahlzeit(tag: string, typ: string): Mahlzeit | undefined {
  return mahlzeitMap.value.get(`${tag}-${typ}`)
}

function getGericht(tag: string, typ: string): string {
  return getMahlzeit(tag, typ)?.gericht ?? ''
}

function getNotizen(tag: string, typ: string): string {
  return getMahlzeit(tag, typ)?.notizen ?? ''
}

async function ladeMahlzeiten() {
  laden.value = true
  const { data } = await supabase
    .from('mahlzeiten')
    .select('*')
    .eq('lager_id', props.lagerId)
    .order('tag')
    .order('mahlzeit')
  mahlzeiten.value = data ?? []
  laden.value = false
}

onMounted(ladeMahlzeiten)

async function speichereMahlzeit(tag: string, typ: string, gericht: string, notizen: string) {
  const key = `${tag}-${typ}`
  speichern.value[key] = true
  const existing = getMahlzeit(tag, typ)
  if (existing) {
    await supabase
      .from('mahlzeiten')
      .update({ gericht, notizen })
      .eq('id', existing.id)
    existing.gericht = gericht
    existing.notizen = notizen
  } else {
    const { data } = await supabase
      .from('mahlzeiten')
      .insert({ lager_id: props.lagerId, tag, mahlzeit: typ, gericht, notizen })
      .select()
      .single()
    if (data) {
      mahlzeiten.value.push(data as Mahlzeit)
    }
  }
  speichern.value[key] = false
}

function handleBlur(tag: string, typ: string, e: Event) {
  const target = e.target as HTMLInputElement
  const notizenInput = (target.closest('.mahlzeit-zelle')?.querySelector('.notizen-input') as HTMLInputElement)
  speichereMahlzeit(tag, typ, target.value, notizenInput?.value ?? '')
}

function handleNotizenBlur(tag: string, typ: string, e: Event) {
  const target = e.target as HTMLInputElement
  const gerichtInput = (target.closest('.mahlzeit-zelle')?.querySelector('.gericht-input') as HTMLInputElement)
  speichereMahlzeit(tag, typ, gerichtInput?.value ?? '', target.value)
}
</script>

<template>
  <section class="kueche-mahlzeiten">
    <h3>Mahlzeiten-Planung</h3>
    <p class="hint">Wochenraster für die Küche – erfasse was es zu essen gibt.</p>

    <div v-if="laden" class="hint">Lade Mahlzeiten...</div>
    <div v-else-if="!tage.length" class="hint">Bitte zuerst Start- und Enddatum in den Einstellungen setzen.</div>

    <div v-else class="mahlzeiten-raster">
      <div class="raster-header">
        <div class="zelle tag-label"></div>
        <div v-for="typ in MAHLZEIT_TYPEN" :key="typ.key" class="zelle typ-label">{{ typ.label }}</div>
      </div>
      <div v-for="tag in tage" :key="tag" class="raster-zeile">
        <div class="zelle tag-label">{{ formatTag(tag) }}</div>
        <div v-for="typ in MAHLZEIT_TYPEN" :key="`${tag}-${typ.key}`" class="zelle mahlzeit-zelle">
          <input
            class="gericht-input"
            :value="getGericht(tag, typ.key)"
            :placeholder="typ.label"
            @blur="handleBlur(tag, typ.key, $event)"
          />
          <input
            class="notizen-input"
            :value="getNotizen(tag, typ.key)"
            placeholder="Notiz"
            @blur="handleNotizenBlur(tag, typ.key, $event)"
          />
          <span v-if="speichern[`${tag}-${typ.key}`]" class="speichern-hinweis">✓</span>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.kueche-mahlzeiten { margin-bottom: 1.5rem; }
.kueche-mahlzeiten h3 { margin: 0 0 0.25rem; }
.mahlzeiten-raster {
  overflow-x: auto;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface);
  margin-top: 0.75rem;
}
.raster-header {
  display: flex;
  background: var(--color-surface-muted);
  border-bottom: 1px solid var(--color-border);
  font-weight: 700;
  font-size: 0.78rem;
}
.raster-zeile {
  display: flex;
  border-bottom: 1px solid var(--color-border);
}
.raster-zeile:last-child { border-bottom: none; }
.zelle {
  min-width: 120px;
  padding: 0.35rem 0.5rem;
  border-right: 1px solid var(--color-border);
  font-size: 0.82rem;
}
.zelle:last-child { border-right: none; }
.tag-label {
  min-width: 100px;
  display: flex;
  align-items: center;
  font-weight: 600;
  font-size: 0.78rem;
  color: var(--color-text-muted);
}
.mahlzeit-zelle {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  position: relative;
}
.gericht-input, .notizen-input {
  border: 1px solid transparent;
  background: transparent;
  padding: 0.15rem 0.3rem;
  font-size: 0.82rem;
  border-radius: 4px;
  width: 100%;
  box-sizing: border-box;
}
.gericht-input:focus, .notizen-input:focus {
  border-color: var(--color-accent);
  background: var(--color-surface);
  outline: none;
}
.gericht-input::placeholder, .notizen-input::placeholder { color: var(--color-text-muted); opacity: 0.5; }
.notizen-input { font-size: 0.72rem; color: var(--color-text-muted); }
.speichern-hinweis {
  position: absolute;
  right: 0.3rem;
  top: 0.3rem;
  font-size: 0.7rem;
  color: var(--color-accent);
}
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>