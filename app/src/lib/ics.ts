interface IcsBlock {
  titel: string
  tag: string | null
  start_zeit: string | null
  end_zeit: string | null
  ort: string | null
  code: string
  nummer: string | null
  verantwortlich: string | null
}

function pad(n: number) {
  return String(n).padStart(2, '0')
}

function toIcsDate(iso: string): string {
  const d = new Date(iso)
  return (
    d.getUTCFullYear() +
    pad(d.getUTCMonth() + 1) +
    pad(d.getUTCDate()) +
    'T' +
    pad(d.getUTCHours()) +
    pad(d.getUTCMinutes()) +
    pad(d.getUTCSeconds()) +
    'Z'
  )
}

function toIcsDateOnly(dateStr: string): string {
  return dateStr.replace(/-/g, '')
}

function escapeIcs(text: string) {
  return text.replace(/\\/g, '\\\\').replace(/;/g, '\\;').replace(/,/g, '\\,').replace(/\n/g, '\\n')
}

function uid(prefix: string, index: number) {
  return `${prefix}-${index}@stoecklilager.com`
}

export function generateIcs(
  lagerName: string,
  bloecke: IcsBlock[],
  zeitraum?: { von: string; bis: string },
): string {
  const filtered = bloecke.filter((b) => {
    if (!b.tag) return false
    if (!zeitraum) return true
    return b.tag >= zeitraum.von && b.tag <= zeitraum.bis
  })

  const events = filtered.map((b, i) => {
    const summary = escapeIcs(`${b.code}${b.nummer ? ' ' + b.nummer : ''} ${b.titel}`)
    const location = b.ort ? escapeIcs(b.ort) : ''
    const description = b.verantwortlich ? escapeIcs(`Verantwortlich: ${b.verantwortlich}`) : ''

    let dtStart: string
    let dtEnd: string

    if (b.start_zeit && b.end_zeit) {
      dtStart = toIcsDate(b.start_zeit)
      dtEnd = toIcsDate(b.end_zeit)
    } else if (b.tag) {
      dtStart = `;VALUE=DATE:${toIcsDateOnly(b.tag)}`
      dtEnd = `;VALUE=DATE:${toIcsDateOnly(b.tag)}`
    } else {
      return ''
    }

    const startLine = b.start_zeit ? `DTSTART:${dtStart}` : `DTSTART${dtStart}`
    const endLine = b.end_zeit ? `DTEND:${dtEnd}` : `DTEND${dtEnd}`

    return [
      'BEGIN:VEVENT',
      `UID:${uid(lagerName, i)}`,
      startLine,
      endLine,
      `SUMMARY:${summary}`,
      location ? `LOCATION:${location}` : '',
      description ? `DESCRIPTION:${description}` : '',
      'END:VEVENT',
    ]
      .filter(Boolean)
      .join('\r\n')
  })

  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Stöckli Lager//DE',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    `X-WR-CALNAME:${escapeIcs(lagerName)}`,
    ...events,
    'END:VCALENDAR',
  ].join('\r\n')
}

export function downloadIcs(filename: string, content: string) {
  const blob = new Blob([content], { type: 'text/calendar;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  URL.revokeObjectURL(url)
}
