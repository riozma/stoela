-- Letzte Lager-Aktivitäten für Dashboard (aggregiert + optional manuelles Log)

create table if not exists lager_aktivitaet (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  beschreibung text not null,
  kategorie text,
  actor_id uuid references profiles (id),
  created_at timestamptz not null default now()
);

create index if not exists lager_aktivitaet_lager_idx on lager_aktivitaet (lager_id, created_at desc);

alter table lager_aktivitaet enable row level security;

create policy "lager_aktivitaet: lagerteam" on lager_aktivitaet
  for all to authenticated
  using (public.can_access_lager(lager_id))
  with check (public.can_access_lager(lager_id));

create or replace function public.log_lager_aktivitaet(
  p_lager_id uuid,
  p_beschreibung text,
  p_kategorie text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_access_lager(p_lager_id) then
    raise exception 'Kein Zugriff auf dieses Lager.';
  end if;
  insert into lager_aktivitaet (lager_id, beschreibung, kategorie, actor_id)
  values (p_lager_id, p_beschreibung, p_kategorie, auth.uid());
end;
$$;

grant execute on function public.log_lager_aktivitaet(uuid, text, text) to authenticated;

create or replace function public.list_lager_letzte_aenderungen(
  p_lager_id uuid,
  p_limit integer default 10
)
returns table (
  zeit timestamptz,
  beschreibung text,
  kategorie text
)
language sql
stable
security definer
set search_path = public
as $$
  select u.zeit, u.beschreibung, u.kategorie
  from (
    select q.created_at as zeit,
      'Quittung eingereicht: ' || q.zweck as beschreibung,
      'quittungen' as kategorie
    from quittungen q
    where q.lager_id = p_lager_id

    union all

    select q.bearbeitet_am,
      'Quittung ' || q.status || ': ' || q.zweck,
      'quittungen'
    from quittungen q
    where q.lager_id = p_lager_id and q.bearbeitet_am is not null

    union all

    select t.created_at,
      'TN ' || t.vorname || ' ' || t.nachname || ' angemeldet',
      'teilnehmer'
    from anmeldungen_tn t
    where t.lager_id = p_lager_id

    union all

    select al.created_at,
      case al.status
        when 'angefragt' then 'Leiter-Anfrage: '
        when 'abgelehnt' then 'Leiter-Anfrage abgelehnt: '
        else 'Leiter: '
      end || al.vorname || ' ' || al.nachname,
      'leiter'
    from anmeldungen_leiter al
    where al.lager_id = p_lager_id

    union all

    select e.created_at,
      'Einkauf: ' || e.name,
      'einkauf'
    from einkaufsliste_items e
    where e.lager_id = p_lager_id

    union all

    select h.updated_at,
      'Höck-Notizen ' || to_char(h.tag, 'DD.MM.YYYY'),
      'programm'
    from hoeck_notizen h
    where h.lager_id = p_lager_id

    union all

    select g.created_at,
      'Gruppe «' || g.name || '» erstellt',
      'gruppen'
    from lagergruppen g
    where g.lager_id = p_lager_id

    union all

    select la.created_at,
      la.beschreibung,
      coalesce(la.kategorie, 'sonstiges')
    from lager_aktivitaet la
    where la.lager_id = p_lager_id
  ) u
  where public.can_access_lager(p_lager_id)
  order by u.zeit desc
  limit greatest(1, least(p_limit, 50));
$$;

grant execute on function public.list_lager_letzte_aenderungen(uuid, integer) to authenticated;
