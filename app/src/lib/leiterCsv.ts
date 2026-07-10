export interface LeiterExportZeile {
  vorname: string
  nachname: string
  email?: string | null
  telefon?: string | null
  geburtsdatum?: string | null
  geschlecht?: string | null
  ahv_nr?: string | null
  anwesend_von?: string | null
  anwesend_bis?: string | null
  status?: string
  anmeldung_art?: string | null
  essensgewohnheiten?: string | null
  profile_id?: string | null
  aemtli?: string
  app_rolle?: string | null
}

function csvZelle(wert: string | number | null | undefined) {
  const s = String(wert ?? '')
  if (/[",\n\r]/.test(s)) return `"${s.replace(/"/g, '""')}"`
  return s
}

export function leiterAlsCsv(zeilen: LeiterExportZeile[]) {
  const kopf = [
    'Vorname',
    'Nachname',
    'E-Mail',
    'Telefon',
    'Geburtsdatum',
    'Geschlecht',
    'AHV',
    'Anwesend von',
    'Anwesend bis',
    'Status',
    'Anmeldung',
    'Essensgewohnheiten',
    'Login',
    'Ämtli',
    'App-Rolle',
  ]
  const daten = zeilen.map((z) =>
    [
      z.vorname,
      z.nachname,
      z.email,
      z.telefon,
      z.geburtsdatum,
      z.geschlecht,
      z.ahv_nr,
      z.anwesend_von,
      z.anwesend_bis,
      z.status,
      z.anmeldung_art,
      z.essensgewohnheiten,
      z.profile_id ? 'ja' : 'nein',
      z.aemtli,
      z.app_rolle,
    ]
      .map(csvZelle)
      .join(','),
  )
  return [kopf.join(','), ...daten].join('\n')
}

export function leiterCsvDownload(dateiname: string, inhalt: string) {
  const blob = new Blob(['\ufeff' + inhalt], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = dateiname
  a.click()
  URL.revokeObjectURL(url)
}
