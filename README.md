# Stöckli Lager App

Interne Web-App fürs Jugendlager (J+S/Jubla) des Stöckli-Teams: Leiter-/TN-Anmeldung,
Ämtli mit Übergabe-Learnings, Einkaufsliste und Erinnerungen. Läuft auf GitHub Pages
(`app.stoecklilager.com`) mit Supabase als Backend.

## Struktur

- `app/` – Vue 3 + TypeScript SPA (Vite)
- `supabase/migrations/` – Datenbankschema
- `.github/workflows/deploy-pages.yml` – Build & Deploy auf GitHub Pages
- `CNAME` – Custom Domain für GitHub Pages

## Lokale Entwicklung

```bash
cd app
npm install
cp .env.example .env   # VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY eintragen
npm run dev
```

## Supabase

Migration liegt in `supabase/migrations/20260702000001_init.sql`. Mit der Supabase CLI
gegen ein Projekt anwenden:

```bash
supabase link --project-ref <project-ref>
supabase db push
```

## Deployment (GitHub Pages)

1. Repo-Settings → Pages → Source: „GitHub Actions".
2. Repo-Secrets setzen: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`.
3. DNS beim Domain-Registrar: `CNAME app.stoecklilager.com → <username>.github.io`.
4. Push auf `main` löst den Workflow aus.

## Noch offen

- Resend-Integration (Edge Function `supabase/functions/send-reminder`)
- Anbindung eCamp / jubla.db (OAuth-Zugänge nötig, siehe Konzept-Diskussion)
- TN-/Leiter-Anmeldeformular, Ämtli- und Einkaufslisten-UI
