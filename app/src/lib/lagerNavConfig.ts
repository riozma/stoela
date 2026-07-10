/** Alle Lager-Bereiche erreichbar (Rollout abgeschlossen). Ämtli-Zugriff wird in LagerDetail geprüft. */
export const LAGER_NAV_SECTIONS = [
  'dashboard',
  'chatbot',
  'programm',
  'quittungen',
  'einstellungen',
  'teilnehmer',
  'leiter',
  'gruppen',
  'fahrplan',
  'vorweekend',
  'elterninfo',
  'statistik',
  'gemini',
  'einkauf',
  'kalender',
  'leiter-zeitstrahl',
  'bearbeitung',
] as const

export function isNavSectionAllowed(tab: string): boolean {
  if (tab.startsWith('aemtli:')) return true
  return (LAGER_NAV_SECTIONS as readonly string[]).includes(tab)
}
