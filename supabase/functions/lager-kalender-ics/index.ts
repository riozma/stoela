import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const url = new URL(req.url)
  const lagerId = url.searchParams.get('lager_id')
  const token = url.searchParams.get('token')

  if (!lagerId || !token) {
    return new Response('Missing lager_id or token', { status: 400 })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )

  const { data, error } = await supabase.rpc('get_lager_kalender_ics', {
    p_lager_id: lagerId,
    p_token: token,
  })

  if (error || !data) {
    return new Response('Not found', { status: 404 })
  }

  return new Response(data, {
    headers: {
      'Content-Type': 'text/calendar; charset=utf-8',
      'Content-Disposition': 'attachment; filename="lager.ics"',
    },
  })
})
