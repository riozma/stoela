// Versendet fällige Reminders per Resend. Kann per Cron (pg_cron / externer Trigger)
// oder manuell aus der UI aufgerufen werden.
//
// Secrets: RESEND_API_KEY, RESEND_FROM (z.B. "Stöckli Lager <lager@stoecklilager.com>")

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
const RESEND_FROM = Deno.env.get('RESEND_FROM') ?? 'Stöckli Lager <onboarding@resend.dev>'
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

interface ReminderRow {
  id: string
  lager_id: string
  titel: string
  nachricht: string | null
  faellig_am: string
  ziel_rolle: string | null
  ziel_aemtli_id: string | null
  lager: { name: string } | null
}

async function empfaengerEmails(
  supabase: ReturnType<typeof createClient>,
  reminder: ReminderRow,
): Promise<string[]> {
  const emails = new Set<string>()

  if (reminder.ziel_aemtli_id) {
    const { data: leiterRollen } = await supabase
      .from('leiter_rollen')
      .select('anmeldungen_leiter!inner(email, lager_id)')
      .eq('aemtli_id', reminder.ziel_aemtli_id)

    for (const row of leiterRollen ?? []) {
      const leiter = row.anmeldungen_leiter as { email: string; lager_id: string }
      if (leiter?.lager_id === reminder.lager_id && leiter.email) {
        emails.add(leiter.email)
      }
    }

    const { data: zuweisungen } = await supabase
      .from('aemtli_zuweisungen')
      .select('profiles!inner(email)')
      .eq('lager_id', reminder.lager_id)
      .eq('aemtli_id', reminder.ziel_aemtli_id)

    for (const row of zuweisungen ?? []) {
      const profile = row.profiles as { email: string }
      if (profile?.email) emails.add(profile.email)
    }
  }

  if (reminder.ziel_rolle === 'lagerleitung' || !reminder.ziel_aemtli_id) {
    const { data: team } = await supabase
      .from('lager_leiter')
      .select('profiles!inner(email), rolle')
      .eq('lager_id', reminder.lager_id)
      .eq('status', 'bestaetigt')

    for (const row of team ?? []) {
      const profile = row.profiles as { email: string }
      if (!profile?.email) continue
      if (!reminder.ziel_rolle || row.rolle === reminder.ziel_rolle) {
        emails.add(profile.email)
      }
    }
  }

  return [...emails]
}

async function sendViaResend(to: string[], subject: string, html: string) {
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from: RESEND_FROM, to, subject, html }),
  })
  if (!response.ok) {
    const detail = await response.text()
    const ohneDomain = detail.includes('resend.dev') || response.status === 403
    throw new Error(
      ohneDomain
        ? 'Resend Test-Modus: mit onboarding@resend.dev gehen Mails nur an deine Resend-Account-E-Mail. Für echte Empfänger brauchst du eine verifizierte Domain.'
        : `Resend Fehler: ${detail}`,
    )
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: CORS_HEADERS })
  }
  if (!RESEND_API_KEY) {
    return new Response(JSON.stringify({ error: 'RESEND_API_KEY ist nicht gesetzt' }), {
      status: 500,
      headers: CORS_HEADERS,
    })
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  const body = await req.json().catch(() => ({}))
  const einzelReminderId = body.reminder_id as string | undefined

  let query = supabase
    .from('reminders')
    .select('id, lager_id, titel, nachricht, faellig_am, ziel_rolle, ziel_aemtli_id, lager(name)')
    .eq('status', 'geplant')

  if (einzelReminderId) {
    query = query.eq('id', einzelReminderId)
  } else {
    query = query.lte('faellig_am', new Date().toISOString())
  }

  const { data: reminders, error: fetchError } = await query
  if (fetchError) {
    return new Response(JSON.stringify({ error: fetchError.message }), {
      status: 500,
      headers: CORS_HEADERS,
    })
  }

  const ergebnis: { id: string; status: string; detail?: string }[] = []

  for (const reminder of (reminders ?? []) as ReminderRow[]) {
    try {
      const empfaenger = await empfaengerEmails(supabase, reminder)
      if (!empfaenger.length) {
        await supabase
          .from('reminders')
          .update({ status: 'fehlgeschlagen' })
          .eq('id', reminder.id)
        ergebnis.push({ id: reminder.id, status: 'fehlgeschlagen', detail: 'Keine Empfänger gefunden' })
        continue
      }

      const lagerName = reminder.lager?.name ?? 'Lager'
      const subject = `[${lagerName}] ${reminder.titel}`
      const html = `
        <h2>${reminder.titel}</h2>
        <p>${reminder.nachricht ?? ''}</p>
        <p style="color:#666;font-size:0.85em">Stöckli Lager App · ${lagerName}</p>
      `

      await sendViaResend(empfaenger, subject, html)

      await supabase
        .from('reminders')
        .update({ status: 'gesendet', gesendet_am: new Date().toISOString() })
        .eq('id', reminder.id)

      ergebnis.push({ id: reminder.id, status: 'gesendet' })
    } catch (e) {
      await supabase.from('reminders').update({ status: 'fehlgeschlagen' }).eq('id', reminder.id)
      ergebnis.push({
        id: reminder.id,
        status: 'fehlgeschlagen',
        detail: e instanceof Error ? e.message : 'Unbekannter Fehler',
      })
    }
  }

  return new Response(JSON.stringify({ gesendet: ergebnis.length, ergebnis }), {
    headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
  })
})
