-- Öffentlicher Instagram-Link des Vereins, für die dynamische
-- Willkommensseite (/lager/:id/willkommen): während dem Lager wird
-- dorthin verlinkt.
alter table organisation add column if not exists instagram_url text;

-- get_lager_willkommen um Instagram-Link + Diashow-Termin erweitern,
-- damit die Willkommensseite ohne separate privilegierte Abfragen
-- (org_ressourcen enthält u.a. Passwörter und darf nicht anonym lesbar
-- sein) alles Nötige aus einem öffentlichen RPC-Aufruf bekommt.
create or replace function public.get_lager_willkommen(p_lager_id uuid)
returns json
language sql
security definer
stable
set search_path = public
as $$
  select json_build_object(
    'id', l.id,
    'name', l.name,
    'ort', l.ort,
    'start_datum', l.start_datum,
    'end_datum', l.end_datum,
    'ort_lat', l.ort_lat,
    'ort_lng', l.ort_lng,
    'status', l.status,
    'foto_link', l.foto_link,
    'instagram_url', o.instagram_url,
    'diashow_datum', dt.start_datum,
    'diashow_zeit', dt.start_zeit,
    'diashow_ort', dt.ort
  )
  from lager l
  left join organisation o on o.id = l.organisation_id
  left join lager_termine dt on dt.lager_id = l.id and dt.typ = 'diashow'
  where l.id = p_lager_id
    and l.status <> 'archiviert';
$$;

grant execute on function public.get_lager_willkommen(uuid) to anon, authenticated;
