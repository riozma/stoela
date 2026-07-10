-- Öffentliche Termine (Elternabend/Kennenlernabend/Diashow) mit Uhrzeit,
-- TN-Anmeldung auch bei Status laufend, Kuchenstand + Skiweekend Kalender-Sync

-- ---------------------------------------------------------------------
-- Hilfsfunktion: Datum aus Elterninfo-Text (ISO oder Präfix)
-- ---------------------------------------------------------------------
create or replace function public.cfg_text_to_datum(p_text text)
returns date
language plpgsql
immutable
as $$
declare
  v text := trim(coalesce(p_text, ''));
begin
  if v = '' then return null; end if;
  if v ~ '^\d{4}-\d{2}-\d{2}' then
    return substring(v from 1 for 10)::date;
  end if;
  if v ~ '^\d{1,2}\.\d{1,2}\.\d{4}' then
    return to_date(substring(v from '^\d{1,2}\.\d{1,2}\.\d{4}'), 'DD.MM.YYYY');
  end if;
  return null;
exception when others then
  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- Upsert mit optionaler Uhrzeit
-- ---------------------------------------------------------------------
create or replace function public.lager_termin_upsert_cfg(
  p_lager_id uuid,
  p_typ text,
  p_titel text,
  p_start_datum date,
  p_end_datum date default null,
  p_ort text default null,
  p_oeffentlich boolean default false,
  p_sortierung int default 0,
  p_start_zeit time default null,
  p_end_zeit time default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_start_datum is null then return; end if;

  insert into lager_termine (
    lager_id, typ, titel, start_datum, end_datum, start_zeit, end_zeit,
    ort, oeffentlich, sortierung
  )
  values (
    p_lager_id, p_typ, p_titel, p_start_datum, p_end_datum, p_start_zeit, p_end_zeit,
    p_ort, p_oeffentlich, p_sortierung
  )
  on conflict (lager_id, typ) where typ in (
    'lager', 'elternabend', 'kennenlernabend', 'diashow', 'vorweekend', 'skiweekend', 'hoeck'
  )
  do update set
    titel = excluded.titel,
    start_datum = excluded.start_datum,
    end_datum = excluded.end_datum,
    start_zeit = coalesce(excluded.start_zeit, lager_termine.start_zeit),
    end_zeit = coalesce(excluded.end_zeit, lager_termine.end_zeit),
    ort = coalesce(excluded.ort, lager_termine.ort),
    oeffentlich = excluded.oeffentlich,
    sortierung = excluded.sortierung,
    updated_at = now();
end;
$$;

-- ---------------------------------------------------------------------
-- Öffentliche Termine anlegen/ändern (Kalender + Teilnehmer)
-- ---------------------------------------------------------------------
create or replace function public.lager_termin_oeffentlich_upsert(
  p_lager_id uuid,
  p_typ text,
  p_start_datum date,
  p_end_datum date default null,
  p_start_zeit time default null,
  p_end_zeit time default null,
  p_ort text default null,
  p_nur_ein_tag boolean default true,
  p_termin_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_t lager_termine%rowtype;
  v_cfg jsonb;
  v_datum text;
  v_zeit text;
  v_end date;
  v_cfg_key_datum text;
  v_cfg_key_ort text;
  v_cfg_key_zeit text;
  v_titel text;
begin
  if p_typ not in ('elternabend', 'kennenlernabend', 'diashow') then
    raise exception 'Ungültiger Termintyp.';
  end if;
  if not public.can_access_lager(p_lager_id) then
    raise exception 'Kein Zugriff auf dieses Lager.';
  end if;
  if p_start_datum is null then
    raise exception 'Startdatum ist Pflicht.';
  end if;

  v_end := case when p_nur_ein_tag or p_end_datum is null then p_start_datum else p_end_datum end;

  v_titel := case p_typ
    when 'elternabend' then 'Elternabend'
    when 'kennenlernabend' then 'Kennenlernabend'
    else 'Diashow / Lagerrückblick'
  end;

  if p_termin_id is not null then
    select * into v_t from lager_termine where id = p_termin_id and lager_id = p_lager_id;
  else
    select * into v_t from lager_termine where lager_id = p_lager_id and typ = p_typ limit 1;
  end if;

  if v_t.id is not null then
    update lager_termine
    set start_datum = p_start_datum,
        end_datum = v_end,
        start_zeit = p_start_zeit,
        end_zeit = p_end_zeit,
        ort = nullif(trim(p_ort), ''),
        oeffentlich = true,
        updated_at = now()
    where id = v_t.id;
  else
    insert into lager_termine (
      lager_id, typ, titel, start_datum, end_datum, start_zeit, end_zeit, ort, oeffentlich, sortierung
    )
    values (
      p_lager_id, p_typ, v_titel, p_start_datum, v_end, p_start_zeit, p_end_zeit,
      nullif(trim(p_ort), ''), true,
      case p_typ when 'elternabend' then 20 when 'kennenlernabend' then 30 else 40 end
    )
    returning * into v_t;
  end if;

  v_datum := to_char(p_start_datum, 'YYYY-MM-DD');
  v_zeit := case when p_start_zeit is not null then to_char(p_start_zeit, 'HH24:MI') else null end;

  case p_typ
    when 'elternabend' then
      v_cfg_key_datum := 'elternabend_datum';
      v_cfg_key_ort := 'elternabend_ort';
      v_cfg_key_zeit := 'elternabend_zeit';
    when 'kennenlernabend' then
      v_cfg_key_datum := 'kennenlernabend_datum';
      v_cfg_key_ort := 'kennenlernabend_ort';
      v_cfg_key_zeit := 'kennenlernabend_zeit';
    when 'diashow' then
      v_cfg_key_datum := 'diashow_datum';
      v_cfg_key_ort := 'diashow_ort';
      v_cfg_key_zeit := 'diashow_zeit';
  end case;

  select coalesce(elterninfo_config, '{}'::jsonb) into v_cfg from lager where id = p_lager_id;

  v_cfg := v_cfg
    || jsonb_build_object(v_cfg_key_datum, v_datum)
    || jsonb_build_object(v_cfg_key_ort, coalesce(nullif(trim(p_ort), ''), v_cfg->>v_cfg_key_ort, ''))
    || jsonb_build_object(v_cfg_key_zeit, coalesce(v_zeit, v_cfg->>v_cfg_key_zeit, ''));

  update lager set elterninfo_config = v_cfg where id = p_lager_id;

  return v_t.id;
end;
$$;

grant execute on function public.lager_termin_oeffentlich_upsert(uuid, text, date, date, time, time, text, boolean, uuid) to authenticated;

-- Alte Funktion delegiert an neue (mit Uhrzeit)
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
begin
  select * into v_t from lager_termine where id = p_termin_id;
  if not found then raise exception 'Termin nicht gefunden.'; end if;

  perform public.lager_termin_oeffentlich_upsert(
    v_t.lager_id,
    v_t.typ,
    p_start_datum,
    p_end_datum,
    v_t.start_zeit,
    v_t.end_zeit,
    p_ort,
    p_nur_ein_tag,
    p_termin_id
  );
end;
$$;

-- ---------------------------------------------------------------------
-- Sync: Elterninfo flexibel, Kuchenstand, Skiweekend
-- ---------------------------------------------------------------------
create or replace function public.lager_termine_sync(p_lager_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager lager%rowtype;
  v_cfg jsonb;
  v_datum date;
  v_zeit time;
  v_ski org_skiweekend%rowtype;
  r record;
begin
  select * into v_lager from lager where id = p_lager_id;
  if not found then return; end if;

  perform public.lager_termine_dedupe(p_lager_id);

  v_cfg := coalesce(v_lager.elterninfo_config, '{}'::jsonb);

  if v_lager.start_datum is not null then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'lager', coalesce(v_lager.name, 'Lager'),
      v_lager.start_datum, v_lager.end_datum,
      v_lager.ort, true, 0
    );
  else
    delete from lager_termine where lager_id = p_lager_id and typ = 'lager';
  end if;

  if v_lager.vorweekend_start is not null then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'vorweekend', 'Vorweekend',
      v_lager.vorweekend_start, v_lager.vorweekend_ende,
      null, false, 10
    );
  else
    delete from lager_termine where lager_id = p_lager_id and typ = 'vorweekend';
  end if;

  -- Elternabend / Kennenlernabend / Diashow (flexibles Datum + Uhrzeit)
  v_datum := public.cfg_text_to_datum(v_cfg->>'elternabend_datum');
  if v_datum is not null then
    v_zeit := nullif(v_cfg->>'elternabend_zeit', '')::time;
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'elternabend', 'Elternabend', v_datum, null,
      nullif(v_cfg->>'elternabend_ort', ''), true, 20, v_zeit, null
    );
  else
    delete from lager_termine where lager_id = p_lager_id and typ = 'elternabend';
  end if;

  v_datum := public.cfg_text_to_datum(v_cfg->>'kennenlernabend_datum');
  if v_datum is not null then
    v_zeit := nullif(v_cfg->>'kennenlernabend_zeit', '')::time;
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'kennenlernabend', 'Kennenlernabend', v_datum, null,
      nullif(v_cfg->>'kennenlernabend_ort', ''), true, 30, v_zeit, null
    );
  else
    delete from lager_termine where lager_id = p_lager_id and typ = 'kennenlernabend';
  end if;

  v_datum := public.cfg_text_to_datum(v_cfg->>'diashow_datum');
  if v_datum is null then
    v_datum := public.cfg_text_to_datum(v_cfg->>'lagerrueckblick_datum');
  end if;
  if v_datum is not null then
    v_zeit := coalesce(nullif(v_cfg->>'diashow_zeit', '')::time, nullif(v_cfg->>'lagerrueckblick_zeit', '')::time);
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'diashow', 'Diashow / Lagerrückblick', v_datum, null,
      coalesce(nullif(v_cfg->>'diashow_ort', ''), nullif(v_cfg->>'lagerrueckblick_ort', '')), true, 40, v_zeit, null
    );
  else
    delete from lager_termine where lager_id = p_lager_id and typ = 'diashow';
  end if;

  -- Skiweekend aus Organisation (Ämtli) – kein manueller Duplikat
  if v_lager.organisation_id is not null then
    select * into v_ski
    from org_skiweekend
    where organisation_id = v_lager.organisation_id and jahr = v_lager.jahr
    limit 1;

    if v_ski.id is not null and v_ski.start_datum is not null then
      perform public.lager_termin_upsert_cfg(
        p_lager_id, 'skiweekend', 'Skiweekend ' || v_ski.jahr::text,
        v_ski.start_datum, v_ski.end_datum,
        v_ski.ort, true, 50
      );
    else
      delete from lager_termine where lager_id = p_lager_id and typ = 'skiweekend';
    end if;
  end if;

  -- Kuchenstand-Standorte -> sonstiges (mehrere erlaubt)
  delete from lager_termine
  where lager_id = p_lager_id
    and typ = 'sonstiges'
    and coalesce(beschreibung, '') like 'sync:kuchenstand:%';

  for r in
    select id, ort, datum, notiz
    from kuchenstand_standorte
    where lager_id = p_lager_id and datum is not null
    order by sortierung, created_at
  loop
    insert into lager_termine (
      lager_id, typ, titel, start_datum, end_datum, ort, beschreibung, oeffentlich, sortierung
    )
    values (
      p_lager_id, 'sonstiges', 'Kuchenstand: ' || r.ort, r.datum, r.datum, r.ort,
      'sync:kuchenstand:' || r.id::text,
      true, 60
    );
  end loop;

  perform public.lager_termine_dedupe(p_lager_id);
end;
$$;

-- ---------------------------------------------------------------------
-- TN-Anmeldung auch bei Status laufend
-- ---------------------------------------------------------------------
create or replace function public.lager_erlaubt_tn_anmeldung(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from lager l
    where l.id = p_lager_id
      and l.status in ('anmeldung_offen', 'laufend')
  );
$$;

drop policy if exists "tn_eltern_kontakte: insert bei offener anmeldung" on tn_eltern_kontakte;
create policy "tn_eltern_kontakte: insert bei offener anmeldung" on tn_eltern_kontakte
  for insert to anon, authenticated
  with check (public.lager_erlaubt_tn_anmeldung(lager_id));

drop policy if exists "tn_anmeldung_dokumente: insert bei offener anmeldung" on tn_anmeldung_dokumente;
create policy "tn_anmeldung_dokumente: insert bei offener anmeldung" on tn_anmeldung_dokumente
  for insert to anon, authenticated
  with check (
    exists (
      select 1
      from anmeldungen_tn t
      where t.id = anmeldung_tn_id and public.lager_erlaubt_tn_anmeldung(t.lager_id)
    )
  );

create or replace function public.get_lager_tn_anmeldung_info(p_lager_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager lager%rowtype;
  v_org_felder jsonb := '{}'::jsonb;
  v_cfg jsonb := '{}'::jsonb;
  v_merged jsonb;
  v_kontakt_name text;
  v_kontakt_email text;
  v_kontakt_telefon text;
  v_kontakt_adresse text;
  v_lageradresse text;
  v_lagertelefon text;
  v_elternabend text;
  v_elternabend_ort text;
  v_kennenlern text;
  v_kennenlern_ort text;
  v_diashow text;
  v_diashow_ort text;
  v_t lager_termine%rowtype;
begin
  select * into v_lager from lager
  where id = p_lager_id and status in ('anmeldung_offen', 'laufend');
  if not found then return null; end if;

  perform public.lager_termine_sync(p_lager_id);

  if v_lager.organisation_id is not null then
    select felder into v_org_felder from org_elterninfo_vorlage where organisation_id = v_lager.organisation_id;
  end if;

  v_cfg := coalesce(v_lager.elterninfo_config, '{}'::jsonb);
  v_merged := coalesce(v_org_felder, '{}'::jsonb) || v_cfg;

  select * into v_t from lager_termine where lager_id = p_lager_id and typ = 'elternabend' limit 1;
  if v_t.id is not null and v_t.start_datum is not null then
    v_elternabend := to_char(v_t.start_datum, 'DD.MM.YYYY');
    if v_t.start_zeit is not null then v_elternabend := v_elternabend || ', ' || to_char(v_t.start_zeit, 'HH24:MI'); end if;
    v_elternabend_ort := coalesce(v_t.ort, '');
  else
    v_elternabend := coalesce(v_merged->>'elternabend_datum', '');
    v_elternabend_ort := coalesce(v_merged->>'elternabend_ort', '');
  end if;

  select * into v_t from lager_termine where lager_id = p_lager_id and typ = 'kennenlernabend' limit 1;
  if v_t.id is not null and v_t.start_datum is not null then
    v_kennenlern := to_char(v_t.start_datum, 'DD.MM.YYYY');
    if v_t.start_zeit is not null then v_kennenlern := v_kennenlern || ', ' || to_char(v_t.start_zeit, 'HH24:MI'); end if;
    v_kennenlern_ort := coalesce(v_t.ort, '');
  else
    v_kennenlern := coalesce(v_merged->>'kennenlernabend_datum', '');
    v_kennenlern_ort := coalesce(v_merged->>'kennenlernabend_ort', '');
  end if;

  select * into v_t from lager_termine where lager_id = p_lager_id and typ = 'diashow' limit 1;
  if v_t.id is not null and v_t.start_datum is not null then
    v_diashow := to_char(v_t.start_datum, 'DD.MM.YYYY');
    if v_t.start_zeit is not null then v_diashow := v_diashow || ', ' || to_char(v_t.start_zeit, 'HH24:MI'); end if;
    v_diashow_ort := coalesce(v_t.ort, '');
  else
    v_diashow := coalesce(v_merged->>'diashow_datum', v_merged->>'lagerrueckblick_datum', '');
    v_diashow_ort := coalesce(v_merged->>'diashow_ort', v_merged->>'lagerrueckblick_ort', '');
  end if;

  v_kontakt_name := nullif(trim(coalesce(v_merged->>'lagerleiter_name', v_merged->>'kontakt_name', '')), '');
  v_kontakt_email := nullif(trim(coalesce(v_merged->>'lagerleiter_email', v_merged->>'kontakt_email', '')), '');
  v_kontakt_telefon := nullif(trim(coalesce(v_merged->>'lagerleiter_telefon', v_merged->>'kontakt_telefon', '')), '');
  v_kontakt_adresse := nullif(trim(v_merged->>'lagerleiter_adresse'), '');

  if v_kontakt_name is null or v_kontakt_email is null then
    select
      coalesce(v_kontakt_name, nullif(trim(concat_ws(' ', al.vorname, al.nachname)), '')),
      coalesce(v_kontakt_email, nullif(trim(al.email), '')),
      coalesce(v_kontakt_telefon, nullif(trim(al.telefon), ''))
    into v_kontakt_name, v_kontakt_email, v_kontakt_telefon
    from lager_leiter ll
    join anmeldungen_leiter al on al.id = ll.anmeldung_leiter_id
    where ll.lager_id = p_lager_id and ll.rolle = 'lagerleitung' and ll.status = 'bestaetigt'
    order by al.nachname, al.vorname limit 1;
  end if;

  v_lageradresse := nullif(trim(coalesce(v_merged->>'lageradresse', v_lager.ort, '')), '');
  v_lagertelefon := nullif(trim(coalesce(v_merged->>'lagertelefon', v_lager.telefon_zeiten, '')), '');

  return json_build_object(
    'id', v_lager.id, 'name', v_lager.name, 'jahr', v_lager.jahr,
    'ort', v_lager.ort, 'start_datum', v_lager.start_datum, 'end_datum', v_lager.end_datum,
    'status', v_lager.status, 'organisation_id', v_lager.organisation_id,
    'info', json_build_object(
      'beschreibung', coalesce(v_merged->>'beschreibung', v_merged->>'lager_beschreibung', ''),
      'lagerart', coalesce(v_merged->>'lagerart', 'Sommerlager im Haus, J+S-Lager'),
      'durchgefuehrt_von', coalesce(v_merged->>'durchgefuehrt_von', 'Jubla Stöcklilager Zuchwil'),
      'anmeldeschluss', coalesce(v_merged->>'anmeldeschluss', v_merged->>'anmeldeschluss_datum', ''),
      'mindestalter', coalesce(v_merged->>'mindestalter', ''),
      'max_teilnehmer', coalesce(v_merged->>'max_teilnehmer', '50'),
      'kosten_erstes_kind', coalesce((v_merged->>'lagerbeitrag_tn')::int, (v_merged->>'lagerbeitrag')::int, 340),
      'kosten_weiteres_kind', coalesce((v_merged->>'lagerbeitrag_geschwister')::int, 280),
      'kontakt_name', coalesce(v_kontakt_name, ''),
      'kontakt_email', coalesce(v_kontakt_email, 'info@stoecklilager.com'),
      'kontakt_telefon', coalesce(v_kontakt_telefon, ''),
      'kontakt_adresse', coalesce(v_kontakt_adresse, ''),
      'lageradresse', coalesce(v_lageradresse, ''),
      'lagertelefon', coalesce(v_lagertelefon, ''),
      'elternabend_datum', v_elternabend,
      'elternabend_ort', v_elternabend_ort,
      'kennenlernabend_datum', v_kennenlern,
      'kennenlernabend_ort', v_kennenlern_ort,
      'lagerrueckblick_datum', v_diashow,
      'lagerrueckblick_ort', v_diashow_ort,
      'reise_besammlung', coalesce(v_merged->>'reise_besammlung', ''),
      'reise_abfahrt', coalesce(v_merged->>'reise_abfahrt', ''),
      'reise_rueckkehr', coalesce(v_merged->>'reise_rueckkehr', ''),
      'einzahlungsfrist', coalesce(v_merged->>'einzahlungsfrist', ''),
      'versicherung_hinweis', coalesce(v_merged->>'versicherung_hinweis', 'Versicherung ist Sache der Teilnehmenden.')
    )
  );
end;
$$;

grant execute on function public.get_lager_tn_anmeldung_info(uuid) to anon, authenticated;
