import type { LagerTodo } from './workflowUtils'
import { faelligStatus, formatFaelligkeit } from './workflowUtils'

export interface TimelineMeilenstein {
  monate: number | null
  titel: string
  kurz: string
  kategorie: string
}

/** Jahresprogramm Stöckli-Lager – Meilensteine relativ zum Lagerstart */
export const JAHRES_MEILENSTEINE: TimelineMeilenstein[] = [
  { monate: 9, titel: 'Küche & Leitungsteam', kurz: '9 Mo.', kategorie: 'team' },
  { monate: 9, titel: 'Lagerhaus & Vertrag', kurz: '9 Mo.', kategorie: 'logistik' },
  { monate: 7, titel: 'Anreise / Car, Vorweekend planen', kurz: '7 Mo.', kategorie: 'logistik' },
  { monate: 7, titel: 'Finanzen-Ämtli & Budget', kurz: '7 Mo.', kategorie: 'finanzen' },
  { monate: 6, titel: 'Ämtli verteilen, TN-Anmeldung live, Werbung', kurz: '6 Mo.', kategorie: 'werbung' },
  { monate: 5, titel: 'Motto & Zweiwochenraster (eCamp)', kurz: '5 Mo.', kategorie: 'programm' },
  { monate: 5, titel: 'Jugendurlaub', kurz: '5 Mo.', kategorie: 'team' },
  { monate: 4.5, titel: 'Vorweekend', kurz: 'VW', kategorie: 'vorweekend' },
  { monate: 4, titel: 'Feinprogramm an Coach, TJ/S', kurz: '4 Mo.', kategorie: 'programm' },
  { monate: 3, titel: 'Leiter bestätigen, Küche, Sponsoring, Plakate, Kuchenstand', kurz: '3 Mo.', kategorie: 'werbung' },
  { monate: 1, titel: 'Gruppen, Elterninfo', kurz: '1 Mo.', kategorie: 'eltern' },
  { monate: 0, titel: 'Lager – Kiosk, Höck, Programm', kurz: 'Lager', kategorie: 'lager' },
  { monate: -1, titel: 'Nachbereitung, Diashow, Learnings', kurz: 'Nach', kategorie: 'nachlager' },
]

export function monateVorLager(startDatum: string | null, heute = new Date()): number | null {
  if (!startDatum) return null
  const start = new Date(startDatum + 'T00:00:00')
  const diffMs = start.getTime() - heute.getTime()
  return diffMs / (1000 * 60 * 60 * 24 * 30.44)
}

export function tageBisLager(startDatum: string | null, heute = new Date()): number | null {
  if (!startDatum) return null
  const start = new Date(startDatum + 'T00:00:00')
  const h = new Date(heute.toISOString().slice(0, 10) + 'T00:00:00')
  return Math.round((start.getTime() - h.getTime()) / (1000 * 60 * 60 * 24))
}

export type LagerPhase =
  | 'vor_planung'
  | 'frueh'
  | 'vorbereitung'
  | 'vorweekend_phase'
  | 'finale'
  | 'im_lager'
  | 'nachlager'

export function lagerPhase(
  startDatum: string | null,
  endDatum: string | null,
  heute = new Date(),
): LagerPhase {
  const heuteStr = heute.toISOString().slice(0, 10)
  if (endDatum && heuteStr > endDatum) return 'nachlager'
  if (startDatum && heuteStr >= startDatum && (!endDatum || heuteStr <= endDatum)) return 'im_lager'
  const mo = monateVorLager(startDatum, heute)
  if (mo === null) return 'vor_planung'
  if (mo > 9) return 'vor_planung'
  if (mo > 6) return 'frueh'
  if (mo > 4) return 'vorbereitung'
  if (mo > 1) return 'vorweekend_phase'
  if (mo > 0) return 'finale'
  return 'im_lager'
}

export const PHASE_LABELS: Record<LagerPhase, string> = {
  vor_planung: 'Frühe Planung (>9 Monate)',
  frueh: 'Team & Logistik (7–9 Monate)',
  vorbereitung: 'Werbung & Motto (4–6 Monate)',
  vorweekend_phase: 'Vorweekend & Feinprogramm (1–4 Monate)',
  finale: 'Finale Vorbereitung (<1 Monat)',
  im_lager: 'Im Lager',
  nachlager: 'Nach dem Lager',
}

/** Welche Features sind jetzt aktiv? */
export function featureAktiv(
  feature: 'kiosk' | 'moerderli' | 'skiweekend' | 'werbung' | 'sponsoring' | 'kuchenstand' | 'motto',
  startDatum: string | null,
  endDatum: string | null,
): boolean {
  const phase = lagerPhase(startDatum, endDatum)
  const mo = monateVorLager(startDatum)

  switch (feature) {
    case 'kiosk':
    case 'moerderli':
      return phase === 'im_lager'
    case 'skiweekend':
      return true // Org-Ebene, immer sichtbar für Zuständige
    case 'werbung':
      return mo !== null && mo <= 6
    case 'sponsoring':
      return mo !== null && mo <= 4
    case 'kuchenstand':
      return mo !== null && mo <= 3
    case 'motto':
      return mo !== null && mo <= 5
    default:
      return true
  }
}

export function phaseLabel(startDatum: string | null, endDatum: string | null): string {
  return PHASE_LABELS[lagerPhase(startDatum, endDatum)]
}

export function naechsteTodos(todos: LagerTodo[], limit = 5): LagerTodo[] {
  return [...todos]
    .filter((t) => !t.erledigt)
    .sort((a, b) => {
      const sa = faelligStatus(a.faellig_am, false)
      const sb = faelligStatus(b.faellig_am, false)
      const order = { ueberfaellig: 0, bald: 1, offen: 2, ok: 3 }
      if (order[sa] !== order[sb]) return order[sa] - order[sb]
      return (a.faellig_am ?? '9999').localeCompare(b.faellig_am ?? '9999')
    })
    .slice(0, limit)
}

export function meilensteinStatus(
  monate: number | null,
  startDatum: string | null,
): 'erledigt' | 'aktuell' | 'kommend' {
  const aktuell = monateVorLager(startDatum)
  if (aktuell === null || monate === null) return 'kommend'
  if (monate < 0 && aktuell < 0) return 'aktuell'
  if (monate <= 0 && aktuell <= 0 && aktuell > -1) return 'aktuell'
  if (aktuell <= monate - 0.5) return 'erledigt'
  if (Math.abs(aktuell - monate) <= 1) return 'aktuell'
  return 'kommend'
}

export { formatFaelligkeit, faelligStatus }
