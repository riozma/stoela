let loadPromise: Promise<void> | null = null

function loadGoogleMaps(): Promise<void> {
  const apiKey = import.meta.env.VITE_GOOGLE_MAPS_API_KEY
  if (!apiKey) return Promise.reject(new Error('VITE_GOOGLE_MAPS_API_KEY fehlt'))

  if (!loadPromise) {
    loadPromise = new Promise((resolve, reject) => {
      const w = window as any
      if (w.google?.maps?.places) {
        resolve()
        return
      }
      const script = document.createElement('script')
      script.src = `https://maps.googleapis.com/maps/api/js?key=${apiKey}&libraries=places`
      script.async = true
      script.onload = () => resolve()
      script.onerror = () => reject(new Error('Google Maps konnte nicht geladen werden'))
      document.head.appendChild(script)
    })
  }
  return loadPromise
}

export interface OrtAuswahl {
  adresse: string
  lat: number
  lng: number
  placeId: string
}

export function useGooglePlaces() {
  async function attachAutocomplete(input: HTMLInputElement, onSelect: (ort: OrtAuswahl) => void) {
    try {
      await loadGoogleMaps()
    } catch {
      return
    }
    const g = (window as any).google
    const autocomplete = new g.maps.places.Autocomplete(input, {
      fields: ['formatted_address', 'geometry', 'place_id'],
    })
    autocomplete.addListener('place_changed', () => {
      const place = autocomplete.getPlace()
      if (!place.geometry?.location) return
      onSelect({
        adresse: place.formatted_address ?? input.value,
        lat: place.geometry.location.lat(),
        lng: place.geometry.location.lng(),
        placeId: place.place_id ?? '',
      })
    })
  }

  return { attachAutocomplete }
}
