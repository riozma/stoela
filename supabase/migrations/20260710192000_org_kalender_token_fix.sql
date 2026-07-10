-- Kalender-Abo: auch Legacy-Lager-Token akzeptieren

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
