export interface TagesWetter {
  datum: string
  tempMax: number
  tempMin: number
  wettercode: number
  beschreibung: string
}

const WETTER_BESCHREIBUNG: Record<number, string> = {
  0: 'Klar',
  1: 'Überwiegend klar',
  2: 'Teilweise bewölkt',
  3: 'Bewölkt',
  45: 'Nebel',
  48: 'Nebel',
  51: 'Nieselregen',
  53: 'Nieselregen',
  55: 'Nieselregen',
  61: 'Regen',
  63: 'Regen',
  65: 'Starkregen',
  71: 'Schnee',
  73: 'Schnee',
  75: 'Starkschnee',
  80: 'Regenschauer',
  81: 'Regenschauer',
  82: 'Starke Regenschauer',
  95: 'Gewitter',
  96: 'Gewitter mit Hagel',
  99: 'Gewitter mit Hagel',
}

export async function ladeWetter(
  lat: number,
  lng: number,
  startDatum: string,
  endDatum: string,
): Promise<TagesWetter[]> {
  const url = new URL('https://api.open-meteo.com/v1/forecast')
  url.searchParams.set('latitude', String(lat))
  url.searchParams.set('longitude', String(lng))
  url.searchParams.set(
    'daily',
    'weathercode,temperature_2m_max,temperature_2m_min',
  )
  url.searchParams.set('timezone', 'Europe/Zurich')
  url.searchParams.set('start_date', startDatum)
  url.searchParams.set('end_date', endDatum)

  const response = await fetch(url)
  if (!response.ok) throw new Error('Wetter konnte nicht geladen werden')

  const data = await response.json()
  const daily = data.daily
  if (!daily?.time?.length) return []

  return daily.time.map((datum: string, i: number) => ({
    datum,
    tempMax: Math.round(daily.temperature_2m_max[i]),
    tempMin: Math.round(daily.temperature_2m_min[i]),
    wettercode: daily.weathercode[i],
    beschreibung: WETTER_BESCHREIBUNG[daily.weathercode[i]] ?? 'Unbekannt',
  }))
}
