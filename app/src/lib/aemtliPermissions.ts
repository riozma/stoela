/** Nur Lagerleitung darf diese Ämtli zuweisen */
export const GESCHUETZTE_AEMTLI = ['Küche', 'Finanzen'] as const

export function istGeschuetztesAemtli(name: string): boolean {
  return (GESCHUETZTE_AEMTLI as readonly string[]).includes(name)
}

export function darfGeschuetztesAemtliZuweisen(isLeitung: boolean): boolean {
  return isLeitung
}
