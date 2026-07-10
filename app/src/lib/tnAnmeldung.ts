export const ESSENS_OPTIONEN = [
  { id: 'vegan', label: 'Vegan' },
  { id: 'vegetarisch', label: 'Vegetarisch' },
  { id: 'kein_schweinefleisch', label: 'Kein Schweinefleisch' },
  { id: 'glutenfrei', label: 'Glutenfrei' },
  { id: 'laktose_leicht', label: 'Leichte Laktoseintoleranz' },
  { id: 'laktose_schwer', label: 'Schwere Laktoseintoleranz' },
] as const

export type EssensOptionId = (typeof ESSENS_OPTIONEN)[number]['id']

export interface ElternDaten {
  eltern_email: string
  eltern_vorname: string
  eltern_nachname: string
  telefon: string
  adresse: string
  plz: string
  ort: string
  aufenthaltsort: string
  aufenthaltsort_unbekannt: boolean
}

export interface KindDaten {
  vorname: string
  nachname: string
  geburtsdatum: string
  geschlecht: '' | 'm' | 'w' | 'd'
  essensgewohnheiten: EssensOptionId[]
  essensgewohnheiten_keine: boolean
  essensgewohnheiten_sonstiges: string
  medikamente: string
  gesundheit_bemerkungen: string
  ahv_nr: string
  sonstige_info: string
  krankenkasse_vorne: File | null
  krankenkasse_hinten: File | null
  impfungen: File[]
}

export interface LagerTnInfo {
  id: string
  name: string
  jahr: number
  ort: string | null
  start_datum: string | null
  end_datum: string | null
  info: {
    beschreibung: string
    lagerart: string
    durchgefuehrt_von: string
    anmeldeschluss: string | null
    mindestalter: string
    max_teilnehmer: string
    kosten_erstes_kind: number
    kosten_weiteres_kind: number
    kontakt_name: string
    kontakt_email: string
    kontakt_telefon: string
    elternabend_datum: string | null
    kennenlernabend_datum: string | null
    lagerrueckblick_datum: string | null
    versicherung_hinweis: string
  }
}

export function formatDatumCh(iso: string | null) {
  if (!iso) return '–'
  return new Intl.DateTimeFormat('de-CH', { day: '2-digit', month: '2-digit', year: 'numeric' }).format(
    new Date(iso + 'T00:00:00'),
  )
}

export function formatDatumSpanne(von: string | null, bis: string | null) {
  if (!von) return '–'
  if (!bis) return formatDatumCh(von)
  return `${formatDatumCh(von)}–${formatDatumCh(bis)}`
}

export function ahvGueltig(wert: string) {
  return /^756\.\d{4}\.\d{4}\.\d{2}$/.test(wert.trim())
}

export function ahvBeimTippen(roh: string) {
  const z = roh.replace(/\D/g, '').slice(0, 13)
  if (z.length <= 3) return z
  if (z.length <= 7) return `${z.slice(0, 3)}.${z.slice(3)}`
  if (z.length <= 11) return `${z.slice(0, 3)}.${z.slice(3, 7)}.${z.slice(7)}`
  return `${z.slice(0, 3)}.${z.slice(3, 7)}.${z.slice(7, 11)}.${z.slice(11)}`
}

export function leerEltern(): ElternDaten {
  return {
    eltern_email: '',
    eltern_vorname: '',
    eltern_nachname: '',
    telefon: '',
    adresse: '',
    plz: '',
    ort: '',
    aufenthaltsort: '',
    aufenthaltsort_unbekannt: false,
  }
}

export function leerKind(): KindDaten {
  return {
    vorname: '',
    nachname: '',
    geburtsdatum: '',
    geschlecht: '',
    essensgewohnheiten: [],
    essensgewohnheiten_keine: false,
    essensgewohnheiten_sonstiges: '',
    medikamente: '',
    gesundheit_bemerkungen: '',
    ahv_nr: '',
    sonstige_info: '',
    krankenkasse_vorne: null,
    krankenkasse_hinten: null,
    impfungen: [],
  }
}

export function berechneLagerbeitrag(kindAnzahl: number, erstes: number, weiteres: number) {
  if (kindAnzahl <= 0) return 0
  return erstes + Math.max(0, kindAnzahl - 1) * weiteres
}

export function essensLabel(ids: readonly EssensOptionId[], sonstiges: string, keine: boolean) {
  if (keine) return 'Keine besonderen Gewohnheiten'
  const teile: string[] = ESSENS_OPTIONEN.filter((o) => ids.includes(o.id)).map((o) => o.label)
  if (sonstiges.trim()) teile.push(sonstiges.trim())
  return teile.length ? teile.join(', ') : '–'
}
