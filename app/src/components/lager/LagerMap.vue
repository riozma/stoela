<script setup lang="ts">
import { onMounted, ref } from 'vue'

const props = defineProps<{
  lat: number
  lng: number
  ort?: string | null
}>()

const mapEl = ref<HTMLDivElement | null>(null)
const karteFehler = ref(false)

onMounted(async () => {
  if (!mapEl.value) return
  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY
  if (!apiKey) {
    karteFehler.value = true
    return
  }

  try {
    const w = window as any
    if (!w.google?.maps) {
      await new Promise<void>((resolve, reject) => {
        const script = document.createElement('script')
        script.src = `https://maps.googleapis.com/maps/api/js?key=${apiKey}`
        script.async = true
        script.onload = () => resolve()
        script.onerror = () => reject(new Error('Maps load failed'))
        document.head.appendChild(script)
      })
    }
    const g = (window as any).google
    const map = new g.maps.Map(mapEl.value, {
      center: { lat: props.lat, lng: props.lng },
      zoom: 13,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false,
    })
    new g.maps.Marker({
      position: { lat: props.lat, lng: props.lng },
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
    <p v-else class="hint">
      <a :href="`https://www.google.com/maps/search/?api=1&query=${lat},${lng}`" target="_blank" rel="noopener noreferrer">
        📍 {{ ort ?? 'Lagerort' }} auf Google Maps anzeigen
      </a>
    </p>
    <a
      v-if="ort && !karteFehler"
      class="maps-link"
      :href="`https://www.google.com/maps/search/?api=1&query=${lat},${lng}`"
      target="_blank"
      rel="noopener noreferrer"
    >
      {{ ort }} in Google Maps öffnen
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
