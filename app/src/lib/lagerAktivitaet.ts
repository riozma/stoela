import { supabase } from '../supabaseClient'

export interface LagerAenderung {
  zeit: string
  beschreibung: string
  kategorie: string | null
}

export async function ladeLetzteAenderungen(lagerId: string, limit = 10): Promise<LagerAenderung[]> {
  const { data, error } = await supabase.rpc('list_lager_letzte_aenderungen', {
    p_lager_id: lagerId,
    p_limit: limit,
  })
  if (error) return []
  return (data ?? []) as LagerAenderung[]
}

export async function logLagerAktivitaet(lagerId: string, beschreibung: string, kategorie?: string) {
  await supabase.rpc('log_lager_aktivitaet', {
    p_lager_id: lagerId,
    p_beschreibung: beschreibung,
    p_kategorie: kategorie ?? null,
  })
}
