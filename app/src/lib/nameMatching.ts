export interface LeiterPerson {
  id: string
  vorname: string
  nachname: string
}

export interface AemtliEintrag {
  id: string
  name: string
}

export interface NamensZuordnung {
  name: string
  leiter_id: string | null
  aemtli_id: string | null
}

export interface MaterialMitZuordnung {
  name: string
  wer: string | null
  wer_leiter_id?: string | null
  wer_aemtli_id?: string | null
}

export interface ProgrammabschnittMitZuordnung {
  zeit: string | null
  programm: string
  verantwortlich: string | null
  verantwortlich_leiter_id?: string | null
  verantwortlich_aemtli_id?: string | null
}

function normalize(text: string): string {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
}

export function splitNamen(text: string): string[] {
  return text
    .split(/[,;/]|\bund\b|\+\s*/gi)
    .map((s) => s.trim())
    .filter(Boolean)
}

function matchLeiter(name: string, leiter: LeiterPerson[]): string | null {
  const n = normalize(name)
  if (!n || !leiter.length) return null

  for (const l of leiter) {
    const full = normalize(`${l.vorname} ${l.nachname}`)
    const rev = normalize(`${l.nachname} ${l.vorname}`)
    if (n === full || n === rev) return l.id
  }

  for (const l of leiter) {
    const vor = normalize(l.vorname)
    const nach = normalize(l.nachname)
    if (vor && nach && n.includes(vor) && n.includes(nach)) return l.id
    if (nach && n === nach) {
      const gleicherNachname = leiter.filter((x) => normalize(x.nachname) === nach)
      if (gleicherNachname.length === 1) return l.id
    }
    if (vor && n === vor) {
      const gleicherVorname = leiter.filter((x) => normalize(x.vorname) === vor)
      if (gleicherVorname.length === 1) return l.id
    }
  }

  const nachnameTreffer = leiter.filter((l) => {
    const nach = normalize(l.nachname)
    return nach.length > 2 && (n === nach || n.endsWith(` ${nach}`) || n.startsWith(`${nach} `))
  })
  if (nachnameTreffer.length === 1) return nachnameTreffer[0].id

  return null
}

function matchAemtli(name: string, aemtli: AemtliEintrag[]): string | null {
  const n = normalize(name)
  if (!n || !aemtli.length) return null

  for (const a of aemtli) {
    const an = normalize(a.name)
    if (n === an) return a.id
  }
  for (const a of aemtli) {
    const an = normalize(a.name)
    if (an.length > 2 && (n.includes(an) || an.includes(n))) return a.id
  }
  return null
}

export function ordneNamenZu(
  rohName: string,
  leiter: LeiterPerson[],
  aemtli: AemtliEintrag[],
): NamensZuordnung {
  const name = rohName.trim()
  const leiterId = matchLeiter(name, leiter)
  if (leiterId) return { name, leiter_id: leiterId, aemtli_id: null }
  const aemtliId = matchAemtli(name, aemtli)
  if (aemtliId) return { name, leiter_id: null, aemtli_id: aemtliId }
  return { name, leiter_id: null, aemtli_id: null }
}

export function ordneNamenListeZu(
  text: string | null | undefined,
  leiter: LeiterPerson[],
  aemtli: AemtliEintrag[],
): NamensZuordnung[] {
  if (!text?.trim()) return []
  return splitNamen(text).map((n) => ordneNamenZu(n, leiter, aemtli))
}

export function ordneMaterialZu<T extends { name: string; wer?: string | null }>(
  items: T[],
  leiter: LeiterPerson[],
  aemtli: AemtliEintrag[],
): MaterialMitZuordnung[] {
  return items.map((m) => {
    const wer = m.wer?.trim() || null
    if (!wer) return { ...m, name: m.name, wer: null, wer_leiter_id: null, wer_aemtli_id: null }
    const z = ordneNamenZu(wer, leiter, aemtli)
    return {
      name: m.name,
      wer,
      wer_leiter_id: z.leiter_id,
      wer_aemtli_id: z.aemtli_id,
    }
  })
}

export function ordneAbschnitteZu<T extends { zeit: string | null; programm: string; verantwortlich: string | null }>(
  abschnitte: T[],
  leiter: LeiterPerson[],
  aemtli: AemtliEintrag[],
): ProgrammabschnittMitZuordnung[] {
  return abschnitte.map((a) => {
    const v = a.verantwortlich?.trim() || null
    if (!v) return { ...a, verantwortlich_leiter_id: null, verantwortlich_aemtli_id: null }
    const z = ordneNamenZu(v, leiter, aemtli)
    return {
      ...a,
      verantwortlich_leiter_id: z.leiter_id,
      verantwortlich_aemtli_id: z.aemtli_id,
    }
  })
}

export function leiterName(leiter: LeiterPerson[], id: string | null | undefined): string | null {
  if (!id) return null
  const l = leiter.find((x) => x.id === id)
  return l ? `${l.vorname} ${l.nachname}`.trim() : null
}

export function aemtliName(aemtli: AemtliEintrag[], id: string | null | undefined): string | null {
  if (!id) return null
  return aemtli.find((x) => x.id === id)?.name ?? null
}
