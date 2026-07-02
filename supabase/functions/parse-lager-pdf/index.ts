// Nimmt den rohen Text eines eCamp-"Layout 2"-PDF-Exports entgegen und lässt
// Gemini daraus ein Lager + alle Programmblöcke strukturieren. Der PDF-Export
// ist inhaltlich sehr uneinheitlich (fehlende Felder, Freitext-Spässe in
// Notizen, Zeiten über Mitternacht) -- ein Regex-Parser wäre hier zu fragil.
//
// Gemini statt Claude, weil das Volumen (paar Imports pro Jahr) locker im
// kostenlosen Gemini-Free-Tier bleibt.

const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')
const GEMINI_MODEL = 'gemini-2.5-flash'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const RESPONSE_SCHEMA = {
  type: 'OBJECT',
  properties: {
    lager: {
      type: 'OBJECT',
      properties: {
        name: { type: 'STRING', description: 'Titel des Lagers, z.B. "Stöcklilager 2026"' },
        jahr: { type: 'INTEGER' },
        ort: { type: 'STRING', nullable: true, description: 'Adresse der Gruppenunterkunft, falls vorhanden' },
        start_datum: { type: 'STRING', nullable: true, description: 'YYYY-MM-DD' },
        end_datum: { type: 'STRING', nullable: true, description: 'YYYY-MM-DD' },
      },
      required: ['name', 'jahr'],
    },
    bloecke: {
      type: 'ARRAY',
      items: {
        type: 'OBJECT',
        properties: {
          code: { type: 'STRING', enum: ['LP', 'LS', 'LA', 'ES'] },
          nummer: { type: 'STRING', nullable: true, description: 'z.B. "1.1", null bei Blöcken ohne Nummer (meist ES)' },
          titel: { type: 'STRING' },
          tag: { type: 'STRING', nullable: true, description: 'YYYY-MM-DD' },
          start_zeit: { type: 'STRING', nullable: true, description: 'ISO 8601 Datum+Zeit' },
          end_zeit: { type: 'STRING', nullable: true, description: 'ISO 8601 Datum+Zeit, kann am Folgetag liegen' },
          ort: { type: 'STRING', nullable: true },
          verantwortlich: { type: 'STRING', nullable: true, description: 'Namen, kommagetrennt' },
          geschichte: { type: 'STRING', nullable: true },
          sicherheitsueberlegungen: { type: 'STRING', nullable: true },
          programmabschnitt: {
            type: 'ARRAY',
            items: {
              type: 'OBJECT',
              properties: {
                zeit: { type: 'STRING', nullable: true },
                programm: { type: 'STRING' },
                verantwortlich: { type: 'STRING', nullable: true },
              },
              required: ['programm'],
            },
          },
          material: {
            type: 'ARRAY',
            items: {
              type: 'OBJECT',
              properties: {
                name: { type: 'STRING' },
                wer: { type: 'STRING', nullable: true },
              },
              required: ['name'],
            },
          },
          notizen: { type: 'STRING', nullable: true },
        },
        required: ['code', 'titel'],
      },
    },
  },
  required: ['lager', 'bloecke'],
}

const PROMPT_PREFIX =
  'Das ist der per PDF-Textextraktion gewonnene Inhalt eines eCamp-Lagerprogramm-Exports ' +
  '("Layout 2"). Die Reihenfolge der Wörter kann durch die Spaltenextraktion leicht durcheinander ' +
  'geraten sein (z.B. bei "Geschichte"/"Sicherheitsüberlegungen" nebeneinander). Nutze die ' +
  'Abschnittsüberschriften (Ort:, Verantwortlich:, Geschichte, Sicherheitsüberlegungen, ' +
  'Programmabschnitt, Material, Notizen) als Anker, um den "Detailprogramm: Lager"-Teil in ' +
  'einzelne Blöcke zu zerlegen. Jeder Block beginnt mit Code (LP/LS/LA/ES), optionaler Nummer, ' +
  'Titel und Datum/Zeit. Ignoriere das "Grobprogramm"-Raster und das Inhaltsverzeichnis inhaltlich, ' +
  'nutze sie höchstens um Lücken zu ergänzen. Ignoriere Scherz-/Fake-Notizen nicht, gib sie als ' +
  'notizen einfach unverändert wieder. Extrahiere jetzt vollständig:\n\n'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS })
  }
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: CORS_HEADERS })
  }
  if (!GEMINI_API_KEY) {
    return new Response(JSON.stringify({ error: 'GEMINI_API_KEY ist nicht gesetzt' }), {
      status: 500,
      headers: CORS_HEADERS,
    })
  }

  const { text } = await req.json()
  if (!text || typeof text !== 'string') {
    return new Response(JSON.stringify({ error: 'text fehlt' }), { status: 400, headers: CORS_HEADERS })
  }

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`,
    {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': GEMINI_API_KEY,
      },
      body: JSON.stringify({
        contents: [{ parts: [{ text: PROMPT_PREFIX + text }] }],
        generationConfig: {
          responseMimeType: 'application/json',
          responseSchema: RESPONSE_SCHEMA,
          maxOutputTokens: 16000,
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
  const jsonText = result.candidates?.[0]?.content?.parts?.[0]?.text
  if (!jsonText) {
    return new Response(JSON.stringify({ error: 'Kein strukturiertes Ergebnis erhalten', detail: result }), {
      status: 502,
      headers: CORS_HEADERS,
    })
  }

  return new Response(jsonText, { headers: { ...CORS_HEADERS, 'content-type': 'application/json' } })
})
