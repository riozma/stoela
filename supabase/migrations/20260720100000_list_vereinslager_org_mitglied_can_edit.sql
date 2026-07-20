-- Dashboard/Organisation-Lagerlisten schickten Vereinsmitglieder ohne
-- expliziten (u.U. bei alten/vergangenen Lagern nie nachgetragenen)
-- lager_leiter-Eintrag auf die reine Gastansicht (/willkommen), obwohl sie
-- als Leiter im Verein eigentlich immer auf die Lagerseite gehören.
-- can_edit nutzt daher zusätzlich is_org_mitglied_von_lager (nur
-- UI-Routing-Entscheidung, ändert keine RLS auf sensiblen Detaildaten).
create or replace function public.list_vereinslager(p_organisation_id uuid)
returns table (
  id uuid,
  jahr int,
  name text,
  ort text,
  start_datum date,
  end_datum date,
  status text,
  can_edit boolean
)
language sql
security definer
stable
set search_path = public
as $$
  select
    l.id,
    l.jahr,
    l.name,
    l.ort,
    l.start_datum,
    l.end_datum,
    l.status,
    (public.can_access_lager(l.id) or public.is_org_mitglied_von_lager(l.id)) as can_edit
  from lager l
  where l.organisation_id = p_organisation_id
    and public.is_org_mitglied(p_organisation_id)
  order by l.start_datum nulls last, l.jahr desc, l.name;
$$;
