-- Social-Media-Zugriff für zuständige Ämtli, Bastel-Inventur und Foto-Link.

alter table public.org_bastel_inventar
  add column if not exists nachkaufen boolean not null default false,
  add column if not exists letzte_inventur_lager_id uuid references public.lager(id) on delete set null,
  add column if not exists letzte_inventur_am timestamptz;

alter table public.lager
  add column if not exists foto_link text;

create or replace function public.hat_social_media_aemtli(p_organisation_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from leiter_rollen lr
    join anmeldungen_leiter al on al.id = lr.anmeldung_leiter_id
    join lager l on l.id = al.lager_id
    join aemtli a on a.id = lr.aemtli_id
    where l.organisation_id = p_organisation_id
      and al.profile_id = auth.uid()
      and al.status = 'bestaetigt'
      and lower(a.name) in ('social media', 'social-media', 'werbung', 'publicity')
  );
$$;

revoke all on function public.hat_social_media_aemtli(uuid) from public;
grant execute on function public.hat_social_media_aemtli(uuid) to authenticated;

create or replace function public.list_org_ressourcen(p_organisation_id uuid)
returns table (
  id uuid,
  typ text,
  titel text,
  url text,
  benutzername text,
  passwort text,
  notiz text,
  sichtbarkeit text,
  sortierung int,
  zugewiesene_profile_ids uuid[]
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet';
  end if;

  if not public.is_org_mitglied(p_organisation_id) then
    raise exception 'Kein Zugriff auf diesen Verein';
  end if;

  return query
  select
    r.id,
    r.typ,
    r.titel,
    r.url,
    case when r.typ = 'zugang' then r.benutzername else null end,
    case when r.typ = 'zugang' then r.passwort else null end,
    r.notiz,
    r.sichtbarkeit,
    r.sortierung,
    coalesce(
      (
        select array_agg(z.profile_id order by z.profile_id)
        from org_ressourcen_zugriff z
        where z.ressource_id = r.id
      ),
      '{}'::uuid[]
    )
  from org_ressourcen r
  where r.organisation_id = p_organisation_id
    and (
      public.org_ressource_darf_sehen(r.organisation_id, r.sichtbarkeit, r.id)
      or (
        public.hat_social_media_aemtli(p_organisation_id)
        and lower(concat_ws(' ', r.titel, r.url, r.benutzername, r.notiz))
          ~ '(instagram|insta|tiktok|facebook|youtube|twitter|linkedin|snapchat|pinterest|threads|social|meta|whatsapp|telegram|vimeo|twitch|x\.com|fb\.com)'
      )
    )
  order by r.sortierung, r.titel;
end;
$$;

grant execute on function public.list_org_ressourcen(uuid) to authenticated;

-- Vereinskalender: alle synchronisierten Termine, Höcks und Kuchenstände.
-- Termine mit Uhrzeit werden nicht mehr als Ganztages-Termine exportiert.
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
  v_h record;
  v_k record;
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
    || 'X-WR-CALNAME:' || replace(v_titel, ',', '\,') || chr(13) || chr(10)
    || 'X-PUBLISHED-TTL:PT15M' || chr(13) || chr(10)
    || 'REFRESH-INTERVAL;VALUE=DURATION:PT15M' || chr(13) || chr(10);

  for v_t in
    select lt.*, l.name as lager_name
    from lager_termine lt
    join lager l on l.id = lt.lager_id
    where l.organisation_id = p_organisation_id
      and not (lt.typ = 'sonstiges' and coalesce(lt.beschreibung, '') like 'sync:kuchenstand:%')
    order by coalesce(lt.start_datum, '9999-12-31'::date), l.jahr desc, lt.sortierung
  loop
    if v_t.start_datum is null then continue; end if;
    v_summary := coalesce(v_t.lager_name, 'Lager') || ' – ' || v_t.titel;
    v_ics := v_ics || 'BEGIN:VEVENT' || chr(13) || chr(10)
      || 'UID:lager-termin-' || v_t.id::text || '@stoecklilager.com' || chr(13) || chr(10)
      || 'DTSTAMP:' || to_char(now() at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"') || chr(13) || chr(10);

    if v_t.start_zeit is not null then
      v_ics := v_ics
        || 'DTSTART;TZID=Europe/Zurich:'
        || to_char(v_t.start_datum, 'YYYYMMDD') || 'T' || to_char(v_t.start_zeit, 'HH24MISS')
        || chr(13) || chr(10);
      if v_t.end_zeit is not null then
        v_ics := v_ics
          || 'DTEND;TZID=Europe/Zurich:'
          || to_char(coalesce(v_t.end_datum, v_t.start_datum), 'YYYYMMDD')
          || 'T' || to_char(v_t.end_zeit, 'HH24MISS') || chr(13) || chr(10);
      end if;
    else
      v_ics := v_ics
        || 'DTSTART;VALUE=DATE:' || to_char(v_t.start_datum, 'YYYYMMDD') || chr(13) || chr(10)
        || 'DTEND;VALUE=DATE:'
        || to_char(coalesce(v_t.end_datum, v_t.start_datum) + 1, 'YYYYMMDD') || chr(13) || chr(10);
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
    where l.organisation_id = p_organisation_id and pb.tag is not null
    order by pb.tag, pb.start_zeit nulls last
  loop
    v_summary := coalesce(v_pb.lager_name, 'Lager') || ' – '
      || trim(coalesce(v_pb.code, '') || coalesce(' ' || v_pb.nummer, '') || ' ' || v_pb.titel);
    v_ics := v_ics || 'BEGIN:VEVENT' || chr(13) || chr(10)
      || 'UID:lager-prog-' || v_pb.id::text || '@stoecklilager.com' || chr(13) || chr(10)
      || 'DTSTAMP:' || to_char(now() at time zone 'UTC', 'YYYYMMDD"T"HH24MISS"Z"') || chr(13) || chr(10);
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

  -- Tages-Höcks aus der Höck-Funktion (8–10 Uhr).
  for v_h in
    select h.id, h.tag, l.name as lager_name
    from hoeck_notizen h
    join lager l on l.id = h.lager_id
    where l.organisation_id = p_organisation_id
      and not exists (
        select 1 from lager_termine lt
        where lt.lager_id = h.lager_id and lt.typ = 'hoeck' and lt.start_datum = h.tag
      )
    order by h.tag
  loop
    v_ics := v_ics || 'BEGIN:VEVENT' || chr(13) || chr(10)
      || 'UID:lager-hoeck-' || v_h.id::text || '@stoecklilager.com' || chr(13) || chr(10)
      || 'DTSTART;TZID=Europe/Zurich:' || to_char(v_h.tag, 'YYYYMMDD') || 'T080000' || chr(13) || chr(10)
      || 'DTEND;TZID=Europe/Zurich:' || to_char(v_h.tag, 'YYYYMMDD') || 'T100000' || chr(13) || chr(10)
      || 'SUMMARY:' || replace(v_h.lager_name || ' – Höck', ',', '\,') || chr(13) || chr(10)
      || 'END:VEVENT' || chr(13) || chr(10);
  end loop;

  -- Kuchenstände direkt aus dem Ämtli: stabile UID, auch nach erneutem Sync.
  for v_k in
    select k.id, k.datum, k.ort, k.notiz, l.name as lager_name
    from kuchenstand_standorte k
    join lager l on l.id = k.lager_id
    where l.organisation_id = p_organisation_id and k.datum is not null
    order by k.datum, k.sortierung
  loop
    v_ics := v_ics || 'BEGIN:VEVENT' || chr(13) || chr(10)
      || 'UID:kuchenstand-' || v_k.id::text || '@stoecklilager.com' || chr(13) || chr(10)
      || 'DTSTART;VALUE=DATE:' || to_char(v_k.datum, 'YYYYMMDD') || chr(13) || chr(10)
      || 'DTEND;VALUE=DATE:' || to_char(v_k.datum + 1, 'YYYYMMDD') || chr(13) || chr(10)
      || 'SUMMARY:' || replace(v_k.lager_name || ' – Kuchenstand: ' || v_k.ort, ',', '\,') || chr(13) || chr(10)
      || 'LOCATION:' || replace(v_k.ort, ',', '\,') || chr(13) || chr(10);
    if v_k.notiz is not null then
      v_ics := v_ics || 'DESCRIPTION:' || replace(v_k.notiz, ',', '\,') || chr(13) || chr(10);
    end if;
    v_ics := v_ics || 'END:VEVENT' || chr(13) || chr(10);
  end loop;

  return v_ics || 'END:VCALENDAR';
end;
$$;
