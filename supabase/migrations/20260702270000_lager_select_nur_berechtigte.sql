-- Die Policy «lager: select anmeldung basis» erlaubte jedem (auch ohne Team-Zugang)
-- alle Lager mit Status planung/anmeldung_offen/laufend zu lesen.
-- Anmelde- und Willkommensseiten nutzen bereits RPCs (get_lager_anmeldung_*,
-- get_lager_willkommen) – direkter Tabellenzugriff ist nicht nötig.

drop policy if exists "lager: select anmeldung basis" on lager;

-- Übersicht: nur Lager zurückgeben, auf die der User Zugriff hat
create or replace function public.list_meine_lager()
returns table (
  id uuid,
  jahr integer,
  name text,
  ort text,
  start_datum date,
  end_datum date,
  status text
)
language sql
security definer
stable
set search_path = public
as $$
  select l.id, l.jahr, l.name, l.ort, l.start_datum, l.end_datum, l.status
  from lager l
  where public.can_access_lager(l.id)
  order by l.jahr desc;
$$;

grant execute on function public.list_meine_lager() to authenticated;
