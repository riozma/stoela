-- ICS: STABLE entfernen (Sync macht DELETE → read-only Fehler)
-- Öffentliche Termine im Kalender bearbeitbar (Datum/Ort → Elterninfo)

create or replace function public.get_org_kalender_ics(
  p_organisation_id uuid,
  p_token uuid default null
)
returns text
language plpgsql
security definer
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
    if v_org.kalender_token::text is distinct from p_token::text
      and not exists (
        select 1 from lager l
        where l.organisation_id = p_organisation_id
          and l.kalender_token::text = p_token::text
      ) then
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

create or replace function public.get_lager_kalender_ics(p_lager_id uuid, p_token uuid default null)
returns text
language plpgsql
security definer
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

create or replace function public.lager_termin_oeffentlich_speichern(
  p_termin_id uuid,
  p_start_datum date,
  p_end_datum date default null,
  p_ort text default null,
  p_nur_ein_tag boolean default true
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t lager_termine%rowtype;
  v_cfg jsonb;
  v_datum text;
  v_end date;
  v_cfg_key_datum text;
  v_cfg_key_ort text;
begin
  select * into v_t from lager_termine where id = p_termin_id;
  if not found then
    raise exception 'Termin nicht gefunden.';
  end if;

  if v_t.typ not in ('elternabend', 'kennenlernabend', 'diashow') then
    raise exception 'Nur Elternabend, Kennenlernabend und Diashow können hier bearbeitet werden.';
  end if;

  if not public.can_access_lager(v_t.lager_id) then
    raise exception 'Kein Zugriff auf dieses Lager.';
  end if;

  if p_start_datum is null then
    raise exception 'Startdatum ist Pflicht.';
  end if;

  v_end := case when p_nur_ein_tag or p_end_datum is null then p_start_datum else p_end_datum end;

  update lager_termine
  set start_datum = p_start_datum,
      end_datum = v_end,
      ort = nullif(trim(p_ort), ''),
      updated_at = now()
  where id = p_termin_id;

  v_datum := to_char(p_start_datum, 'YYYY-MM-DD');

  case v_t.typ
    when 'elternabend' then
      v_cfg_key_datum := 'elternabend_datum';
      v_cfg_key_ort := 'elternabend_ort';
    when 'kennenlernabend' then
      v_cfg_key_datum := 'kennenlernabend_datum';
      v_cfg_key_ort := 'kennenlernabend_ort';
    when 'diashow' then
      v_cfg_key_datum := 'diashow_datum';
      v_cfg_key_ort := 'diashow_ort';
  end case;

  select coalesce(elterninfo_config, '{}'::jsonb) into v_cfg
  from lager where id = v_t.lager_id;

  v_cfg := v_cfg
    || jsonb_build_object(v_cfg_key_datum, v_datum)
    || jsonb_build_object(v_cfg_key_ort, coalesce(nullif(trim(p_ort), ''), v_cfg->>v_cfg_key_ort));

  update lager
  set elterninfo_config = v_cfg
  where id = v_t.lager_id;
end;
$$;

grant execute on function public.lager_termin_oeffentlich_speichern(uuid, date, date, text, boolean) to authenticated;
