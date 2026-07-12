export interface TnExportZeile {
  vorname: string
  nachname: string
  geburtsdatum?: string | null
  geschlecht?: string | null
  ahv_nr?: string | null
  rolle?: string
  status?: string
  notfallkontakt?: string | null
  allergien?: string | null
  essensgewohnheiten?: string | null
  essensgewohnheiten_sonstiges?: string | null
  medikamente?: string | null
  gesundheit_bemerkungen?: string | null
  eltern_vorname?: string | null
  eltern_nachname?: string | null
  eltern_email?: string | null
  eltern_telefon?: string | null
  eltern_adresse?: string | null
  eltern_plz?: string | null
  eltern_ort?: string | null
  eltern_aufenthaltsort?: string | null
  anwesend_von?: string | null
  anwesend_bis?: string | null
  sonstige_info?: string | null
}

function csvZelle(wert: string | number | null | undefined) {
  const s = String(wert ?? '')
  if (/[",\n\r]/.test(s)) return `"${s.replace(/"/g, '""')}"`
  return s
}

export function tnAlsCsv(zeilen: TnExportZeile[]) {
  const kopf = [
    'Vorname', 'Nachname', 'Geburtsdatum', 'Geschlecht', 'AHV', 'Rolle', 'Status',
    'Notfallkontakt', 'Allergien', 'Essensgewohnheiten', 'Essen Sonstiges', 'Medikamente', 'Gesundheit',
    'Eltern Vorname', 'Eltern Nachname', 'Eltern E-Mail', 'Eltern Telefon', 'Eltern Adresse', 'Eltern PLZ', 'Eltern Ort', 'Aufenthaltsort Eltern',
    'Anwesend von', 'Anwesend bis', 'Sonstiges',
  ]
  const daten = zeilen.map((z) =>
    [
      z.vorname, z.nachname, z.geburtsdatum, z.geschlecht, z.ahv_nr, z.rolle, z.status,
      z.notfallkontakt, z.allergien, z.essensgewohnheiten, z.essensgewohnheiten_sonstiges, z.medikamente, z.gesundheit_bemerkungen,
      z.eltern_vorname, z.eltern_nachname, z.eltern_email, z.eltern_telefon, z.eltern_adresse, z.eltern_plz, z.eltern_ort, z.eltern_aufenthaltsort,
      z.anwesend_von, z.anwesend_bis, z.sonstige_info,
    ]
      .map(csvZelle)
      .join(','),
  )
  return [kopf.join(','), ...daten].join('\n')
}

export function tnCsvDownload(dateiname: string, inhalt: string) {
  const blob = new Blob(['﻿' + inhalt], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = dateiname
  a.click()
  URL.revokeObjectURL(url)
}
