/** Geschützte Ämtli – nur App Admin darf diese zuweisen */
export const GESCHUETZTE_AEMTLI: string[] = []

export function istGeschuetztesAemtli(name: string): boolean {
  return (GESCHUETZTE_AEMTLI as readonly string[]).includes(name)
}

export function darfGeschuetztesAemtliZuweisen(isLeitung: boolean): boolean {
  return isLeitung
}

/** App Admin Rolle – hat Zugriff auf ALLES */
export const APP_ADMIN_ROLLE = 'app_admin'

export function istAppAdmin(rolle: string | null | undefined): boolean {
  return rolle === APP_ADMIN_ROLLE
}

/** Prüft ob jemand App Admin ist (Lalei oder App Admin) */
export function darfAppAdminVergeben(istLalei: boolean): boolean {
  return istLalei
}