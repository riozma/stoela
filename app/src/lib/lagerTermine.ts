export type LagerTerminTyp =
  | 'lager'
  | 'elternabend'
  | 'kennenlernabend'
  | 'diashow'
  | 'vorweekend'
  | 'skiweekend'
  | 'hoeck'
  | 'sonstiges'

export interface LagerTermin {
  id: string
  lager_id: string
  typ: LagerTerminTyp
  titel: string
  start_datum: string | null
  end_datum: string | null
  start_zeit: string | null
  end_zeit: string | null
  ort: string | null
  beschreibung: string | null
  oeffentlich: boolean
  sortierung: number
}

/** Nur unter Einstellungen / Vorweekend – kein Bearbeiten im Kalender */
export const KALENDER_NUR_EINSTELLUNGEN: LagerTerminTyp[] = ['lager', 'vorweekend']

/** Datum/Ort im Kalender änderbar, nicht löschbar */
export const KALENDER_DATUM_EDITIERBAR: LagerTerminTyp[] = ['elternabend', 'kennenlernabend', 'diashow']

/** @deprecated use KALENDER_NUR_EINSTELLUNGEN */
export const KALENDER_READONLY_TYPEN: LagerTerminTyp[] = KALENDER_NUR_EINSTELLUNGEN

/** Im Kalender-Tab hinzufügbar/bearbeitbar/löschbar (je Lager max. einer) */
export const KALENDER_FORM_TYPEN: LagerTerminTyp[] = ['skiweekend', 'hoeck', 'sonstiges']

export function kannKalenderTerminLoeschen(typ: LagerTerminTyp) {
  return KALENDER_FORM_TYPEN.includes(typ)
}

export function kannKalenderTerminBearbeiten(typ: LagerTerminTyp) {
  return KALENDER_FORM_TYPEN.includes(typ) || KALENDER_DATUM_EDITIERBAR.includes(typ)
}

export function istKalenderNurEinstellungen(typ: LagerTerminTyp) {
  return KALENDER_NUR_EINSTELLUNGEN.includes(typ)
}

export const KALENDER_SINGLETON_TYPEN: LagerTerminTyp[] = [
  'lager',
  'elternabend',
  'kennenlernabend',
  'diashow',
  'vorweekend',
  'skiweekend',
  'hoeck',
]

export const KALENDER_READONLY_HINTS: Partial<Record<LagerTerminTyp, string>> = {
  lager: 'Unter Einstellungen (Start/Ende/Ort)',
  vorweekend: 'Unter Vorweekend',
}

export const TERMIN_TYP_LABELS: Record<LagerTerminTyp, string> = {
  lager: 'Lager',
  elternabend: 'Elternabend',
  kennenlernabend: 'Kennenlernabend',
  diashow: 'Diashow / Lagerrückblick',
  vorweekend: 'Vorweekend',
  skiweekend: 'Skiweekend',
  hoeck: 'Höck',
  sonstiges: 'Sonstiges',
}

export function formatTerminDatum(t: LagerTermin) {
  if (!t.start_datum) return '–'
  const fmt = (d: string) =>
    new Intl.DateTimeFormat('de-CH', { day: '2-digit', month: '2-digit', year: 'numeric' }).format(
      new Date(d + 'T00:00:00'),
    )
  if (!t.end_datum || t.end_datum === t.start_datum) return fmt(t.start_datum)
  return `${fmt(t.start_datum)} – ${fmt(t.end_datum)}`
}

export function formatTerminZeit(t: LagerTermin) {
  const parts: string[] = []
  if (t.start_zeit) parts.push(t.start_zeit.slice(0, 5))
  if (t.end_zeit) parts.push(t.end_zeit.slice(0, 5))
  return parts.join(' – ')
}
