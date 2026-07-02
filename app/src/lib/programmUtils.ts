export type BlockCode = 'LP' | 'LS' | 'LA' | 'ES'

export interface ProgrammBlockBasis {
  id: string
  code: BlockCode
  nummer: string | null
  titel: string
  tag: string | null
  start_zeit: string | null
  end_zeit: string | null
  ort: string | null
  verantwortlich: string | null
}

export const CODE_LABELS: Record<BlockCode, string> = {
  LP: 'Lagerprogramm',
  LS: 'Lagersport',
  LA: 'Lageraktivität',
  ES: 'Essen',
}

export const RASTER_START_MIN = 6 * 60
export const RASTER_END_MIN = 22 * 60
export const RASTER_SLOT_MIN = 30

export function heuteIso(): string {
  return new Date().toISOString().slice(0, 10)
}

export function lagerLaeuft(startDatum: string | null, endDatum: string | null): boolean {
  const heute = heuteIso()
  if (!startDatum) return false
  if (heute < startDatum) return false
  if (endDatum && heute > endDatum) return false
  return true
}

export function tageZwischen(start: string, end: string): string[] {
  const list: string[] = []
  const cur = new Date(start + 'T00:00:00')
  const last = new Date(end + 'T00:00:00')
  while (cur <= last) {
    list.push(cur.toISOString().slice(0, 10))
    cur.setDate(cur.getDate() + 1)
  }
  return list
}

export function formatProgrammTag(tag: string): string {
  const d = new Date(tag + 'T00:00:00')
  return new Intl.DateTimeFormat('de-CH', { weekday: 'short', day: 'numeric', month: 'numeric' }).format(d)
}

export function formatProgrammZeit(zeit: string | null): string {
  if (!zeit) return '–'
  const d = new Date(zeit)
  if (Number.isNaN(d.getTime())) return zeit
  return new Intl.DateTimeFormat('de-CH', { hour: '2-digit', minute: '2-digit' }).format(d)
}

export function zeitZuMinuten(zeit: string | null): number {
  if (!zeit) return RASTER_START_MIN
  const d = new Date(zeit)
  if (!Number.isNaN(d.getTime())) return d.getHours() * 60 + d.getMinutes()
  const m = zeit.match(/(\d{1,2}):(\d{2})/)
  if (m) return parseInt(m[1], 10) * 60 + parseInt(m[2], 10)
  return RASTER_START_MIN
}

export function minutenZuLabel(min: number): string {
  const h = Math.floor(min / 60)
  const m = min % 60
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`
}

export function rasterSlots(): number[] {
  const slots: number[] = []
  for (let m = RASTER_START_MIN; m < RASTER_END_MIN; m += RASTER_SLOT_MIN) slots.push(m)
  return slots
}

export function bloeckeFuerTag<T extends { tag: string | null }>(bloecke: T[], tag: string): T[] {
  return bloecke.filter((b) => b.tag === tag)
}

export function wocheIndexFuerTag(alleTage: string[], tag: string, tageProSeite: number): number {
  const idx = alleTage.indexOf(tag)
  if (idx < 0) return 0
  return Math.floor(idx / tageProSeite)
}

export function tageFuerSeite(alleTage: string[], seite: number, tageProSeite: number): string[] {
  const start = seite * tageProSeite
  return alleTage.slice(start, start + tageProSeite)
}
