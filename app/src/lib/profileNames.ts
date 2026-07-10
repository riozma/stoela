import type { User } from '@supabase/supabase-js'
import { supabase } from '../supabaseClient'

export interface ProfilLeiterDaten {
  vorname: string
  nachname: string
  geburtsdatum: string
  geschlecht: string
  ahv_nr: string
  telefon: string
  email: string
  vollstaendig: boolean
  namenVollstaendig: boolean
  stammdatenVollstaendig: boolean
}

export function namenAusUser(user: User | null | undefined): { vorname: string; nachname: string } {
  if (!user) return { vorname: '', nachname: '' }
  const meta = user.user_metadata ?? {}
  let vorname = String(meta.given_name ?? meta.vorname ?? '').trim()
  let nachname = String(meta.family_name ?? meta.nachname ?? '').trim()
  if (!vorname && !nachname) {
    const full = String(meta.full_name ?? meta.name ?? '').trim()
    if (full) {
      const teile = full.split(/\s+/).filter(Boolean)
      if (teile.length >= 2) {
        vorname = teile[0]
        nachname = teile.slice(1).join(' ')
      } else if (teile.length === 1) {
        vorname = teile[0]
      }
    }
  }
  return { vorname, nachname }
}

function feld(v: string | null | undefined) {
  return String(v ?? '').trim()
}

export function profilNamenVollstaendig(vorname: string | null | undefined, nachname: string | null | undefined) {
  return !!feld(vorname) && !!feld(nachname)
}

export function profilStammdatenVollstaendig(p: {
  vorname?: string | null
  nachname?: string | null
  geburtsdatum?: string | null
  geschlecht?: string | null
  ahv_nr?: string | null
}) {
  return profilNamenVollstaendig(p.vorname, p.nachname) && !!feld(p.geburtsdatum) && !!feld(p.geschlecht)
}

export async function ladeProfilLeiterDaten(user: User): Promise<ProfilLeiterDaten> {
  const google = namenAusUser(user)
  const { data: profil } = await supabase
    .from('profiles')
    .select('vorname, nachname, geburtsdatum, geschlecht, ahv_nr, telefon, email')
    .eq('id', user.id)
    .maybeSingle()

  const vorname = feld(profil?.vorname) || google.vorname
  const nachname = feld(profil?.nachname) || google.nachname
  const geburtsdatum = feld(profil?.geburtsdatum)
  const geschlecht = feld(profil?.geschlecht)
  const ahv_nr = feld(profil?.ahv_nr)
  const telefon = feld(profil?.telefon)
  const email = feld(profil?.email) || feld(user.email)

  const fehltInDb = !profilStammdatenVollstaendig({ vorname: profil?.vorname, nachname: profil?.nachname, geburtsdatum: profil?.geburtsdatum, geschlecht: profil?.geschlecht })
  const googleHatNamen = profilNamenVollstaendig(google.vorname, google.nachname)

  if (fehltInDb && googleHatNamen && !feld(profil?.vorname)) {
    await supabase.from('profiles').update({ vorname, nachname }).eq('id', user.id)
  }

  return {
    vorname,
    nachname,
    geburtsdatum,
    geschlecht,
    ahv_nr,
    telefon,
    email,
    namenVollstaendig: profilNamenVollstaendig(vorname, nachname),
    stammdatenVollstaendig: profilStammdatenVollstaendig({ vorname, nachname, geburtsdatum, geschlecht }),
    vollstaendig: profilStammdatenVollstaendig({ vorname, nachname, geburtsdatum, geschlecht }) && !!feld(ahv_nr),
  }
}

export async function speichereProfilLeiterDaten(
  userId: string,
  daten: Partial<ProfilLeiterDaten>,
) {
  const payload: Record<string, string | null> = {}
  if (daten.vorname?.trim()) payload.vorname = daten.vorname.trim()
  if (daten.nachname?.trim()) payload.nachname = daten.nachname.trim()
  if (daten.geburtsdatum?.trim()) payload.geburtsdatum = daten.geburtsdatum.trim()
  if (daten.geschlecht?.trim()) payload.geschlecht = daten.geschlecht.trim()
  if (daten.ahv_nr?.trim()) payload.ahv_nr = daten.ahv_nr.trim()
  if (daten.telefon?.trim()) payload.telefon = daten.telefon.trim()
  if (!Object.keys(payload).length) return
  const { error } = await supabase.from('profiles').update(payload).eq('id', userId)
  if (error) throw error
}
