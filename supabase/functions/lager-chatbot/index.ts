import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')
const GEMINI_MODEL = 'gemini-2.5-flash'
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

type ChatMessage = { role: 'user' | 'assistant'; content: string }
type ContextTopic =
  | 'basis'
  | 'todos'
  | 'programm'
  | 'teilnehmer'
  | 'gruppen'
  | 'leiter'
  | 'aemtli'
  | 'vorweekend'
  | 'einkauf'
  | 'reminders'

function compact(text: string, max = 14000) {
  if (!text) return ''
  return text.length > max ? `${text.slice(0, max)}\n...[gekürzt]` : text
}

function detectTopics(question: string): Set<ContextTopic> {
  const q = question.toLowerCase()
  const topics = new Set<ContextTopic>(['basis'])

  if (/todo|aufgabe|fällig|deadline|erledig|offen/.test(q)) topics.add('todos')
  if (/programm|block|morgen|heute|zeitplan|ablauf|anreise|abreise|uhr|zeit/.test(q)) topics.add('programm')
  if (/teilnehmer|tn\b|kinder|anmeld|medikament|gesundheit|allerg/.test(q)) topics.add('teilnehmer')
  if (/gruppe|gruppen|zelt|patrouille/.test(q)) topics.add('gruppen')
  if (/leiter|leitende|team|personal|anwesend/.test(q)) topics.add('leiter')
  if (/ämtli|aemtli|rolle|küche|kueche|finanz|material|werbung|sponsor/.test(q)) topics.add('aemtli')
  if (/vorweekend|wochenende/.test(q)) topics.add('vorweekend')
  if (/einkauf|material|liste|bestell/.test(q)) topics.add('einkauf')
  if (/reminder|erinnerung|mail/.test(q)) topics.add('reminders')

  if (topics.size === 1) {
    topics.add('todos')
    topics.add('programm')
  }

  return topics
}

function topicLabel(topic: ContextTopic) {
  const map: Record<ContextTopic, string> = {
    basis: 'Lager-Infos',
    todos: 'Todos',
    programm: 'Programm',
    teilnehmer: 'Teilnehmer',
    gruppen: 'Gruppen',
    leiter: 'Leiter',
    aemtli: 'Ämtli',
    vorweekend: 'Vorweekend',
    einkauf: 'Einkauf',
    reminders: 'Reminders',
  }
  return map[topic]
}

async function buildDynamicContext(
  supabase: ReturnType<typeof createClient>,
  lagerId: string,
  question: string,
) {
  const topics = detectTopics(question)
  const sections: string[] = []
  const heute = new Date().toISOString().slice(0, 10)

  if (topics.has('basis')) {
    const { data: lager } = await supabase
      .from('lager')
      .select('name, jahr, status, ort, start_datum, end_datum, vorweekend_start, vorweekend_ende, motto')
      .eq('id', lagerId)
      .maybeSingle()

    if (lager) {
      sections.push([
        '## Lager-Basis',
        `Name: ${lager.name} (${lager.jahr})`,
        `Status: ${lager.status}`,
        `Ort: ${lager.ort ?? '–'}`,
        `Zeitraum: ${lager.start_datum ?? '–'} bis ${lager.end_datum ?? '–'}`,
        lager.motto ? `Motto: ${lager.motto}` : null,
        lager.vorweekend_start ? `Vorweekend: ${lager.vorweekend_start} – ${lager.vorweekend_ende ?? '?'}` : null,
      ].filter(Boolean).join('\n'))
    }
  }

  if (topics.has('todos')) {
    const { data } = await supabase
      .from('lager_todos')
      .select('titel, faellig_am, kategorie, zustaendig, aemtli_name, erledigt')
      .eq('lager_id', lagerId)
      .order('faellig_am', { ascending: true, nullsFirst: false })
      .limit(20)

    const offen = (data ?? []).filter((t) => !t.erledigt)
    const lines = offen.map((t) => {
      const due = t.faellig_am ? ` bis ${t.faellig_am}` : ''
      const aemtli = t.aemtli_name ? ` (${t.aemtli_name})` : ''
      return `- ${t.titel}${aemtli}${due} [${t.kategorie}/${t.zustaendig}]`
    })
    sections.push(`## Offene Todos (${offen.length})\n${lines.length ? lines.join('\n') : '- keine'}`)
  }

  if (topics.has('programm')) {
    const { data } = await supabase
      .from('programmbloecke')
      .select('code, titel, tag, start_zeit, end_zeit, verantwortlich, ort, block_typ')
      .eq('lager_id', lagerId)
      .gte('tag', heute)
      .order('tag', { ascending: true })
      .order('start_zeit', { ascending: true, nullsFirst: true })
      .limit(15)

    const lines = (data ?? []).map((b) => {
      const zeit = b.start_zeit ? ` ${b.start_zeit.slice(0, 5)}-${b.end_zeit ? b.end_zeit.slice(0, 5) : '?'}` : ''
      return `- ${b.tag ?? '?'}${zeit} [${b.code}] ${b.titel} (${b.block_typ})${b.verantwortlich ? ` – ${b.verantwortlich}` : ''}${b.ort ? ` @ ${b.ort}` : ''}`
    })
    sections.push(`## Kommendes Programm\n${lines.length ? lines.join('\n') : '- keine kommenden Blöcke'}`)
  }

  if (topics.has('teilnehmer')) {
    const [{ count }, { data: tn }] = await Promise.all([
      supabase.from('anmeldungen_tn').select('*', { count: 'exact', head: true }).eq('lager_id', lagerId),
      supabase
        .from('anmeldungen_tn')
        .select('vorname, nachname, status, rolle, geschlecht, geburtsdatum, medikamente, gesundheit_bemerkungen')
        .eq('lager_id', lagerId)
        .order('nachname')
        .limit(25),
    ])

    const statusCount = new Map<string, number>()
    for (const row of tn ?? []) {
      statusCount.set(row.status, (statusCount.get(row.status) ?? 0) + 1)
    }
    const statusLine = [...statusCount.entries()].map(([s, n]) => `${s}: ${n}`).join(', ')
    const lines = (tn ?? []).slice(0, 12).map((t) => {
      const extra = [t.rolle !== 'TN' ? t.rolle : null, t.medikamente ? 'Medikamente' : null].filter(Boolean).join(', ')
      return `- ${t.vorname} ${t.nachname} (${t.status}${extra ? `, ${extra}` : ''})`
    })
    sections.push([
      `## Teilnehmer (${count ?? 0} total)`,
      statusLine ? `Status: ${statusLine}` : null,
      lines.length ? lines.join('\n') : '- keine Details',
      (tn ?? []).length > 12 ? `… und ${(tn ?? []).length - 12} weitere` : null,
    ].filter(Boolean).join('\n'))
  }

  if (topics.has('gruppen')) {
    const { data: gruppen } = await supabase
      .from('lagergruppen')
      .select('id, name, farbe, max_groesse')
      .eq('lager_id', lagerId)
      .order('name')

    const gruppenLines: string[] = []
    for (const g of gruppen ?? []) {
      const { count } = await supabase
        .from('gruppen_mitglieder')
        .select('*', { count: 'exact', head: true })
        .eq('lagergruppe_id', g.id)
      gruppenLines.push(`- ${g.name}: ${count ?? 0} Mitglieder${g.max_groesse ? ` (max ${g.max_groesse})` : ''}`)
    }
    sections.push(`## Gruppen\n${gruppenLines.length ? gruppenLines.join('\n') : '- keine Gruppen'}`)
  }

  if (topics.has('leiter')) {
    const { data, count } = await supabase
      .from('anmeldungen_leiter')
      .select('vorname, nachname, email, status, anmeldung_art, anwesend_von, anwesend_bis', { count: 'exact' })
      .eq('lager_id', lagerId)
      .in('status', ['angemeldet', 'bestaetigt'])
      .order('nachname')
      .limit(20)

    const lines = (data ?? []).map((l) => {
      const zeitraum = l.anwesend_von ? ` ${l.anwesend_von}–${l.anwesend_bis ?? '?'}` : ''
      return `- ${l.vorname} ${l.nachname} (${l.status}, ${l.anmeldung_art})${zeitraum}`
    })
    sections.push(`## Leiter (${count ?? 0})\n${lines.length ? lines.join('\n') : '- keine'}`)
  }

  if (topics.has('aemtli')) {
    const { data: leiter } = await supabase
      .from('anmeldungen_leiter')
      .select('id, vorname, nachname')
      .eq('lager_id', lagerId)

    const leiterIds = (leiter ?? []).map((l) => l.id)
    const leiterMap = new Map((leiter ?? []).map((l) => [l.id, `${l.vorname} ${l.nachname}`]))

    let lines: string[] = []
    if (leiterIds.length) {
      const { data: rollen } = await supabase
        .from('leiter_rollen')
        .select('anmeldung_leiter_id, aemtli!inner(name)')
        .in('anmeldung_leiter_id', leiterIds)

      lines = (rollen ?? []).map((r) => {
        const name = leiterMap.get(r.anmeldung_leiter_id) ?? 'Unbekannt'
        const aemtli = r.aemtli as { name: string }
        return `- ${name}: ${aemtli.name}`
      })
    }
    sections.push(`## Ämtli-Zuweisungen\n${lines.length ? lines.join('\n') : '- keine Zuweisungen'}`)
  }

  if (topics.has('vorweekend')) {
    const [{ data: prog }, { data: anm }] = await Promise.all([
      supabase
        .from('vorweekend_programm')
        .select('tag, start_zeit, end_zeit, titel, ort')
        .eq('lager_id', lagerId)
        .order('tag')
        .limit(12),
      supabase
        .from('vorweekend_anmeldungen')
        .select('vorname, nachname')
        .eq('lager_id', lagerId)
        .limit(15),
    ])

    const progLines = (prog ?? []).map((p) =>
      `- ${p.tag} ${p.start_zeit?.slice(0, 5) ?? ''}: ${p.titel}${p.ort ? ` @ ${p.ort}` : ''}`
    )
    const anmLines = (anm ?? []).map((a) => `- ${a.vorname} ${a.nachname}`)
    sections.push([
      '## Vorweekend',
      `Programm (${prog?.length ?? 0}):`,
      progLines.length ? progLines.join('\n') : '- kein Programm',
      `Anmeldungen (${anm?.length ?? 0}):`,
      anmLines.length ? anmLines.join('\n') : '- keine',
    ].join('\n'))
  }

  if (topics.has('einkauf')) {
    const { data } = await supabase
      .from('einkaufsliste_items')
      .select('name, menge, einheit, kategorie, erledigt, bereich')
      .eq('lager_id', lagerId)
      .eq('erledigt', false)
      .order('kategorie')
      .limit(20)

    const lines = (data ?? []).map((i) =>
      `- ${i.name}: ${i.menge ?? '?'} ${i.einheit ?? ''} [${i.bereich ?? 'lager'}]`
    )
    sections.push(`## Einkaufsliste\n${lines.length ? lines.join('\n') : '- leer'}`)
  }

  if (topics.has('reminders')) {
    const { data } = await supabase
      .from('reminders')
      .select('titel, faellig_am, ziel_rolle, gesendet_am')
      .eq('lager_id', lagerId)
      .order('faellig_am', { ascending: true })
      .limit(10)

    const lines = (data ?? []).map((r) =>
      `- ${r.titel} (${r.faellig_am})${r.gesendet_am ? ' ✓gesendet' : ''}${r.ziel_rolle ? ` → ${r.ziel_rolle}` : ''}`
    )
    sections.push(`## Reminders\n${lines.length ? lines.join('\n') : '- keine'}`)
  }

  return {
    context: sections.join('\n\n'),
    topics: [...topics].map(topicLabel),
  }
}

function buildPrompt(input: {
  question: string
  context: string
  topics: string[]
  history: ChatMessage[]
}) {
  const history = input.history
    .slice(-8)
    .map((m) => `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`)
    .join('\n')

  return `Du bist ein hilfreicher Lager-Chatbot für eine Schweizer Lagerplanungs-App.
Antworte kurz, konkret und nutze PRIMÄR den gegebenen Kontext.
Wenn Daten fehlen: ehrlich sagen "im aktuellen Lagerkontext nicht vorhanden".
Kein Halluzinieren. Antworte auf Deutsch.

Für diese Frage wurden folgende Kontextbereiche aus der Datenbank geladen: ${input.topics.join(', ')}.

Lagerkontext:
${compact(input.context)}

Letzter Verlauf:
${history || '(kein Verlauf)'}

Neue Frage:
${input.question}
`
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS })
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: CORS_HEADERS })

  if (!GEMINI_API_KEY) {
    return new Response(JSON.stringify({ error: 'GEMINI_API_KEY ist nicht gesetzt' }), {
      status: 500,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
    })
  }

  if (!SUPABASE_SERVICE_ROLE_KEY) {
    return new Response(JSON.stringify({ error: 'SUPABASE_SERVICE_ROLE_KEY fehlt' }), {
      status: 500,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
    })
  }

  const body = await req.json()
  const question = (body?.question ?? '').toString().trim()
  const lagerId = (body?.lagerId ?? body?.lager_id ?? '').toString().trim()
  const history = (Array.isArray(body?.history) ? body.history : []) as ChatMessage[]

  if (!question) {
    return new Response(JSON.stringify({ error: 'question fehlt' }), {
      status: 400,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
    })
  }

  if (!lagerId) {
    return new Response(JSON.stringify({ error: 'lagerId fehlt' }), {
      status: 400,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
    })
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  const { context, topics } = await buildDynamicContext(supabase, lagerId, question)
  const prompt = buildPrompt({ question, context, topics, history })

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': GEMINI_API_KEY,
      },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          maxOutputTokens: 1024,
          temperature: 0.2,
        },
      }),
    },
  )

  if (!response.ok) {
    const detail = await response.text()
    return new Response(JSON.stringify({ error: 'Gemini API Fehler', detail }), {
      status: 502,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
    })
  }

  const result = await response.json()
  const answer = result?.candidates?.[0]?.content?.parts?.[0]?.text?.toString()?.trim()
  if (!answer) {
    return new Response(JSON.stringify({ error: 'Keine Antwort erhalten', detail: result }), {
      status: 502,
      headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
    })
  }

  return new Response(JSON.stringify({ answer, topics, contextPreview: compact(context, 1200) }), {
    headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
  })
})
