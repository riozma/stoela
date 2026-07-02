export interface LagerTodo {
  id: string
  titel: string
  beschreibung: string | null
  kategorie: string
  zustaendig: string
  aemtli_name: string | null
  faellig_am: string | null
  erledigt: boolean
  sortierung: number
}

export const KATEGORIE_LABELS: Record<string, string> = {
  team: 'Team',
  logistik: 'Logistik',
  vorweekend: 'Vorweekend',
  programm: 'Programm',
  werbung: 'Werbung',
  finanzen: 'Finanzen',
  eltern: 'Eltern',
  lager: 'Im Lager',
  nachlager: 'Nach dem Lager',
  verein: 'Verein',
}

export const ZUSTAENDIG_LABELS: Record<string, string> = {
  lalei: 'Lagerleitung',
  kueche: 'Küche',
  aemtli: 'Ämtli',
  alle: 'Alle',
}

export function formatFaelligkeit(datum: string | null): string {
  if (!datum) return '–'
  return new Intl.DateTimeFormat('de-CH', { day: 'numeric', month: 'short', year: 'numeric' }).format(
    new Date(datum + 'T00:00:00'),
  )
}

export function faelligStatus(datum: string | null, erledigt: boolean): 'ok' | 'bald' | 'ueberfaellig' | 'offen' {
  if (erledigt) return 'ok'
  if (!datum) return 'offen'
  const heute = new Date().toISOString().slice(0, 10)
  if (datum < heute) return 'ueberfaellig'
  const in7 = new Date()
  in7.setDate(in7.getDate() + 7)
  if (datum <= in7.toISOString().slice(0, 10)) return 'bald'
  return 'offen'
}

export function gruppiereTodos(todos: LagerTodo[]): { kategorie: string; items: LagerTodo[] }[] {
  const map = new Map<string, LagerTodo[]>()
  for (const t of todos) {
    const list = map.get(t.kategorie) ?? []
    list.push(t)
    map.set(t.kategorie, list)
  }
  return [...map.entries()]
    .map(([kategorie, items]) => ({
      kategorie,
      items: items.sort((a, b) => a.sortierung - b.sortierung || (a.faellig_am ?? '').localeCompare(b.faellig_am ?? '')),
    }))
    .sort((a, b) => (a.items[0]?.sortierung ?? 0) - (b.items[0]?.sortierung ?? 0))
}

export function bestaetigenBis(startDatum: string | null): string | null {
  if (!startDatum) return null
  const d = new Date(startDatum + 'T00:00:00')
  d.setMonth(d.getMonth() - 3)
  return d.toISOString().slice(0, 10)
}

export const BLOCK_TYP_LABELS: Record<string, string> = {
  programm: 'Programm',
  anreise: 'Anreise',
  abreise: 'Abreise',
  vorweekend: 'Vorweekend',
}

export const ANREISE_FELDER = [
  { key: 'treffpunkt', label: 'Treffpunkt' },
  { key: 'abfahrt', label: 'Abfahrt (Uhrzeit/Ort)' },
  { key: 'mitfahrgelegenheit', label: 'Mitfahrgelegenheit / Car' },
  { key: 'gepaeck_hinweis', label: 'Gepäck-Hinweis' },
  { key: 'verantwortlich_kontakt', label: 'Verantwortlich (Kontakt)' },
] as const

export const ABREISE_FELDER = [
  { key: 'treffpunkt', label: 'Rückkehr-Ort' },
  { key: 'ankunft', label: 'Ankunft ca.' },
  { key: 'abholung', label: 'Abholung durch Eltern' },
  { key: 'verantwortlich_kontakt', label: 'Verantwortlich (Kontakt)' },
] as const
