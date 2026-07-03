const GEMINI_API_KEY = Deno.env.get('GEMINI_API_KEY')
const GEMINI_MODEL = 'gemini-2.5-flash'

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

type ChatMessage = { role: 'user' | 'assistant'; content: string }

function compact(text: string, max = 12000) {
  if (!text) return ''
  return text.length > max ? `${text.slice(0, max)}\n...[gekürzt]` : text
}

function buildPrompt(input: { question: string; context: string; history: ChatMessage[] }) {
  const history = input.history
    .slice(-8)
    .map((m) => `${m.role === 'user' ? 'User' : 'Assistant'}: ${m.content}`)
    .join('\n')

  return `Du bist ein hilfreicher Lager-Chatbot für eine Schweizer Lagerplanungs-App.
Antworte kurz, konkret und nutze PRIMÄR den gegebenen Kontext.
Wenn Daten fehlen: ehrlich sagen "im aktuellen Lagerkontext nicht vorhanden".
Kein Halluzinieren.

Lagerkontext (kompakt):
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
      headers: CORS_HEADERS,
    })
  }

  const body = await req.json()
  const question = (body?.question ?? '').toString().trim()
  const context = (body?.context ?? '').toString()
  const history = (Array.isArray(body?.history) ? body.history : []) as ChatMessage[]

  if (!question) {
    return new Response(JSON.stringify({ error: 'question fehlt' }), {
      status: 400,
      headers: CORS_HEADERS,
    })
  }

  const prompt = buildPrompt({ question, context, history })

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
      headers: CORS_HEADERS,
    })
  }

  const result = await response.json()
  const answer = result?.candidates?.[0]?.content?.parts?.[0]?.text?.toString()?.trim()
  if (!answer) {
    return new Response(JSON.stringify({ error: 'Keine Antwort erhalten', detail: result }), {
      status: 502,
      headers: CORS_HEADERS,
    })
  }

  return new Response(JSON.stringify({ answer }), {
    headers: { ...CORS_HEADERS, 'content-type': 'application/json' },
  })
})
