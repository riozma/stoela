import type { User } from '@supabase/supabase-js'
import { supabase } from '../supabaseClient'

export interface ProfilNamen {
  vorname: string
  nachname: string
  vollstaendig: boolean
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

export function profilNamenVollstaendig(vorname: string | null | undefined, nachname: string | null | undefined) {
  return !!String(vorname ?? '').trim() && !!String(nachname ?? '').trim()
}

export async function ladeUndSyncProfilNamen(user: User): Promise<ProfilNamen> {
  const google = namenAusUser(user)

  const { data: profil } = await supabase
    .from('profiles')
    .select('vorname, nachname')
    .eq('id', user.id)
    .maybeSingle()

  const vorname = String(profil?.vorname ?? '').trim() || google.vorname
  const nachname = String(profil?.nachname ?? '').trim() || google.nachname

  const fehltInDb = !profilNamenVollstaendig(profil?.vorname, profil?.nachname)
  const googleHatNamen = profilNamenVollstaendig(google.vorname, google.nachname)

  if (fehltInDb && googleHatNamen) {
    await supabase
      .from('profiles')
      .update({
        vorname: vorname || null,
        nachname: nachname || null,
      })
      .eq('id', user.id)
  }

  return {
    vorname,
    nachname,
    vollstaendig: profilNamenVollstaendig(vorname, nachname),
  }
}

export async function speichereProfilNamen(userId: string, vorname: string, nachname: string) {
  const v = vorname.trim()
  const n = nachname.trim()
  if (!v || !n) throw new Error('Vorname und Nachname sind Pflicht.')
  const { error } = await supabase
    .from('profiles')
    .update({ vorname: v, nachname: n })
    .eq('id', userId)
  if (error) throw error
  return { vorname: v, nachname: n }
}
