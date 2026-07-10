import type { OrgRessource } from './orgRessourcen'

const SOCIAL_MEDIA_KEYWORDS = [
  'instagram',
  'tiktok',
  'facebook',
  'twitter',
  'youtube',
  'linkedin',
  'snapchat',
  'pinterest',
  'threads',
  'social',
  'meta',
  'whatsapp',
  'telegram',
  'vimeo',
  'twitch',
  'x.com',
  'fb.com',
  'insta',
]

function ressourceSuchtext(r: OrgRessource) {
  return `${r.titel} ${r.url ?? ''} ${r.benutzername ?? ''} ${r.notiz ?? ''}`.toLowerCase()
}

export function istSocialMediaRessource(r: OrgRessource) {
  const hay = ressourceSuchtext(r)
  return SOCIAL_MEDIA_KEYWORDS.some((k) => hay.includes(k))
}

/** Logindaten & Links aus Verein, wenn Titel/Link/Login Social-Media-Begriffe enthält */
export function filterSocialMediaLogins(r: OrgRessource) {
  if (!istSocialMediaRessource(r)) return false
  if (r.typ === 'zugang') return true
  if (r.typ === 'link' && r.url) return true
  return false
}

export function filterInstagramLogins(r: OrgRessource) {
  const hay = ressourceSuchtext(r)
  return hay.includes('instagram') || hay.includes('insta')
}
