import { supabase } from '../supabaseClient'
import {
  type AemtliEintrag,
  type LeiterPerson,
  ordneAbschnitteZu,
  ordneMaterialZu,
  ordneNamenListeZu,
} from './nameMatching'

export async function ladeLeiterFuerMatching(lagerId: string): Promise<LeiterPerson[]> {
  const { data } = await supabase
    .from('anmeldungen_leiter')
    .select('id, vorname, nachname')
    .eq('lager_id', lagerId)
    .in('status', ['bestaetigt', 'angemeldet'])
  return data ?? []
}

export async function ladeAemtliFuerMatching(): Promise<AemtliEintrag[]> {
  const { data } = await supabase.from('aemtli').select('id, name').eq('aktiv', true).order('name')
  return data ?? []
}

export async function synchronisiereProgrammZuordnungen(lagerId: string): Promise<number> {
  const [leiter, aemtli, { data: bloecke }] = await Promise.all([
    ladeLeiterFuerMatching(lagerId),
    ladeAemtliFuerMatching(),
    supabase
      .from('programmbloecke')
      .select('id, verantwortlich, programmabschnitt, material')
      .eq('lager_id', lagerId),
  ])

  if (!bloecke?.length) return 0

  let aktualisiert = 0
  for (const block of bloecke) {
    const zuordnungen = ordneNamenListeZu(block.verantwortlich, leiter, aemtli)
    const programmabschnitt = ordneAbschnitteZu(block.programmabschnitt ?? [], leiter, aemtli)
    const material = ordneMaterialZu(block.material ?? [], leiter, aemtli)

    const { error } = await supabase
      .from('programmbloecke')
      .update({
        verantwortlich_zuordnungen: zuordnungen,
        programmabschnitt,
        material,
      })
      .eq('id', block.id)

    if (!error) aktualisiert++
  }

  return aktualisiert
}
