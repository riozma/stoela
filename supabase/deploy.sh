#!/usr/bin/env bash
set -euo pipefail

# Deploy Stöla Supabase schema + Edge Functions
# Voraussetzung: SUPABASE_ACCESS_TOKEN und PROJECT_REF gesetzt

if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
  echo "Fehler: SUPABASE_ACCESS_TOKEN fehlt"
  echo "Token: https://supabase.com/dashboard/account/tokens"
  exit 1
fi

if [[ -z "${PROJECT_REF:-}" ]]; then
  echo "Fehler: PROJECT_REF fehlt"
  echo "Project Ref: Dashboard → Project Settings → General"
  exit 1
fi

cd "$(dirname "$0")/.."

echo "→ Linking project $PROJECT_REF ..."
npx --yes supabase link --project-ref "$PROJECT_REF"

echo "→ Applying migrations ..."
npx --yes supabase db push

echo "→ Deploying Edge Functions ..."
npx --yes supabase functions deploy parse-lager-pdf
npx --yes supabase functions deploy send-reminder

if [[ -n "${GEMINI_API_KEY:-}" || -n "${RESEND_API_KEY:-}" ]]; then
  echo "→ Setting secrets ..."
  SECRETS=()
  [[ -n "${GEMINI_API_KEY:-}" ]] && SECRETS+=(GEMINI_API_KEY="$GEMINI_API_KEY")
  [[ -n "${RESEND_API_KEY:-}" ]] && SECRETS+=(RESEND_API_KEY="$RESEND_API_KEY")
  [[ -n "${RESEND_FROM:-}" ]] && SECRETS+=(RESEND_FROM="$RESEND_FROM")
  npx --yes supabase secrets set "${SECRETS[@]}"
fi

echo ""
echo "✓ Fertig! Vergiss nicht GitHub Secrets zu aktualisieren:"
echo "  VITE_SUPABASE_URL=https://${PROJECT_REF}.supabase.co"
echo "  VITE_SUPABASE_ANON_KEY=<anon key aus Dashboard → API>"
