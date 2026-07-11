-- TN/HL-Alterseinteilung, vereinsweit konfigurierbar.
-- Mindestalter = Lagerjahr - tn_min_alter_jahre (jüngster erlaubter Jahrgang)
-- HL ab        = Lagerjahr - tn_hl_ab_jahre (Jahrgang <= diesem Wert -> HL statt TN)
-- Beispiel 2026 mit 8/14: Jahrgang <= 2018 darf sich anmelden, Jahrgang <= 2012 wird HL.

alter table organisation add column if not exists tn_min_alter_jahre int not null default 8;
alter table organisation add column if not exists tn_hl_ab_jahre int not null default 14;

-- ---------------------------------------------------------------------
-- get_lager_tn_anmeldung_info: zusätzlich die beiden Vereins-Werte liefern
-- ---------------------------------------------------------------------
create or replace function public.get_lager_tn_anmeldung_info(p_lager_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager lager%rowtype;
  v_org organisation%rowtype;
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
    select * into v_org from organisation where id = v_lager.organisation_id;
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
    'tn_min_alter_jahre', coalesce(v_org.tn_min_alter_jahre, 8),
    'tn_hl_ab_jahre', coalesce(v_org.tn_hl_ab_jahre, 14),
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
      'kontakt_email', coalesce(v_kontakt_email, ''),
      'kontakt_telefon', coalesce(v_kontakt_telefon, ''),
      'kontakt_adresse', coalesce(v_kontakt_adresse, ''),
      'lageradresse', coalesce(v_lageradresse, ''),
      'lagertelefon', coalesce(v_lagertelefon, ''),
      'elternabend_datum', nullif(v_elternabend, ''),
      'elternabend_ort', nullif(v_elternabend_ort, ''),
      'kennenlernabend_datum', nullif(v_kennenlern, ''),
      'kennenlernabend_ort', nullif(v_kennenlern_ort, ''),
      'lagerrueckblick_datum', nullif(v_diashow, ''),
      'lagerrueckblick_ort', nullif(v_diashow_ort, ''),
      'reise_besammlung', nullif(v_merged->>'reise_besammlung', ''),
      'reise_abfahrt', nullif(v_merged->>'reise_abfahrt', ''),
      'reise_rueckkehr', nullif(v_merged->>'reise_rueckkehr', ''),
      'einzahlungsfrist', nullif(v_merged->>'einzahlungsfrist', ''),
      'versicherung_hinweis', coalesce(v_merged->>'versicherung_hinweis', 'Kinder sind über die Eltern unfall- und krankenversichert.')
    )
  );
end;
$$;

-- ---------------------------------------------------------------------
-- tn_anmeldung_absenden: Rolle (TN/HL) serverseitig aus Jahrgang berechnen,
-- zu junge Anmeldungen ablehnen.
-- ---------------------------------------------------------------------
create or replace function public.tn_anmeldung_absenden(
  p_lager_id uuid,
  p_eltern jsonb,
  p_kinder jsonb
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager lager%rowtype;
  v_min_alter int := 8;
  v_hl_ab int := 14;
  v_min_jahrgang int;
  v_hl_jahrgang int;
  v_kontakt_id uuid;
  v_kind jsonb;
  v_tn_id uuid;
  v_ids jsonb := '[]'::jsonb;
  v_nr int := 0;
  v_jahrgang int;
  v_rolle text;
begin
  if not public.lager_erlaubt_tn_anmeldung(p_lager_id) then
    raise exception 'Die TN-Anmeldung ist für dieses Lager nicht geöffnet.';
  end if;

  select * into v_lager from lager where id = p_lager_id;

  if v_lager.organisation_id is not null then
    select tn_min_alter_jahre, tn_hl_ab_jahre into v_min_alter, v_hl_ab
    from organisation where id = v_lager.organisation_id;
    v_min_alter := coalesce(v_min_alter, 8);
    v_hl_ab := coalesce(v_hl_ab, 14);
  end if;
  v_min_jahrgang := v_lager.jahr - v_min_alter;
  v_hl_jahrgang := v_lager.jahr - v_hl_ab;

  if jsonb_typeof(p_kinder) <> 'array' or jsonb_array_length(p_kinder) = 0 then
    raise exception 'Mindestens ein Kind ist erforderlich.';
  end if;

  if nullif(trim(p_eltern->>'eltern_email'), '') is null
    or nullif(trim(p_eltern->>'eltern_vorname'), '') is null
    or nullif(trim(p_eltern->>'eltern_nachname'), '') is null
    or nullif(trim(p_eltern->>'telefon'), '') is null
    or nullif(trim(p_eltern->>'adresse'), '') is null
    or nullif(trim(p_eltern->>'plz'), '') is null
    or nullif(trim(p_eltern->>'ort'), '') is null then
    raise exception 'Elternkontakt ist unvollständig.';
  end if;

  insert into tn_eltern_kontakte (
    lager_id,
    eltern_email,
    eltern_vorname,
    eltern_nachname,
    telefon,
    adresse,
    plz,
    ort,
    aufenthaltsort,
    aufenthaltsort_unbekannt
  )
  values (
    p_lager_id,
    trim(p_eltern->>'eltern_email'),
    trim(p_eltern->>'eltern_vorname'),
    trim(p_eltern->>'eltern_nachname'),
    trim(p_eltern->>'telefon'),
    trim(p_eltern->>'adresse'),
    trim(p_eltern->>'plz'),
    trim(p_eltern->>'ort'),
    nullif(trim(p_eltern->>'aufenthaltsort'), ''),
    coalesce((p_eltern->>'aufenthaltsort_unbekannt')::boolean, false)
  )
  returning id into v_kontakt_id;

  for v_kind in select value from jsonb_array_elements(p_kinder)
  loop
    v_nr := v_nr + 1;

    if nullif(trim(v_kind->>'vorname'), '') is null
      or nullif(trim(v_kind->>'nachname'), '') is null
      or nullif(v_kind->>'geburtsdatum', '') is null
      or nullif(v_kind->>'geschlecht', '') is null
      or nullif(trim(v_kind->>'ahv_nr'), '') is null then
      raise exception 'Angaben für Kind % sind unvollständig.', v_nr;
    end if;

    v_jahrgang := extract(year from (v_kind->>'geburtsdatum')::date)::int;
    if v_jahrgang > v_min_jahrgang then
      raise exception 'Kind % (Jahrgang %) erfüllt das Mindestalter für dieses Lager nicht (frühester Jahrgang: %).',
        v_nr, v_jahrgang, v_min_jahrgang;
    end if;
    v_rolle := case when v_jahrgang <= v_hl_jahrgang then 'HL' else 'TN' end;

    insert into anmeldungen_tn (
      lager_id,
      vorname,
      nachname,
      geburtsdatum,
      geschlecht,
      rolle,
      ahv_nr,
      allergien,
      essensgewohnheiten,
      essensgewohnheiten_sonstiges,
      medikamente,
      gesundheit_bemerkungen,
      sonstige_info,
      eltern_email,
      eltern_aufenthaltsort,
      notfallkontakt,
      eltern_kontakt_id,
      kind_nr
    )
    values (
      p_lager_id,
      trim(v_kind->>'vorname'),
      trim(v_kind->>'nachname'),
      (v_kind->>'geburtsdatum')::date,
      v_kind->>'geschlecht',
      v_rolle,
      trim(v_kind->>'ahv_nr'),
      nullif(trim(v_kind->>'allergien'), ''),
      nullif(trim(v_kind->>'essensgewohnheiten'), ''),
      nullif(trim(v_kind->>'essensgewohnheiten_sonstiges'), ''),
      nullif(trim(v_kind->>'medikamente'), ''),
      nullif(trim(v_kind->>'gesundheit_bemerkungen'), ''),
      nullif(trim(v_kind->>'sonstige_info'), ''),
      trim(p_eltern->>'eltern_email'),
      case
        when coalesce((p_eltern->>'aufenthaltsort_unbekannt')::boolean, false)
          then 'Wird später mitgeteilt'
        else nullif(trim(p_eltern->>'aufenthaltsort'), '')
      end,
      trim(p_eltern->>'eltern_vorname') || ' ' || trim(p_eltern->>'eltern_nachname')
        || ' · ' || trim(p_eltern->>'telefon'),
      v_kontakt_id,
      v_nr
    )
    returning id into v_tn_id;

    v_ids := v_ids || jsonb_build_array(jsonb_build_object('index', v_nr - 1, 'id', v_tn_id, 'rolle', v_rolle));
  end loop;

  return json_build_object(
    'eltern_kontakt_id', v_kontakt_id,
    'anmeldungen', v_ids
  );
end;
$$;

revoke all on function public.tn_anmeldung_absenden(uuid, jsonb, jsonb) from public;
grant execute on function public.tn_anmeldung_absenden(uuid, jsonb, jsonb) to anon, authenticated;
