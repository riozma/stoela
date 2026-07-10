-- Vereins-Kalender (ein Link pro Organisation) + je Lager max. ein Termin pro Typ

-- ---------------------------------------------------------------------
-- Kalender-Token auf Organisationsebene
-- ---------------------------------------------------------------------
alter table organisation
  add column if not exists kalender_token uuid not null default gen_random_uuid();

-- Bestehenden Lager-Token auf Organisation übernehmen (Abwärtskompatibilität)
update organisation o
set kalender_token = sub.tok::uuid
from (
  select l.organisation_id, min(l.kalender_token::text) as tok
  from lager l
  where l.organisation_id is not null
  group by l.organisation_id
) sub
where o.id = sub.organisation_id;

-- Bestehende Duplikate bereinigen (alle Singleton-Typen)
delete from lager_termine lt
where lt.typ in ('lager', 'elternabend', 'kennenlernabend', 'diashow', 'vorweekend', 'skiweekend', 'hoeck')
  and lt.id not in (
    select distinct on (lager_id, typ) id
    from lager_termine
    where typ in ('lager', 'elternabend', 'kennenlernabend', 'diashow', 'vorweekend', 'skiweekend', 'hoeck')
    order by lager_id, typ, updated_at desc nulls last, created_at desc
  );

drop index if exists lager_termine_singleton_typ_idx;

create unique index lager_termine_singleton_typ_idx
  on lager_termine (lager_id, typ)
  where typ in ('lager', 'elternabend', 'kennenlernabend', 'diashow', 'vorweekend', 'skiweekend', 'hoeck');

-- ---------------------------------------------------------------------
-- Upsert-Helfer (alle Singleton-Typen ausser sonstiges)
-- ---------------------------------------------------------------------
create or replace function public.lager_termin_upsert_cfg(
  p_lager_id uuid,
  p_typ text,
  p_titel text,
  p_start_datum date,
  p_end_datum date default null,
  p_ort text default null,
  p_oeffentlich boolean default false,
  p_sortierung int default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_start_datum is null then return; end if;

  insert into lager_termine (
    lager_id, typ, titel, start_datum, end_datum, ort, oeffentlich, sortierung
  )
  values (
    p_lager_id, p_typ, p_titel, p_start_datum, p_end_datum, p_ort, p_oeffentlich, p_sortierung
  )
  on conflict (lager_id, typ) where typ in (
    'lager', 'elternabend', 'kennenlernabend', 'diashow', 'vorweekend', 'skiweekend', 'hoeck'
  )
  do update set
    titel = excluded.titel,
    start_datum = excluded.start_datum,
    end_datum = excluded.end_datum,
    ort = coalesce(excluded.ort, lager_termine.ort),
    oeffentlich = excluded.oeffentlich,
    sortierung = excluded.sortierung,
    updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------
-- Organisation: alle Lager-Termine synchronisieren
-- ---------------------------------------------------------------------
create or replace function public.org_termine_sync(p_organisation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager_id uuid;
begin
  for v_lager_id in
    select l.id from lager l where l.organisation_id = p_organisation_id
  loop
    perform public.lager_termine_sync(v_lager_id);
  end loop;
end;
$$;

create or replace function public.org_kalender_titel(p_organisation_id uuid)
returns text
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_name text;
begin
  select o.name into v_name from organisation o where o.id = p_organisation_id;
  return coalesce(v_name, 'Vereinskalender');
end;
$$;

create or replace function public.get_org_kalender_ics(
  p_organisation_id uuid,
  p_token uuid default null
)
returns text
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_org organisation%rowtype;
  v_ics text := '';
  v_t record;
  v_pb record;
  v_titel text;
  v_summary text;
begin
  select * into v_org from organisation where id = p_organisation_id;
  if not found then return null; end if;

  if p_token is not null then
    if v_org.kalender_token::text is distinct from p_token::text then
      return null;
    end if;
  elsif auth.uid() is null
    or not (
      public.is_org_mitglied(p_organisation_id)
      or public.is_org_leitung(p_organisation_id)
      or exists (
        select 1 from lager l
        where l.organisation_id = p_organisation_id
          and public.can_access_lager(l.id)
      )
    ) then
    return null;
  end if;

  perform public.org_termine_sync(p_organisation_id);

  v_titel := public.org_kalender_titel(p_organisation_id);

  v_ics := 'BEGIN:VCALENDAR' || chr(13) || chr(10)
    || 'VERSION:2.0' || chr(13) || chr(10)
    || 'PRODID:-//Stoeckli Lager//DE' || chr(13) || chr(10)
    || 'CALSCALE:GREGORIAN' || chr(13) || chr(10)
    || 'METHOD:PUBLISH' || chr(13) || chr(10)
    || 'X-WR-CALNAME:' || replace(v_titel, ',', '\,') || chr(13) || chr(10);

  for v_t in
    select lt.*, l.name as lager_name
    from lager_termine lt
    join lager l on l.id = lt.lager_id
    where l.organisation_id = p_organisation_id
    order by coalesce(lt.start_datum, '9999-12-31'::date), l.jahr desc, lt.sortierung
  loop
    if v_t.start_datum is null then continue; end if;
    v_summary := coalesce(v_t.lager_name, 'Lager') || ' – ' || v_t.titel;
    v_ics := v_ics || 'BEGIN:VEVENT' || chr(13) || chr(10)
      || 'UID:lager-termin-' || v_t.id::text || '@stoecklilager.com' || chr(13) || chr(10)
      || 'DTSTART;VALUE=DATE:' || to_char(v_t.start_datum, 'YYYYMMDD') || chr(13) || chr(10);
    if v_t.end_datum is not null and v_t.end_datum > v_t.start_datum then
      v_ics := v_ics || 'DTEND;VALUE=DATE:' || to_char(v_t.end_datum + 1, 'YYYYMMDD') || chr(13) || chr(10);
    else
      v_ics := v_ics || 'DTEND;VALUE=DATE:' || to_char(v_t.start_datum + 1, 'YYYYMMDD') || chr(13) || chr(10);
    end if;
    v_ics := v_ics || 'SUMMARY:' || replace(v_summary, ',', '\,') || chr(13) || chr(10);
    if v_t.ort is not null then
      v_ics := v_ics || 'LOCATION:' || replace(v_t.ort, ',', '\,') || chr(13) || chr(10);
    end if;
    if v_t.beschreibung is not null then
      v_ics := v_ics || 'DESCRIPTION:' || replace(v_t.beschreibung, ',', '\,') || chr(13) || chr(10);
    end if;
    v_ics := v_ics || 'END:VEVENT' || chr(13) || chr(10);
  end loop;

  for v_pb in
    select pb.*, l.name as lager_name
    from programmbloecke pb
    join lager l on l.id = pb.lager_id
    where l.organisation_id = p_organisation_id
      and pb.tag is not null
    order by pb.tag, pb.start_zeit nulls last
  loop
    v_summary := coalesce(v_pb.lager_name, 'Lager') || ' – '
      || trim(coalesce(v_pb.code, '') || coalesce(' ' || v_pb.nummer, '') || ' ' || v_pb.titel);
    v_ics := v_ics || 'BEGIN:VEVENT' || chr(13) || chr(10)
      || 'UID:lager-prog-' || v_pb.id::text || '@stoecklilager.com' || chr(13) || chr(10);
    if v_pb.start_zeit is not null then
      v_ics := v_ics || 'DTSTART:' || to_char(v_pb.start_zeit at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"') || chr(13) || chr(10);
      if v_pb.end_zeit is not null then
        v_ics := v_ics || 'DTEND:' || to_char(v_pb.end_zeit at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"') || chr(13) || chr(10);
      end if;
    else
      v_ics := v_ics || 'DTSTART;VALUE=DATE:' || to_char(v_pb.tag, 'YYYYMMDD') || chr(13) || chr(10)
        || 'DTEND;VALUE=DATE:' || to_char(v_pb.tag + 1, 'YYYYMMDD') || chr(13) || chr(10);
    end if;
    v_ics := v_ics || 'SUMMARY:' || replace(v_summary, ',', '\,') || chr(13) || chr(10);
    if v_pb.ort is not null then
      v_ics := v_ics || 'LOCATION:' || replace(v_pb.ort, ',', '\,') || chr(13) || chr(10);
    end if;
    v_ics := v_ics || 'END:VEVENT' || chr(13) || chr(10);
  end loop;

  v_ics := v_ics || 'END:VCALENDAR';
  return v_ics;
end;
$$;

-- Legacy: Lager-Link leitet auf Vereinskalender um
create or replace function public.get_lager_kalender_ics(p_lager_id uuid, p_token uuid default null)
returns text
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_org_id uuid;
  v_org_token uuid;
begin
  select l.organisation_id into v_org_id from lager l where l.id = p_lager_id;
  if v_org_id is null then return null; end if;

  if p_token is not null then
    select o.kalender_token into v_org_token
    from organisation o where o.id = v_org_id;
    if v_org_token::text is distinct from p_token::text
      and not exists (
        select 1 from lager l
        where l.id = p_lager_id and l.kalender_token::text = p_token::text
      ) then
      return null;
    end if;
  end if;

  return public.get_org_kalender_ics(v_org_id, p_token);
end;
$$;

grant execute on function public.org_termine_sync(uuid) to authenticated;
grant execute on function public.org_kalender_titel(uuid) to authenticated;
grant execute on function public.get_org_kalender_ics(uuid, uuid) to anon, authenticated;
