# Stöckli Lager App

Interne Web-App fürs Jugendlager (J+S/Jubla) des Stöckli-Teams: Leiter-/TN-Anmeldung,
Programm, Gruppen, Reminder und Team-Berechtigungen. Läuft auf GitHub Pages
(`app.stoecklilager.com`) mit Supabase als Backend.

## Struktur

- `app/` – Vue 3 + TypeScript SPA (Vite)
- `supabase/migrations/` – Datenbankschema & RLS
- `supabase/functions/` – Edge Functions (PDF-Import, Reminder)
- `.github/workflows/deploy-pages.yml` – Build & Deploy auf GitHub Pages

## Lokale Entwicklung

```bash
cd app
npm install
cp .env.example .env   # VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY eintragen
npm run dev
```

## Supabase

Migrationen in `supabase/migrations/` anwenden:

```bash
supabase link --project-ref <project-ref>
supabase db push
supabase functions deploy parse-lager-pdf
supabase functions deploy send-reminder
```

### Secrets (Supabase Edge Functions)

| Secret | Funktion |
|---|---|
| `GEMINI_API_KEY` | `parse-lager-pdf` |
| `RESEND_API_KEY` | `send-reminder` |
| `RESEND_FROM` | optional; Default `Stöckli Lager <onboarding@resend.dev>` (nur Test an eigene Resend-E-Mail) |

Ohne verifizierte Domain kannst du trotzdem testen: `RESEND_API_KEY` reicht, `RESEND_FROM` weglassen oder auf `onboarding@resend.dev` lassen. Echte Reminder an Leiter brauchen später eine Domain bei [resend.com/domains](https://resend.com/domains).

Siehe auch `supabase/DEPLOY.md` für den kompletten Deploy nach Org-Wechsel.

### Zugriffskontrolle

- Nur Ersteller/in oder freigeschaltete Teammitglieder (`lager_leiter`, Status `bestaetigt`) sehen ein Lager
- TN/Eltern sehen nur `/lager/:id/willkommen` (Ort, Zeitraum, Wetter) – kein Programm
- Freischalten neuer Leiter über Tab „Team" (E-Mail muss bereits registriert sein)

## Deployment (GitHub Pages)

1. Repo-Settings → Pages → Source: „GitHub Actions"
2. Secrets: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, optional `VITE_GOOGLE_MAPS_API_KEY`
3. DNS: `CNAME app.stoecklilager.com → <username>.github.io`

## Noch offen (später)

- eCamp API (OAuth)
- jubla.db Anbindung
- J+S-Portal
