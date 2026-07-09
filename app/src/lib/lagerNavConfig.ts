/** Während des Lager-Rollouts nur diese Bereiche erreichbar. */
export const LAGER_NAV_SECTIONS = [
  'dashboard',
  'chatbot',
  'programm',
  'quittungen',
  'team',
  'einstellungen',
  'teilnehmer',
  'leiter',
  'gruppen',
  'bearbeitung',
] as const

export const LAGER_NAV_AEMTLI = ['finanzen'] as const

export function isNavSectionAllowed(tab: string): boolean {
  if (tab.startsWith('aemtli:')) {
    const slug = tab.slice(7)
    return (LAGER_NAV_AEMTLI as readonly string[]).includes(slug)
  }
  return (LAGER_NAV_SECTIONS as readonly string[]).includes(tab)
}
