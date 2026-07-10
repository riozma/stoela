-- Fix: lager_termine_sync erzeugte bei jedem Aufruf Duplikate (fehlender Unique-Constraint)

-- Bestehende Duplikate bereinigen (neuesten Eintrag pro Lager+Typ behalten)
delete from lager_termine lt
where lt.typ in ('lager', 'elternabend', 'kennenlernabend', 'diashow', 'vorweekend')
  and lt.id not in (
    select distinct on (lager_id, typ) id
    from lager_termine
    where typ in ('lager', 'elternabend', 'kennenlernabend', 'diashow', 'vorweekend')
    order by lager_id, typ, updated_at desc nulls last, created_at desc
  );

-- Pro Lager nur ein Eintrag je synchronisiertem Typ
create unique index if not exists lager_termine_singleton_typ_idx
  on lager_termine (lager_id, typ)
  where typ in ('lager', 'elternabend', 'kennenlernabend', 'diashow', 'vorweekend');

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
  on conflict (lager_id, typ) where typ in ('lager', 'elternabend', 'kennenlernabend', 'diashow', 'vorweekend')
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

create or replace function public.lager_termine_sync(p_lager_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager lager%rowtype;
  v_cfg jsonb;
begin
  select * into v_lager from lager where id = p_lager_id;
  if not found then return; end if;

  v_cfg := coalesce(v_lager.elterninfo_config, '{}'::jsonb);

  if v_lager.start_datum is not null then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'lager', coalesce(v_lager.name, 'Lager'),
      v_lager.start_datum, v_lager.end_datum,
      v_lager.ort, true, 0
    );
  end if;

  if v_lager.vorweekend_start is not null then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'vorweekend', 'Vorweekend',
      v_lager.vorweekend_start, v_lager.vorweekend_ende,
      null, false, 10
    );
  end if;

  if (v_cfg->>'elternabend_datum') ~ '^\d{4}-\d{2}-\d{2}$' then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'elternabend', 'Elternabend',
      (v_cfg->>'elternabend_datum')::date,
      null, nullif(v_cfg->>'elternabend_ort', ''), true, 20
    );
  end if;

  if (v_cfg->>'kennenlernabend_datum') ~ '^\d{4}-\d{2}-\d{2}$' then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'kennenlernabend', 'Kennenlernabend',
      (v_cfg->>'kennenlernabend_datum')::date,
      null, nullif(v_cfg->>'kennenlernabend_ort', ''), true, 30
    );
  end if;

  if (v_cfg->>'diashow_datum') ~ '^\d{4}-\d{2}-\d{2}$' then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'diashow', 'Diashow / Lagerrückblick',
      (v_cfg->>'diashow_datum')::date,
      null, nullif(v_cfg->>'diashow_ort', ''), true, 40
    );
  end if;
end;
$$;

-- Stabile ICS-UIDs pro Termin (keine Duplikate beim Abo-Refresh)
create or replace function public.get_lager_kalender_ics(p_lager_id uuid, p_token uuid default null)
returns text
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_lager lager%rowtype;
  v_ics text := '';
  v_t lager_termine%rowtype;
  v_pb programmbloecke%rowtype;
  v_titel text;
begin
  select * into v_lager from lager where id = p_lager_id;
  if not found then return null; end if;

  if p_token is not null then
    if v_lager.kalender_token::text is distinct from p_token::text then
      return null;
    end if;
  elsif auth.uid() is null or not public.can_access_lager(p_lager_id) then
    return null;
  end if;

  perform public.lager_termine_sync(p_lager_id);

  v_titel := public.lager_kalender_titel(p_lager_id);

  v_ics := 'BEGIN:VCALENDAR' || chr(13) || chr(10)
    || 'VERSION:2.0' || chr(13) || chr(10)
    || 'PRODID:-//Stoeckli Lager//DE' || chr(13) || chr(10)
    || 'CALSCALE:GREGORIAN' || chr(13) || chr(10)
    || 'METHOD:PUBLISH' || chr(13) || chr(10)
    || 'X-WR-CALNAME:' || replace(v_titel, ',', '\,') || chr(13) || chr(10);

  for v_t in
    select * from lager_termine
    where lager_id = p_lager_id
    order by coalesce(start_datum, '9999-12-31'::date), sortierung
  loop
    if v_t.start_datum is null then continue; end if;
    v_ics := v_ics || 'BEGIN:VEVENT' || chr(13) || chr(10)
      || 'UID:lager-termin-' || v_t.id::text || '@stoecklilager.com' || chr(13) || chr(10)
      || 'DTSTART;VALUE=DATE:' || to_char(v_t.start_datum, 'YYYYMMDD') || chr(13) || chr(10);
    if v_t.end_datum is not null and v_t.end_datum > v_t.start_datum then
      v_ics := v_ics || 'DTEND;VALUE=DATE:' || to_char(v_t.end_datum + 1, 'YYYYMMDD') || chr(13) || chr(10);
    else
      v_ics := v_ics || 'DTEND;VALUE=DATE:' || to_char(v_t.start_datum + 1, 'YYYYMMDD') || chr(13) || chr(10);
    end if;
    v_ics := v_ics || 'SUMMARY:' || replace(v_t.titel, ',', '\,') || chr(13) || chr(10);
    if v_t.ort is not null then
      v_ics := v_ics || 'LOCATION:' || replace(v_t.ort, ',', '\,') || chr(13) || chr(10);
    end if;
    if v_t.beschreibung is not null then
      v_ics := v_ics || 'DESCRIPTION:' || replace(v_t.beschreibung, ',', '\,') || chr(13) || chr(10);
    end if;
    v_ics := v_ics || 'END:VEVENT' || chr(13) || chr(10);
  end loop;

  for v_pb in
    select * from programmbloecke
    where lager_id = p_lager_id and tag is not null
    order by tag, start_zeit nulls last
  loop
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
    v_ics := v_ics || 'SUMMARY:' || replace(trim(coalesce(v_pb.code, '') || coalesce(' ' || v_pb.nummer, '') || ' ' || v_pb.titel), ',', '\,') || chr(13) || chr(10);
    if v_pb.ort is not null then
      v_ics := v_ics || 'LOCATION:' || replace(v_pb.ort, ',', '\,') || chr(13) || chr(10);
    end if;
    v_ics := v_ics || 'END:VEVENT' || chr(13) || chr(10);
  end loop;

  v_ics := v_ics || 'END:VCALENDAR';
  return v_ics;
end;
$$;
