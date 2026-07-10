export type OrgRessourceTyp = 'link' | 'zugang'
export type OrgRessourceSichtbarkeit = 'alle' | 'leitung' | 'admin' | 'ausgewaehlt'

export interface OrgRessource {
  id: string
  typ: OrgRessourceTyp
  titel: string
  url: string | null
  benutzername: string | null
  passwort: string | null
  notiz: string | null
  sichtbarkeit: OrgRessourceSichtbarkeit
  sortierung: number
  zugewiesene_profile_ids: string[]
}

export interface OrgRessourceForm {
  id: string | null
  typ: OrgRessourceTyp
  titel: string
  url: string
  benutzername: string
  passwort: string
  notiz: string
  sichtbarkeit: OrgRessourceSichtbarkeit
  sortierung: number
  zugewiesene_profile_ids: string[]
}

export const SICHTBARKEIT_LABELS: Record<OrgRessourceSichtbarkeit, string> = {
  alle: 'Alle Mitglieder',
  leitung: 'Nur Leitung',
  admin: 'Nur Admins',
  ausgewaehlt: 'Ausgewählte Mitglieder',
}

export function leerRessourceForm(): OrgRessourceForm {
  return {
    id: null,
    typ: 'link',
    titel: '',
    url: '',
    benutzername: '',
    passwort: '',
    notiz: '',
    sichtbarkeit: 'leitung',
    sortierung: 0,
    zugewiesene_profile_ids: [],
  }
}
