<script setup lang="ts">
import { onMounted, ref, watch } from 'vue'

interface WiesePin {
  id: string
  name: string
  lat: number | null
  lng: number | null
}

const props = defineProps<{ wiesen: WiesePin[] }>()

const mapEl = ref<HTMLDivElement | null>(null)
const fehler = ref(false)
let mapInstance: any = null
let markers: any[] = []
let googleRef: any = null

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

function zeichnePins() {
  if (!googleRef || !mapInstance) return
  markers.forEach((m) => m.setMap(null))
  markers = []
  const punkte = props.wiesen.filter((w) => w.lat != null && w.lng != null)
  if (!punkte.length) return

  const bounds = new googleRef.maps.LatLngBounds()
  for (const w of punkte) {
    const pos = { lat: w.lat as number, lng: w.lng as number }
    const marker = new googleRef.maps.Marker({ position: pos, map: mapInstance, title: w.name })
    markers.push(marker)
    bounds.extend(pos)
  }
  if (punkte.length === 1) {
    mapInstance.setCenter({ lat: punkte[0].lat, lng: punkte[0].lng })
    mapInstance.setZoom(14)
  } else {
    mapInstance.fitBounds(bounds)
  }
}

onMounted(async () => {
  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY
  if (!apiKey || !mapEl.value) {
    fehler.value = true
    return
  }
  try {
    googleRef = await ladeGoogleMaps(apiKey)
    mapInstance = new googleRef.maps.Map(mapEl.value, {
      center: { lat: 46.8, lng: 8.2 },
      zoom: 8,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false,
    })
    zeichnePins()
  } catch {
    fehler.value = true
  }
})

watch(() => props.wiesen, zeichnePins, { deep: true })
</script>

<template>
  <div class="wiesen-karte">
    <div v-if="!fehler" ref="mapEl" class="map-container" role="img" aria-label="Karte der erfassten Spielwiesen"></div>
    <p v-else class="hint">Karte nicht verfügbar (Google-Maps-Key fehlt).</p>
  </div>
</template>

<style scoped>
.wiesen-karte { margin: 0.75rem 0 1rem; }
.map-container {
  width: 100%;
  height: 260px;
  border-radius: var(--radius-md);
  border: 1px solid var(--color-border);
  background: var(--color-surface-muted);
}
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
