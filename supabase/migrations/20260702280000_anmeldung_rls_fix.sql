-- Insert-Policies für Anmeldungen prüfen den Lager-Status via Subquery auf «lager».
-- Nach Entfernen der breiten Lager-SELECT-Policy sehen Nicht-Teammitglieder
-- diese Zeilen nicht mehr → INSERT schlägt fehl. Hilfsfunktionen umgehen RLS.

create or replace function public.lager_erlaubt_tn_anmeldung(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from lager l
    where l.id = p_lager_id
      and l.status = 'anmeldung_offen'
  );
$$;

create or replace function public.lager_erlaubt_leiter_anmeldung(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from lager l
    where l.id = p_lager_id
      and l.status <> 'archiviert'
      and l.status in ('planung', 'anmeldung_offen', 'laufend')
  );
$$;

grant execute on function public.lager_erlaubt_tn_anmeldung(uuid) to anon, authenticated;
grant execute on function public.lager_erlaubt_leiter_anmeldung(uuid) to authenticated;

drop policy if exists "anmeldungen_tn: insert öffentlich bei offener Anmeldung" on anmeldungen_tn;

create policy "anmeldungen_tn: insert öffentlich bei offener Anmeldung" on anmeldungen_tn
  for insert to anon, authenticated
  with check (public.lager_erlaubt_tn_anmeldung(lager_id));

drop policy if exists "anmeldungen_leiter: insert eigene Anfrage" on anmeldungen_leiter;

create policy "anmeldungen_leiter: insert eigene Anfrage" on anmeldungen_leiter
  for insert to authenticated
  with check (
    profile_id = auth.uid()
    and public.lager_erlaubt_leiter_anmeldung(lager_id)
  );
