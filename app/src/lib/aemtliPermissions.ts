/** Geschützte Ämtli – nur App Admin darf diese zuweisen */
export const GESCHUETZTE_AEMTLI: string[] = []

export function istGeschuetztesAemtli(name: string): boolean {
  return (GESCHUETZTE_AEMTLI as readonly string[]).includes(name)
}

export function darfGeschuetztesAemtliZuweisen(isLeitung: boolean): boolean {
  return isLeitung
}

