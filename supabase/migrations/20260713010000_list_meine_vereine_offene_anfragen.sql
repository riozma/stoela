-- Admins/Leitung sollen auf dem Dashboard sehen, wenn für ihren Verein
-- Beitrittsanfragen auf Entscheidung warten -- nicht nur der/die
-- Anfragende sieht "meine Anfrage ist offen".
drop function if exists public.list_meine_vereine();

create or replace function public.list_meine_vereine()
returns table (
  organisation_id uuid,
  slug text,
  name text,
  homepage text,
  meine_rolle text,
  mein_status text,
  offene_beitrittsanfragen integer
)
language sql
security definer
stable
set search_path = public
as $$
  select
    o.id as organisation_id,
    o.slug,
    o.name,
    o.homepage,
    om.rolle as meine_rolle,
    om.status as mein_status,
    case
      when om.status = 'mitglied' and om.rolle in ('admin', 'leitung') then (
        select count(*)::int from organisation_mitglieder om2
        where om2.organisation_id = o.id and om2.status = 'angefragt'
      )
      else 0
    end as offene_beitrittsanfragen
  from organisation_mitglieder om
  join organisation o on o.id = om.organisation_id
  where om.profile_id = auth.uid()
  order by o.name;
$$;

grant execute on function public.list_meine_vereine() to authenticated;
