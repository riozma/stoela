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

const TN_CSV_SPALTEN: { key: string; kopf: string; wert: (z: TnExportZeile) => string | number | null | undefined }[] = [
  { key: 'geburtsdatum', kopf: 'Geburtsdatum', wert: (z) => z.geburtsdatum },
  { key: 'geschlecht', kopf: 'Geschlecht', wert: (z) => z.geschlecht },
  { key: 'ahv_nr', kopf: 'AHV', wert: (z) => z.ahv_nr },
  { key: 'notfallkontakt', kopf: 'Notfallkontakt', wert: (z) => z.notfallkontakt },
  { key: 'allergien', kopf: 'Allergien', wert: (z) => z.allergien },
  { key: 'essensgewohnheiten', kopf: 'Essensgewohnheiten', wert: (z) => z.essensgewohnheiten },
  { key: 'essensgewohnheiten', kopf: 'Essen Sonstiges', wert: (z) => z.essensgewohnheiten_sonstiges },
  { key: 'medikamente', kopf: 'Medikamente', wert: (z) => z.medikamente },
  { key: 'gesundheit', kopf: 'Gesundheit', wert: (z) => z.gesundheit_bemerkungen },
  { key: 'eltern', kopf: 'Eltern Vorname', wert: (z) => z.eltern_vorname },
  { key: 'eltern', kopf: 'Eltern Nachname', wert: (z) => z.eltern_nachname },
  { key: 'eltern', kopf: 'Eltern E-Mail', wert: (z) => z.eltern_email },
  { key: 'eltern', kopf: 'Eltern Telefon', wert: (z) => z.eltern_telefon },
  { key: 'eltern', kopf: 'Eltern Adresse', wert: (z) => z.eltern_adresse },
  { key: 'eltern', kopf: 'Eltern PLZ', wert: (z) => z.eltern_plz },
  { key: 'eltern', kopf: 'Eltern Ort', wert: (z) => z.eltern_ort },
  { key: 'eltern', kopf: 'Aufenthaltsort Eltern', wert: (z) => z.eltern_aufenthaltsort },
  { key: 'anwesend', kopf: 'Anwesend von', wert: (z) => z.anwesend_von },
  { key: 'anwesend', kopf: 'Anwesend bis', wert: (z) => z.anwesend_bis },
  { key: 'sonstiges', kopf: 'Sonstiges', wert: (z) => z.sonstige_info },
]

/** spalten: optionale Keys aus TN_SPALTEN_OPTIONAL (LagerDetail.vue) -- ohne Angabe werden alle Spalten exportiert. */
export function tnAlsCsv(zeilen: TnExportZeile[], spalten?: string[]) {
  const aktiveSpalten = spalten ? TN_CSV_SPALTEN.filter((s) => spalten.includes(s.key)) : TN_CSV_SPALTEN
  const kopf = ['Vorname', 'Nachname', 'Rolle', 'Status', ...aktiveSpalten.map((s) => s.kopf)]
  const daten = zeilen.map((z) =>
    [z.vorname, z.nachname, z.rolle, z.status, ...aktiveSpalten.map((s) => s.wert(z))]
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
