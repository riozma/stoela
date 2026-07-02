<script setup lang="ts">
import { computed } from 'vue'

interface Block {
  id: string
  code: string
  nummer: string | null
  titel: string
  tag: string | null
  start_zeit: string | null
  end_zeit: string | null
  verantwortlich: string | null
}

interface Lager {
  name: string
  ort: string | null
  start_datum: string | null
  end_datum: string | null
  status: string
}

const props = defineProps<{
  lager: Lager
  bloecke: Block[]
  userName: string
  istAnwesend: boolean
  bearbeiten: boolean
}>()

const emit = defineEmits<{
  tab: [tab: string]
  hoeck: []
  block: [id: string]
}>()

const jetzt = computed(() => new Date())

function formatDatum(d: string) {
  return new Intl.DateTimeFormat('de-CH', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).format(
    new Date(d + 'T00:00:00'),
  )
}

function formatZeitraum() {
  if (props.lager.start_datum && props.lager.end_datum) {
    return `${formatDatum(props.lager.start_datum)} – ${formatDatum(props.lager.end_datum)}`
  }
  if (props.lager.start_datum) return `Ab ${formatDatum(props.lager.start_datum)}`
  return ''
}

const aktuellerBlock = computed(() => {
  const now = jetzt.value.getTime()
  return props.bloecke.find((b) => {
    if (!b.start_zeit || !b.end_zeit) return false
    const start = new Date(b.start_zeit).getTime()
    const end = new Date(b.end_zeit).getTime()
    return now >= start && now <= end
  }) ?? null
})

const morgen = computed(() => {
  const d = new Date()
  d.setDate(d.getDate() + 1)
  return d.toISOString().slice(0, 10)
})

const morgenBloecke = computed(() =>
  props.bloecke.filter((b) => b.tag === morgen.value),
)

const mussHoeckVorbereiten = computed(() => {
  const name = props.userName.toLowerCase()
  if (!name) return false
  return morgenBloecke.value.some((b) => (b.verantwortlich ?? '').toLowerCase().includes(name))
})

const istHoeckZeit = computed(() => {
  if (!props.istAnwesend) return false
  const h = jetzt.value.getHours()
  return h >= 8 && h < 10
})

const lagerLaufend = computed(() => {
  if (props.lager.status !== 'laufend' && props.lager.status !== 'anmeldung_offen') return false
  const heute = jetzt.value.toISOString().slice(0, 10)
  if (props.lager.start_datum && heute < props.lager.start_datum) return false
  if (props.lager.end_datum && heute > props.lager.end_datum) return false
  return true
})

const aktionen = computed(() => {
  const list: { typ: string; titel: string; text: string; action: () => void }[] = []

  if (aktuellerBlock.value) {
    list.push({
      typ: 'jetzt',
      titel: 'Gerade im Programm',
      text: `${aktuellerBlock.value.code} ${aktuellerBlock.value.titel}`,
      action: () => emit('block', aktuellerBlock.value!.id),
    })
  }

  if (lagerLaufend.value && istHoeckZeit.value) {
    list.push({
      typ: 'hoeck',
      titel: 'Höck-Zeit (8–10 Uhr)',
      text: 'Nächsten Tag besprechen',
      action: () => emit('hoeck'),
    })
  }

  if (mussHoeckVorbereiten.value) {
    list.push({
      typ: 'vorbereiten',
      titel: 'Höck vorbereiten',
      text: `Du bist morgen (${formatDatum(morgen.value)}) verantwortlich`,
      action: () => emit('hoeck'),
    })
  }

  if (!list.length) {
    list.push({
      typ: 'ruhe',
      titel: 'Alles ruhig',
      text: 'Keine dringenden Aktionen gerade.',
      action: () => emit('tab', 'programm'),
    })
  }

  return list
})
</script>

<template>
  <section class="dashboard">
    <header class="lager-kopf">
      <h1>{{ lager.name }}</h1>
      <p v-if="lager.ort" class="ort">📍 {{ lager.ort }}</p>
      <p v-if="formatZeitraum()" class="zeitraum">{{ formatZeitraum() }}</p>
    </header>

    <div class="aktionen">
      <button
        v-for="(a, i) in aktionen"
        :key="i"
        class="aktion-karte"
        :class="'aktion-' + a.typ"
        @click="a.action"
      >
        <strong>{{ a.titel }}</strong>
        <span>{{ a.text }}</span>
      </button>
    </div>

    <div v-if="bearbeiten" class="schnell-links">
      <button class="secondary" @click="emit('tab', 'programm')">Programm</button>
      <button class="secondary" @click="emit('tab', 'einkauf')">Einkaufsliste</button>
      <button class="secondary" @click="emit('tab', 'einstellungen')">Lager bearbeiten</button>
    </div>
  </section>
</template>

<style scoped>
.dashboard { margin-bottom: 1.5rem; }
.lager-kopf { margin-bottom: 1.5rem; }
.lager-kopf h1 { margin: 0 0 0.35rem; font-size: 1.6rem; }
.ort, .zeitraum { color: var(--color-text-muted); margin: 0.2rem 0; font-size: 0.95rem; }
.aktionen { display: flex; flex-direction: column; gap: 0.65rem; margin-bottom: 1.25rem; }
.aktion-karte {
  display: flex; flex-direction: column; align-items: flex-start; gap: 0.25rem;
  text-align: left; padding: 0.85rem 1.1rem; width: 100%;
  background: var(--color-surface); color: var(--color-text);
  border: 1px solid var(--color-border); border-radius: var(--radius-md);
}
.aktion-karte:hover { background: var(--color-surface-muted); }
.aktion-jetzt { border-left: 4px solid var(--color-accent); }
.aktion-hoeck { border-left: 4px solid #c98a3f; }
.aktion-vorbereiten { border-left: 4px solid #6b7fa8; }
.aktion-karte strong { font-size: 0.95rem; }
.aktion-karte span { font-size: 0.85rem; color: var(--color-text-muted); }
.schnell-links { display: flex; flex-wrap: wrap; gap: 0.5rem; }
</style>
