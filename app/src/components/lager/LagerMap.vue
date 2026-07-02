<script setup lang="ts">
import { onMounted, ref } from 'vue'

const props = defineProps<{
  lat?: number | null
  lng?: number | null
  ort?: string | null
}>()

const mapEl = ref<HTMLDivElement | null>(null)
const karteFehler = ref(false)
const kartenLink = ref('')

function suchLink(query: string) {
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`
}

async function ladeGoogleMaps(apiKey: string) {
  const w = window as any
  if (w.google?.maps) return w.google
  await new Promise<void>((resolve, reject) => {
    const script = document.createElement('script')
    script.src = `https://maps.googleapis.com/maps/api/js?key=${apiKey}`
    script.async = true
    script.onload = () => resolve()
    script.onerror = () => reject(new Error('Maps load failed'))
    document.head.appendChild(script)
  })
  return (window as any).google
}

async function koordinatenErmitteln(g: any): Promise<{ lat: number; lng: number } | null> {
  if (props.lat != null && props.lng != null) {
    return { lat: props.lat, lng: props.lng }
  }
  if (!props.ort?.trim()) return null

  const geocoder = new g.maps.Geocoder()
  return new Promise((resolve) => {
    geocoder.geocode({ address: props.ort!.trim() }, (results: any[], status: string) => {
      if (status === 'OK' && results[0]) {
        const loc = results[0].geometry.location
        resolve({ lat: loc.lat(), lng: loc.lng() })
      } else {
        resolve(null)
      }
    })
  })
}

onMounted(async () => {
  const query = props.ort?.trim() || (props.lat != null && props.lng != null ? `${props.lat},${props.lng}` : '')
  if (query) kartenLink.value = suchLink(query)

  if (!mapEl.value) return
  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY
  if (!apiKey) {
    karteFehler.value = true
    return
  }

  try {
    const g = await ladeGoogleMaps(apiKey)
    const center = await koordinatenErmitteln(g)
    if (!center) {
      karteFehler.value = true
      return
    }

    const map = new g.maps.Map(mapEl.value, {
      center,
      zoom: 13,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false,
    })
    new g.maps.Marker({
      position: center,
      map,
      title: props.ort ?? 'Lagerort',
    })
  } catch {
    karteFehler.value = true
  }
})
</script>

<template>
  <div class="lager-map">
    <div v-if="!karteFehler" ref="mapEl" class="map-container" role="img" :aria-label="ort ? `Karte: ${ort}` : 'Lagerort'"></div>
    <p v-else-if="kartenLink" class="hint">
      <a :href="kartenLink" target="_blank" rel="noopener noreferrer">
        📍 {{ ort ?? 'Lagerort' }} auf Google Maps anzeigen
      </a>
    </p>
    <a
      v-if="kartenLink && !karteFehler"
      class="maps-link"
      :href="kartenLink"
      target="_blank"
      rel="noopener noreferrer"
    >
      {{ ort ?? 'Lagerort' }} in Google Maps öffnen
    </a>
  </div>
</template>

<style scoped>
.lager-map { margin: 1rem 0; }
.map-container {
  width: 100%;
  height: 200px;
  border-radius: var(--radius-md);
  border: 1px solid var(--color-border);
  background: var(--color-surface-muted);
}
.maps-link, .hint a {
  display: inline-block;
  margin-top: 0.4rem;
  font-size: 0.85rem;
  color: var(--color-accent);
}
.hint { font-size: 0.88rem; color: var(--color-text-muted); }
</style>
