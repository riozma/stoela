const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')
const GEMINI_MODEL = 'gemini-3.5-flash'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ACTION_TYPES = [
  'update_lager',
  'insert_programmblock',
  'update_programmblock',
  'delete_programmblock',
  'insert_tn',
  'update_tn',
  'insert_leiter',
  'update_leiter',
  'assign_leiter_aemtli',
  'create_lager_todo',
  'update_lager_todo',
  'create_gruppe',
  'assign_gruppenmitglied',
] as const

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    summary: { type: 'STRING' },
    proposals: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          title: { type: 'STRING' },
          description: { type: 'STRING', nullable: true },
          action_type: { type: 'STRING', enum: ACTION_TYPES },
          payload: { type: 'OBJECT' },
        },
        required: ['title', 'action_type', 'payload'],
      },
    },
  },
  required: ['summary', 'proposals'],
}

interface InputDoc {
  name: string
  mimeType: string
  text?: string
  base64?: string
}

function compact(text: string, max = 60000) {
  return text.length > max ? `${text.slice(0, max)}\n...[gekürzt]` : text
}

function promptText(input: {
  prompt: string
  lager: {
    id: string
    name: string
    jahr: number | null
    status: string | null
    start_datum: string | null
    end_datum: string | null
    ort: string | null
  } | null
  docs: InputDoc[]
}) {
  const lagerMeta = input.lager
    ? `Lager-Kontext:
- id: ${input.lager.id}
- name: ${input.lager.name}
- jahr: ${input.lager.jahr ?? 'unbekannt'}
- status: ${input.lager.status ?? 'unbekannt'}
- start_datum: ${input.lager.start_datum ?? 'unbekannt'}
- end_datum: ${input.lager.end_datum ?? 'unbekannt'}
- ort: ${input.lager.ort ?? 'unbekannt'}`
    : 'Lager-Kontext: nicht verfügbar'

  const docsText = input.docs
    .filter((d) => d.text)
    .map((d, i) => `Dokument ${i + 1} (${d.name}, ${d.mimeType}):\n${compact(d.text ?? '')}`)
    .join('\n\n')

  return `Du bist ein Vorschlags-Assistent für eine Lager-Planungs-App.
Du darfst NICHT direkt "fertige Datenbankänderungen" ausführen, sondern nur Vorschläge erstellen.
Jeder Vorschlag wird später manuell bestätigt oder bearbeitet.

${lagerMeta}

Benutzerwunsch:
${input.prompt}

Unterstützte action_type (genau diese):
1) update_lager
   payload Felder: name, ort, start_datum (YYYY-MM-DD), end_datum (YYYY-MM-DD), status
2) insert_programmblock
   payload Felder: code (LP|LS|LA|ES), nummer, titel, tag (YYYY-MM-DD), start_zeit (ISO), end_zeit (ISO),
   ort, verantwortlich, geschichte, sicherheitsueberlegungen, programmabschnitt (Array), material (Array), notizen
3) update_programmblock
   payload Felder: id, sowie dieselben Felder wie insert_programmblock (nur was geändert werden soll)
4) delete_programmblock
   payload Felder: id
5) insert_tn
   payload Felder: vorname, nachname, geburtsdatum (YYYY-MM-DD), geschlecht (m|w|d), ahv_nr,
   notfallkontakt, eltern_email, rolle (TN|HL), status
6) update_tn
   payload Felder: id, vorname, nachname, geburtsdatum, geschlecht, ahv_nr, notfallkontakt, eltern_email, rolle, status
7) insert_leiter
   payload Felder: profile_id (optional UUID), vorname, nachname, email, telefon, geburtsdatum (YYYY-MM-DD),
   geschlecht (m|w|d), ahv_nr, anwesend_von, anwesend_bis, status, anmeldung_art (provisorisch|fix), bestaetigen_bis
8) update_leiter
   payload Felder: id plus optionale Felder von insert_leiter
9) assign_leiter_aemtli
   payload Felder: anmeldung_leiter_id, aemtli_id ODER aemtli_name
10) create_lager_todo
   payload Felder: titel, beschreibung, kategorie, zustaendig, aemtli_name, faellig_am, erledigt, sortierung
11) update_lager_todo
   payload Felder: id plus optionale Felder von create_lager_todo
12) create_gruppe
   payload Felder: name
13) assign_gruppenmitglied
   payload Felder: lagergruppe_id, typ (tn|leiter), anmeldung_id

Regeln:
- Erzeuge nur präzise, umsetzbare Vorschläge.
- Lieber mehrere kleine Vorschläge als einen grossen unscharfen.
- Wenn Informationen fehlen, nutze realistische Defaults und erkläre es in description.
- Für TN immer notfallkontakt + eltern_email mitdenken.
- Maximal 20 Vorschläge.

Textinhalt aus Dokumenten:
${docsText || '(kein Textdokument)'}
`
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS })
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: CORS_HEADERS })
  if (!GEMINI_API_KEY) {
    return new Response(JSON.stringify({ error: 'GEMINI_API_KEY ist nicht gesetzt' }), {
      status: 500,
      headers: CORS_HEADERS,
    })
  }

  const body = await req.json()
  const prompt = (body?.prompt ?? '').toString().trim()
  const lager = body?.lager ?? null
  const docs = (Array.isArray(body?.docs) ? body.docs : []) as InputDoc[]
  if (!prompt) return new Response(JSON.stringify({ error: 'prompt fehlt' }), { status: 400, headers: CORS_HEADERS })

  const textPart = { text: promptText({ prompt, lager, docs }) }
  const imageParts = docs
    .filter((d) => d.base64 && d.mimeType?.startsWith('image/'))
    .slice(0, 6)
    .map((d) => ({
      inlineData: { mimeType: d.mimeType, data: d.base64 as string },
    }))

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': GEMINI_API_KEY,
      },
      body: JSON.stringify({
        contents: [{ parts: [textPart, ...imageParts] }],
        generationConfig: {
          responseMimeType: 'application/json',
          responseSchema: RESPONSE_SCHEMA,
          maxOutputTokens: 8192,
        },
      }),
    },
  )

  if (!response.ok) {
    const detail = await response.text()
    return new Response(JSON.stringify({ error: 'Gemini API Fehler', detail }), {
      status: 502,
      headers: CORS_HEADERS,
    })
  }

  const result = await response.json()
  const raw = result?.candidates?.[0]?.content?.parts?.[0]?.text
  if (!raw) {
    return new Response(JSON.stringify({ error: 'Kein Gemini-Ergebnis erhalten', detail: result }), {
      status: 502,
      headers: CORS_HEADERS,
    })
  }

  let parsed: { summary?: string; proposals?: Array<{ title?: string; description?: string; action_type?: string; payload?: Record<string, unknown> }> } = {}
  try {
    parsed = JSON.parse(raw)
  } catch {
    return new Response(JSON.stringify({ error: 'Gemini JSON konnte nicht geparst werden' }), {
      status: 502,
      headers: CORS_HEADERS,
    })
  }

  const proposals = (parsed.proposals ?? [])
    .filter((p) => p?.action_type && ACTION_TYPES.includes(p.action_type as typeof ACTION_TYPES[number]))
    .slice(0, 20)
    .map((p, idx) => ({
      title: p.title?.trim() || `Vorschlag ${idx + 1}`,
      description: p.description?.trim() || null,
      action_type: p.action_type,
      payload: p.payload ?? {},
    }))

  const payload = {
    summary: parsed.summary ?? 'Gemini hat Vorschläge erstellt.',
    proposals,
  }

  return new Response(JSON.stringify(payload), {
    headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
  })
})
