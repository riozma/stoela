# Supabase deployen (neue Organisation / Projekt)

## Option A: Supabase CLI (empfohlen)

1. Access Token erstellen: https://supabase.com/dashboard/account/tokens
2. Project Ref kopieren: Dashboard → Project Settings → General

```bash
export SUPABASE_ACCESS_TOKEN=sbp_...
export PROJECT_REF=dein-project-ref

npx supabase link --project-ref "$PROJECT_REF"
npx supabase db push
npx supabase functions deploy parse-lager-pdf
npx supabase functions deploy send-reminder

# Secrets
npx supabase secrets set \
  GEMINI_API_KEY=... \
  RESEND_API_KEY=re_... \
  RESEND_FROM="Stöckli Lager <onboarding@resend.dev>"
```

## Option B: SQL Editor (falls CLI nicht geht)

Im Supabase Dashboard → SQL → New query → Inhalt von `apply-all.sql` einfügen und ausführen.

Edge Functions danach trotzdem per CLI deployen.

## Resend ohne eigene Domain

Solange keine Domain verifiziert ist:

- `RESEND_FROM` = `Stöckli Lager <onboarding@resend.dev>` (oder weglassen, das ist der Default)
- **Nur Test:** Mails gehen ausschliesslich an die E-Mail deines Resend-Accounts
- Für echte Reminder an Leiter/TN: Domain unter https://resend.com/domains verifizieren, dann z.B. `lager@stoecklilager.com`

## GitHub Pages Secrets aktualisieren

Nach Org-Wechsel im Repo unter Settings → Secrets:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`
- optional `VITE_GOOGLE_MAPS_API_KEY`
