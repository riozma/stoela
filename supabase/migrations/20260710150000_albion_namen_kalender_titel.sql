-- Albion-Fix: Namen robust auflösen; Kalender-Titel mit Grobprogramm/Motto

-- ---------------------------------------------------------------------
-- Namen aus Profil, OAuth, org_personen, früheren Leiter-Anmeldungen
-- ---------------------------------------------------------------------
create or replace function public.profile_namen_aufloesen(
  p_profile_id uuid,
  p_organisation_id uuid default null
)
returns table (vorname text, nachname text, email text)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_vorname text;
  v_nachname text;
  v_email text;
  v_full text;
begin
  select
    nullif(trim(p.vorname), ''),
    nullif(trim(p.nachname), ''),
    coalesce(nullif(trim(p.email), ''), u.email::text),
    nullif(trim(coalesce(
      u.raw_user_meta_data->>'full_name',
      u.raw_user_meta_data->>'name',
      ''
    )), '')
  into v_vorname, v_nachname, v_email, v_full
  from auth.users u
  left join profiles p on p.id = u.id
  where u.id = p_profile_id;

  if v_vorname is null and v_nachname is null and v_full is not null then
    v_vorname := nullif(split_part(v_full, ' ', 1), '');
    v_nachname := nullif(trim(regexp_replace(v_full, '^\S+\s*', '')), '');
  end if;

  if v_vorname is null then
    select nullif(trim(u.raw_user_meta_data->>'given_name'), ''),
           coalesce(v_nachname, nullif(trim(u.raw_user_meta_data->>'family_name'), ''))
    into v_vorname, v_nachname
    from auth.users u
    where u.id = p_profile_id;
  end if;

  if p_organisation_id is not null then
    select
      coalesce(v_vorname, nullif(trim(op.vorname), '')),
      coalesce(v_nachname, nullif(trim(op.nachname), '')),
      coalesce(v_email, nullif(trim(op.email), ''))
    into v_vorname, v_nachname, v_email
    from org_personen op
    where op.organisation_id = p_organisation_id
      and op.profile_id = p_profile_id
      and op.aktiv = true
    limit 1;
  end if;

  if (v_vorname is null or v_nachname is null) and p_organisation_id is not null then
    select
      coalesce(v_vorname, nullif(trim(al.vorname), '')),
      coalesce(v_nachname, nullif(trim(al.nachname), '')),
      coalesce(v_email, nullif(trim(al.email), ''))
    into v_vorname, v_nachname, v_email
    from anmeldungen_leiter al
    join lager l on l.id = al.lager_id
    where l.organisation_id = p_organisation_id
      and al.profile_id = p_profile_id
      and nullif(trim(al.vorname), '') is not null
    order by al.created_at desc
    limit 1;
  end if;

  if coalesce(trim(v_nachname), '') = '' and coalesce(trim(v_vorname), '') like '% %' then
    v_nachname := nullif(trim(regexp_replace(v_vorname, '^\S+\s*', '')), '');
    v_vorname := nullif(trim(split_part(v_vorname, ' ', 1)), '');
  end if;

  return query select coalesce(v_vorname, ''), coalesce(v_nachname, ''), coalesce(v_email, '');
end;
$$;

create or replace function public.lager_leiter_aus_verein_hinzufuegen(
  p_lager_id uuid,
  p_profile_id uuid default null,
  p_org_person_id uuid default null,
  p_als_lalei boolean default false,
  p_anwesend_von date default null,
  p_anwesend_bis date default null,
  p_vorname text default null,
  p_nachname text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_profile_id uuid;
  v_vorname text;
  v_nachname text;
  v_email text;
  v_telefon text;
  v_person org_personen%rowtype;
  v_anmeldung_id uuid;
  v_start date;
  v_ende date;
  v_aufloesung record;
begin
  if not public.can_access_lager(p_lager_id) then
    raise exception 'Kein Zugriff auf dieses Lager.';
  end if;

  select organisation_id, start_datum, end_datum
  into v_org_id, v_start, v_ende
  from lager where id = p_lager_id;

  if v_org_id is null then
    raise exception 'Lager hat keine Organisation.';
  end if;

  if p_profile_id is not null then
    v_profile_id := p_profile_id;
    if not exists (
      select 1 from organisation_mitglieder om
      where om.organisation_id = v_org_id
        and om.profile_id = v_profile_id
        and om.status = 'mitglied'
    ) then
      raise exception 'Person ist kein bestätigtes Vereinsmitglied.';
    end if;

    select * into v_aufloesung
    from public.profile_namen_aufloesen(v_profile_id, v_org_id);

    v_vorname := coalesce(nullif(trim(p_vorname), ''), v_aufloesung.vorname);
    v_nachname := coalesce(nullif(trim(p_nachname), ''), v_aufloesung.nachname);
    v_email := v_aufloesung.email;

    select p.telefon into v_telefon
    from profiles p where p.id = v_profile_id;

  elsif p_org_person_id is not null then
    select * into v_person
    from org_personen
    where id = p_org_person_id
      and organisation_id = v_org_id
      and aktiv = true;

    if not found then
      raise exception 'Manueller Vereinseintrag nicht gefunden.';
    end if;

    v_profile_id := v_person.profile_id;
    v_vorname := coalesce(nullif(trim(p_vorname), ''), v_person.vorname);
    v_nachname := coalesce(nullif(trim(p_nachname), ''), v_person.nachname);
    v_email := v_person.email;
    v_telefon := v_person.telefon;
  else
    raise exception 'profile_id oder org_person_id erforderlich.';
  end if;

  if coalesce(trim(v_nachname), '') = '' and coalesce(trim(v_vorname), '') like '% %' then
    v_nachname := trim(regexp_replace(v_vorname, '^\S+\s*', ''));
    v_vorname := split_part(v_vorname, ' ', 1);
  end if;

  if coalesce(trim(v_vorname), '') = '' or coalesce(trim(v_nachname), '') = '' then
    raise exception 'Vor- und Nachname fehlen. Bitte im Verein Profil ergänzen.';
  end if;

  if exists (
    select 1 from anmeldungen_leiter al
    where al.lager_id = p_lager_id
      and (
        (v_profile_id is not null and al.profile_id = v_profile_id)
        or (lower(al.vorname) = lower(v_vorname) and lower(al.nachname) = lower(v_nachname))
      )
  ) then
    raise exception 'Person ist bereits als Leiter in diesem Lager erfasst.';
  end if;

  if v_profile_id is not null then
    perform public.profil_leiter_daten_sync(v_profile_id, v_vorname, v_nachname, null, null, null, v_telefon);
  end if;

  insert into anmeldungen_leiter (
    lager_id, profile_id, vorname, nachname, email, telefon,
    anwesend_von, anwesend_bis, status, anmeldung_art, bestaetigen_bis
  )
  values (
    p_lager_id, v_profile_id, v_vorname, v_nachname, v_email, v_telefon,
    coalesce(p_anwesend_von, v_start),
    coalesce(p_anwesend_bis, v_ende),
    'bestaetigt', 'fix',
    case when v_start is not null then (v_start - interval '3 months')::date else null end
  )
  returning id into v_anmeldung_id;

  if v_profile_id is not null then
    insert into lager_leiter (lager_id, profile_id, rolle, status)
    values (
      p_lager_id,
      v_profile_id,
      case when p_als_lalei then 'lagerleitung' else 'leiter' end,
      'bestaetigt'
    )
    on conflict (lager_id, profile_id) do update set
      rolle = case
        when p_als_lalei then 'lagerleitung'
        when lager_leiter.rolle = 'lagerleitung' then 'lagerleitung'
        else excluded.rolle
      end,
      status = 'bestaetigt';
  end if;

  return v_anmeldung_id;
end;
$$;

grant execute on function public.lager_leiter_aus_verein_hinzufuegen(uuid, uuid, uuid, boolean, date, date, text, text) to authenticated;

create or replace function public.list_verein_personen_fuer_lager(p_organisation_id uuid)
returns table (
  id text,
  profile_id uuid,
  vorname text,
  nachname text,
  email text,
  quelle text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet';
  end if;

  if not public.is_org_mitglied(p_organisation_id)
    and not public.is_org_leitung(p_organisation_id)
    and not exists (
      select 1
      from lager l
      where l.organisation_id = p_organisation_id
        and public.can_access_lager(l.id)
    ) then
    raise exception 'Kein Zugriff auf diese Organisation';
  end if;

  return query
  with login_mitglieder as (
    select
      ('login-' || om.profile_id::text) as rid,
      om.profile_id as rprofile_id,
      n.vorname as rvorname,
      n.nachname as rnachname,
      n.email as remail
    from organisation_mitglieder om
    cross join lateral public.profile_namen_aufloesen(om.profile_id, p_organisation_id) n
    where om.organisation_id = p_organisation_id
      and om.status = 'mitglied'
  )
  select
    lm.rid,
    lm.rprofile_id,
    coalesce(lm.rvorname, ''),
    coalesce(lm.rnachname, ''),
    lm.remail,
    'login'::text
  from login_mitglieder lm
  union all
  select
    ('person-' || op.id::text),
    op.profile_id,
    op.vorname,
    op.nachname,
    op.email,
    case when op.profile_id is null then 'manuell' else 'login_verknuepft' end
  from org_personen op
  where op.organisation_id = p_organisation_id
    and op.aktiv = true
    and (
      op.profile_id is null
      or not exists (
        select 1 from login_mitglieder lm where lm.rprofile_id = op.profile_id
      )
    )
  order by 4, 3;
end;
$$;

-- ---------------------------------------------------------------------
-- Kalender: Titel = Grobprogramm dieser Woche oder Verein – Motto
-- ---------------------------------------------------------------------
create or replace function public.lager_kalender_titel(p_lager_id uuid)
returns text
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_lager lager%rowtype;
  v_org_name text;
  v_motto text;
  v_grob text;
  v_montag date;
  v_sonntag date;
begin
  select * into v_lager from lager where id = p_lager_id;
  if not found then return 'Lager'; end if;

  select o.name into v_org_name
  from organisation o
  where o.id = v_lager.organisation_id;

  v_motto := coalesce(nullif(trim(v_lager.motto), ''), nullif(trim(v_lager.name), ''));

  v_montag := date_trunc('week', coalesce(v_lager.start_datum, current_date))::date;
  v_sonntag := v_montag + 6;

  select string_agg(
    trim(coalesce(pb.code, '') || coalesce(' ' || pb.nummer, '') || ': ' || pb.titel),
    ', ' order by pb.tag, pb.start_zeit nulls last
  )
  into v_grob
  from programmbloecke pb
  where pb.lager_id = p_lager_id
    and pb.tag is not null
    and pb.tag between v_montag and v_sonntag;

  if coalesce(v_grob, '') <> '' then
    return left(v_grob, 240);
  end if;

  if v_org_name is not null and v_motto is not null then
    return v_org_name || ' – ' || v_motto;
  end if;

  return coalesce(v_lager.name, 'Lager');
end;
$$;

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
  v_i int := 0;
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
    v_i := v_i + 1;
    v_ics := v_ics || 'BEGIN:VEVENT' || chr(13) || chr(10)
      || 'UID:lager-' || p_lager_id::text || '-termin-' || v_i || '@stoecklilager.com' || chr(13) || chr(10)
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
    v_i := v_i + 1;
    v_ics := v_ics || 'BEGIN:VEVENT' || chr(13) || chr(10)
      || 'UID:lager-' || p_lager_id::text || '-prog-' || v_i || '@stoecklilager.com' || chr(13) || chr(10);
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

grant execute on function public.profile_namen_aufloesen(uuid, uuid) to authenticated;
grant execute on function public.lager_kalender_titel(uuid) to authenticated;
