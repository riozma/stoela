<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
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
  foto_link: string | null
  instagram_url: string | null
  diashow_datum: string | null
  diashow_zeit: string | null
  diashow_ort: string | null
}

const route = useRoute()
const router = useRouter()
const { session } = useAuth()
const lagerId = route.params.id as string

const lager = ref<LagerInfo | null>(null)
const wetter = ref<TagesWetter[]>([])
const ladefehler = ref('')
const wetterFehler = ref('')
const pruefeTeamZugriff = ref(true)

function formatDatum(d: string) {
  return new Intl.DateTimeFormat('de-CH', {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  }).format(new Date(d + 'T00:00:00'))
}

type Phase = 'bevorstehend' | 'laufend' | 'vergangen'

const phase = computed<Phase>(() => {
  if (!lager.value) return 'bevorstehend'
  const heute = new Date().toISOString().slice(0, 10)
  if (lager.value.end_datum && heute > lager.value.end_datum) return 'vergangen'
  if (lager.value.start_datum && heute >= lager.value.start_datum) return 'laufend'
  return 'bevorstehend'
})

onMounted(async () => {
  // Wer bereits im Leiterteam dieses Lagers ist (egal ob Vereinsmitglied
  // oder explizit im Lager bestätigt), soll nie auf der Gastansicht
  // landen -- auch nicht bei einem vergangenen Lager -- sondern direkt
  // auf der Leiter-Seite.
  if (session.value) {
    const [{ data: darfRein }, { data: orgMitglied }] = await Promise.all([
      supabase.rpc('can_access_lager', { p_lager_id: lagerId }),
      supabase.rpc('is_org_mitglied_von_lager', { p_lager_id: lagerId }),
    ])
    if (darfRein || orgMitglied) {
      await router.replace(`/lager/${lagerId}/dashboard`)
      return
    }
  }
  pruefeTeamZugriff.value = false

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
    <p v-if="pruefeTeamZugriff"></p>
    <p v-else-if="ladefehler" class="error">{{ ladefehler }}</p>

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

      <section v-if="phase !== 'vergangen' && lager.instagram_url" class="info-karte insta-karte">
        <h2>Folgt uns</h2>
        <p>{{ phase === 'laufend' ? 'Wir posten während dem Lager laufend Fotos & Updates auf Instagram.' : 'Schon vor dem Lager gibt es News auf unserem Instagram.' }}</p>
        <a :href="lager.instagram_url" target="_blank" rel="noopener noreferrer" class="insta-link">📷 Zu unserem Instagram</a>
      </section>

      <section v-if="phase === 'vergangen'" class="info-karte insta-karte">
        <h2>Das Lager ist vorbei</h2>
        <template v-if="lager.diashow_datum">
          <p>
            An der Diashow zeigen wir Fotos & Erinnerungen ans Lager:
            <strong>{{ formatDatum(lager.diashow_datum) }}</strong>
            <template v-if="lager.diashow_zeit"> · {{ lager.diashow_zeit.slice(0, 5) }} Uhr</template>
            <template v-if="lager.diashow_ort"> · {{ lager.diashow_ort }}</template>
          </p>
        </template>
        <p v-else>Die Diashow mit Fotos & Erinnerungen ans Lager wird noch angekündigt.</p>
        <a v-if="lager.foto_link" :href="lager.foto_link" target="_blank" rel="noopener noreferrer" class="insta-link">🖼️ Zum Fotoalbum</a>
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
.insta-karte {
  text-align: center;
}
.insta-link {
  display: inline-block;
  margin-top: 0.5rem;
  font-weight: 700;
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
