import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const url = new URL(req.url)
  const organisationId = url.searchParams.get('organisation_id')
  const lagerId = url.searchParams.get('lager_id')
  const token = url.searchParams.get('token')

  if (!token || (!organisationId && !lagerId)) {
    return new Response('Missing organisation_id or lager_id, and token', {
      status: 400,
      headers: corsHeaders,
    })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )

  const calendarHeaders = {
    ...corsHeaders,
    'Content-Type': 'text/calendar; charset=utf-8',
    'Content-Disposition': 'attachment; filename="vereinskalender.ics"',
    'Cache-Control': 'public, max-age=300',
  }

  if (organisationId) {
    const { data, error } = await supabase.rpc('get_org_kalender_ics', {
      p_organisation_id: organisationId,
      p_token: token,
    })
    if (error) {
      console.error('get_org_kalender_ics error:', error.message)
      return new Response(`Kalender-Fehler: ${error.message}`, { status: 500, headers: corsHeaders })
    }
    if (!data) {
      return new Response('Kalender nicht gefunden (Token oder Organisation ungültig)', {
        status: 404,
        headers: corsHeaders,
      })
    }
    return new Response(data, { headers: calendarHeaders })
  }

  const { data, error } = await supabase.rpc('get_lager_kalender_ics', {
    p_lager_id: lagerId,
    p_token: token,
  })

  if (error) {
    console.error('get_lager_kalender_ics error:', error.message)
    return new Response(`Kalender-Fehler: ${error.message}`, { status: 500, headers: corsHeaders })
  }
  if (!data) {
    return new Response('Kalender nicht gefunden (Token oder Lager ungültig)', {
      status: 404,
      headers: corsHeaders,
    })
  }

  return new Response(data, { headers: calendarHeaders })
})
