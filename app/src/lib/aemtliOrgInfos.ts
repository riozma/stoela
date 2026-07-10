import type { OrgRessource } from './orgRessourcen'

export function filterSocialMediaLogins(r: OrgRessource) {
  if (r.typ !== 'zugang') return false
  const hay = `${r.titel} ${r.url ?? ''}`.toLowerCase()
  return ['instagram', 'facebook', 'tiktok', 'social', 'twitter', 'youtube', 'linkedin'].some((k) =>
    hay.includes(k),
  )
}

export function filterInstagramLogins(r: OrgRessource) {
  if (r.typ !== 'zugang') return false
  const hay = `${r.titel} ${r.url ?? ''}`.toLowerCase()
  return hay.includes('instagram')
}
