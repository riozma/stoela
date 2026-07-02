<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabaseClient'
import { ladeWetter, type TagesWetter } from '../lib/weather'

interface LagerInfo {
  id: string
  name: string
  ort: string | null
  start_datum: string | null
  end_datum: string | null
  ort_lat: number | null
  ort_lng: number | null
  status: string
}

const route = useRoute()
const lagerId = route.params.id as string

const lager = ref<LagerInfo | null>(null)
const wetter = ref<TagesWetter[]>([])
const ladefehler = ref('')
const wetterFehler = ref('')

function formatDatum(d: string) {
  return new Intl.DateTimeFormat('de-CH', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  }).format(new Date(d + 'T00:00:00'))
}

onMounted(async () => {
  const { data, error } = await supabase.rpc('get_lager_willkommen', { p_lager_id: lagerId })
  if (error || !data) {
    ladefehler.value = 'Diese Lagerseite ist nicht verfügbar.'
    return
  }
  lager.value = data as LagerInfo

  if (lager.value.ort_lat && lager.value.ort_lng && lager.value.start_datum && lager.value.end_datum) {
    try {
      wetter.value = await ladeWetter(
        lager.value.ort_lat,
        lager.value.ort_lng,
        lager.value.start_datum,
        lager.value.end_datum,
      )
    } catch {
      wetterFehler.value = 'Wettervorhersage konnte nicht geladen werden.'
    }
  }
})
</script>

<template>
  <main>
    <p v-if="ladefehler" class="error">{{ ladefehler }}</p>

    <template v-else-if="lager">
      <h1>Wir freuen uns auf euch!</h1>
      <p class="lager-name">{{ lager.name }}</p>

      <section class="info-karte">
        <h2>Wann &amp; wo</h2>
        <p v-if="lager.start_datum && lager.end_datum">
          {{ formatDatum(lager.start_datum) }} – {{ formatDatum(lager.end_datum) }}
        </p>
        <p v-else-if="lager.start_datum">Ab {{ formatDatum(lager.start_datum) }}</p>
        <p v-if="lager.ort" class="ort">📍 {{ lager.ort }}</p>
      </section>

      <section v-if="wetter.length" class="info-karte">
        <h2>Wetter</h2>
        <p v-if="wetterFehler" class="hint">{{ wetterFehler }}</p>
        <ul class="wetter-liste">
          <li v-for="w in wetter" :key="w.datum">
            <span class="wetter-tag">{{ formatDatum(w.datum) }}</span>
            <span>{{ w.beschreibung }}</span>
            <span class="wetter-temp">{{ w.tempMin }}° – {{ w.tempMax }}°</span>
          </li>
        </ul>
      </section>

      <p class="hint">
        Hier findest du die wichtigsten Infos fürs Lager. Das detaillierte Programm ist nur für das Leiterteam sichtbar.
      </p>
    </template>
  </main>
</template>

<style scoped>
main {
  max-width: 520px;
  margin: 3rem auto;
  padding: 0 1rem;
  text-align: center;
}
h1 {
  font-size: 2rem;
  margin-bottom: 0.25rem;
}
.lager-name {
  color: var(--color-text-muted);
  font-size: 1.1rem;
  margin-bottom: 2rem;
}
.info-karte {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: 1.25rem 1.5rem;
  margin-bottom: 1.25rem;
  text-align: left;
}
.info-karte h2 {
  margin: 0 0 0.75rem;
  font-size: 1rem;
  color: var(--color-text-muted);
}
.ort {
  margin-top: 0.5rem;
}
.wetter-liste {
  list-style: none;
  padding: 0;
  margin: 0;
}
.wetter-liste li {
  display: grid;
  grid-template-columns: 1fr 1fr auto;
  gap: 0.5rem;
  padding: 0.35rem 0;
  border-bottom: 1px solid var(--color-border);
  font-size: 0.9rem;
}
.wetter-liste li:last-child {
  border-bottom: none;
}
.wetter-tag {
  font-weight: 700;
}
.wetter-temp {
  color: var(--color-text-muted);
  font-variant-numeric: tabular-nums;
}
.hint {
  color: var(--color-text-muted);
  font-size: 0.85rem;
  margin-top: 2rem;
}
.error {
  color: var(--color-danger);
}
</style>
