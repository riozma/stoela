-- list_vereinslager: leiter_anmeldung_status + im_team (echte Lager-Team-Mitgliedschaft,
-- getrennt von can_edit das für jedes Vereinsmitglied true ist) mitliefern, damit das
-- Frontend Lager mit geschlossener Leiteranmeldung vor Nicht-Admins/Nicht-Team-Mitgliedern
-- verbergen kann.
drop function if exists public.list_vereinslager(uuid);

create or replace function public.list_vereinslager(p_organisation_id uuid)
returns table(
  id uuid, jahr integer, name text, ort text, start_datum date, end_datum date, status text,
  can_edit boolean, leiter_anmeldung_status text, im_team boolean
)
language sql
stable security definer
set search_path to 'public'
as $function$
  select
    l.id,
    l.jahr,
    l.name,
    l.ort,
    l.start_datum,
    l.end_datum,
    l.status,
    (public.can_access_lager(l.id) or public.is_org_mitglied_von_lager(l.id)) as can_edit,
    l.leiter_anmeldung_status,
    public.can_access_lager(l.id) as im_team
  from lager l
  where l.organisation_id = p_organisation_id
    and public.is_org_mitglied(p_organisation_id)
  order by l.start_datum nulls last, l.jahr desc, l.name;
$function$;

grant execute on function public.list_vereinslager(uuid) to authenticated;
