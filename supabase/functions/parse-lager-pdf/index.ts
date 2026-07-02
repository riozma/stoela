// Nimmt den rohen Text eines eCamp-"Layout 2"-PDF-Exports entgegen und lässt
// Claude daraus ein Lager + alle Programmblöcke strukturieren. Der PDF-Export
// ist inhaltlich sehr uneinheitlich (fehlende Felder, Freitext-Spässe in
// Notizen, Zeiten über Mitternacht) -- ein Regex-Parser wäre hier zu fragil.

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY')

const TOOL_SCHEMA = {
  name: 'lager_extrahieren',
  description: 'Extrahiert ein Lager mit allen Programmblöcken aus eCamp-PDF-Text.',
  input_schema: {
    type: 'object',
    properties: {
      lager: {
        type: 'object',
        properties: {
          name: { type: 'string', description: 'Titel des Lagers, z.B. "Stöcklilager 2026"' },
          jahr: { type: 'integer' },
          ort: { type: 'string', description: 'Adresse der Gruppenunterkunft, falls vorhanden' },
          start_datum: { type: 'string', description: 'YYYY-MM-DD' },
          end_datum: { type: 'string', description: 'YYYY-MM-DD' },
        },
        required: ['name', 'jahr'],
      },
      bloecke: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            code: { type: 'string', enum: ['LP', 'LS', 'LA', 'ES'] },
            nummer: { type: ['string', 'null'], description: 'z.B. "1.1", null bei Blöcken ohne Nummer (meist ES)' },
            titel: { type: 'string' },
            tag: { type: ['string', 'null'], description: 'YYYY-MM-DD' },
            start_zeit: { type: ['string', 'null'], description: 'ISO 8601 Datum+Zeit' },
            end_zeit: { type: ['string', 'null'], description: 'ISO 8601 Datum+Zeit, kann am Folgetag liegen' },
            ort: { type: ['string', 'null'] },
            verantwortlich: { type: ['string', 'null'], description: 'Namen, kommagetrennt' },
            geschichte: { type: ['string', 'null'] },
            sicherheitsueberlegungen: { type: ['string', 'null'] },
            programmabschnitt: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  zeit: { type: ['string', 'null'] },
                  programm: { type: 'string' },
                  verantwortlich: { type: ['string', 'null'] },
                },
                required: ['programm'],
              },
            },
            material: {
              type: 'array',
              items: {
                type: 'object',
                properties: {
                  name: { type: 'string' },
                  wer: { type: ['string', 'null'] },
                },
                required: ['name'],
              },
            },
            notizen: { type: ['string', 'null'] },
          },
          required: ['code', 'titel'],
        },
      },
    },
    required: ['lager', 'bloecke'],
  },
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 })
  }
  if (!ANTHROPIC_API_KEY) {
    return new Response(JSON.stringify({ error: 'ANTHROPIC_API_KEY ist nicht gesetzt' }), { status: 500 })
  }

  const { text } = await req.json()
  if (!text || typeof text !== 'string') {
    return new Response(JSON.stringify({ error: 'text fehlt' }), { status: 400 })
  }

  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-api-key': ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: 'claude-sonnet-5',
      max_tokens: 16000,
      tools: [TOOL_SCHEMA],
      tool_choice: { type: 'tool', name: 'lager_extrahieren' },
      messages: [
        {
          role: 'user',
          content:
            'Das ist der per PDF-Textextraktion gewonnene Inhalt eines eCamp-Lagerprogramm-Exports ' +
            '("Layout 2"). Die Reihenfolge der Wörter kann durch die Spaltenextraktion leicht durcheinander ' +
            'geraten sein (z.B. bei "Geschichte"/"Sicherheitsüberlegungen" nebeneinander). Nutze die ' +
            'Abschnittsüberschriften (Ort:, Verantwortlich:, Geschichte, Sicherheitsüberlegungen, ' +
            'Programmabschnitt, Material, Notizen) als Anker, um den "Detailprogramm: Lager"-Teil in ' +
            'einzelne Blöcke zu zerlegen. Jeder Block beginnt mit Code (LP/LS/LA/ES), optionaler Nummer, ' +
            'Titel und Datum/Zeit. Ignoriere das "Grobprogramm"-Raster und das Inhaltsverzeichnis inhaltlich, ' +
            'nutze sie höchstens um Lücken zu ergänzen. Ignoriere Scherz-/Fake-Notizen nicht, gib sie als ' +
            'notizen einfach unverändert wieder. Extrahiere jetzt vollständig:\n\n' +
            text,
        },
      ],
    }),
  })

  if (!response.ok) {
    const detail = await response.text()
    return new Response(JSON.stringify({ error: 'Anthropic API Fehler', detail }), { status: 502 })
  }

  const result = await response.json()
  const toolUse = result.content?.find((block: any) => block.type === 'tool_use')
  if (!toolUse) {
    return new Response(JSON.stringify({ error: 'Kein strukturiertes Ergebnis erhalten' }), { status: 502 })
  }

  return new Response(JSON.stringify(toolUse.input), {
    headers: { 'content-type': 'application/json' },
  })
})
