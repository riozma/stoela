<script setup lang="ts">
import { onMounted, ref } from 'vue'

const props = defineProps<{
  initialLat?: number | null
  initialLng?: number | null
}>()

const emit = defineEmits<{
  gewaehlt: [{ lat: number; lng: number }]
  abbrechen: []
}>()

const mapEl = ref<HTMLDivElement | null>(null)
const fehler = ref('')
const ladend = ref(true)
const position = ref<{ lat: number; lng: number } | null>(null)

let mapInstance: any = null
let marker: any = null
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

function ermittleStandort(): Promise<{ lat: number; lng: number } | null> {
  if (props.initialLat != null && props.initialLng != null) {
    return Promise.resolve({ lat: props.initialLat, lng: props.initialLng })
  }
  if (!navigator.geolocation) return Promise.resolve(null)
  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      (pos) => resolve({ lat: pos.coords.latitude, lng: pos.coords.longitude }),
      () => resolve(null),
      { timeout: 6000 },
    )
  })
}

function pinSetzen(pos: { lat: number; lng: number }) {
  position.value = pos
  if (!mapInstance || !googleRef) return
  if (marker) {
    marker.setPosition(pos)
  } else {
    marker = new googleRef.maps.Marker({ position: pos, map: mapInstance, draggable: true })
    marker.addListener('dragend', () => {
      const p = marker.getPosition()
      position.value = { lat: p.lat(), lng: p.lng() }
    })
  }
}

onMounted(async () => {
  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY
  if (!apiKey || !mapEl.value) {
    fehler.value = 'Karte nicht verfügbar (Google-Maps-Key fehlt).'
    ladend.value = false
    return
  }
  try {
    googleRef = await ladeGoogleMaps(apiKey)
    const start = (await ermittleStandort()) ?? { lat: 46.8, lng: 8.2 }
    mapInstance = new googleRef.maps.Map(mapEl.value, {
      center: start,
      zoom: props.initialLat != null ? 15 : 12,
      mapTypeId: 'hybrid',
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: false,
    })
    mapInstance.addListener('click', (e: any) => {
      pinSetzen({ lat: e.latLng.lat(), lng: e.latLng.lng() })
    })
    if (props.initialLat != null && props.initialLng != null) {
      pinSetzen(start)
    }
  } catch {
    fehler.value = 'Karte konnte nicht geladen werden.'
  }
  ladend.value = false
})

function uebernehmen() {
  if (position.value) emit('gewaehlt', position.value)
}
</script>

<template>
  <div class="ort-waehlen">
    <p class="hint">Auf der Karte klicken, um den Punkt der Wiese zu setzen (Pin lässt sich verschieben).</p>
    <p v-if="ladend" class="hint">Lade Karte / Standort...</p>
    <p v-if="fehler" class="error">{{ fehler }}</p>
    <div v-show="!fehler" ref="mapEl" class="map-container"></div>
    <div class="aktionen">
      <button type="button" class="secondary" @click="emit('abbrechen')">Abbrechen</button>
      <button type="button" :disabled="!position" @click="uebernehmen">Ort übernehmen</button>
    </div>
  </div>
</template>

<style scoped>
.ort-waehlen { margin: 0.5rem 0 1rem; padding: 0.75rem; background: var(--color-surface-muted); border: 1px solid var(--color-border); border-radius: var(--radius-md); }
.map-container { width: 100%; height: 320px; border-radius: var(--radius-md); border: 1px solid var(--color-border); background: var(--color-surface); margin: 0.5rem 0; }
.aktionen { display: flex; gap: 0.5rem; justify-content: flex-end; }
.hint { color: var(--color-text-muted); font-size: 0.85rem; margin: 0 0 0.35rem; }
.error { color: var(--color-danger); font-size: 0.85rem; }
</style>
