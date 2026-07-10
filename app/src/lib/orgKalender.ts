export function orgKalenderHttpsUrl(organisationId: string, token: string) {
  const base = String(import.meta.env.VITE_SUPABASE_URL ?? '').replace(/\/$/, '')
  return `${base}/functions/v1/lager-kalender-ics?organisation_id=${organisationId}&token=${token}`
}

export function orgKalenderWebcalUrl(organisationId: string, token: string) {
  return orgKalenderHttpsUrl(organisationId, token).replace(/^https:\/\//, 'webcal://')
}
