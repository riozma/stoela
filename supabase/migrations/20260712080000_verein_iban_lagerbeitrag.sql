-- IBAN für Lagerbeitrags-Überweisungen: vereinsweit, über die Jahre
-- gleich, nur vom Vereins-Admin editierbar. RLS-Policies für dieselbe
-- Aktion werden per OR kombiniert, deshalb reicht eine zusätzliche
-- Policy nicht, um nur Admins zuzulassen (Leitung dürfte über die
-- bestehende Policy sonst ebenfalls schreiben) -> Trigger stattdessen.
alter table organisation add column if not exists iban text;
alter table organisation add column if not exists iban_kontoinhaber text;

create or replace function public.organisation_iban_nur_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (new.iban is distinct from old.iban or new.iban_kontoinhaber is distinct from old.iban_kontoinhaber)
    and not public.is_org_admin(old.id) then
    raise exception 'Nur Vereins-Admins können die IBAN ändern.';
  end if;
  return new;
end;
$$;

drop trigger if exists organisation_iban_nur_admin_trg on organisation;
create trigger organisation_iban_nur_admin_trg
  before update on organisation
  for each row
  execute function public.organisation_iban_nur_admin();

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
    join anmeldungen_leiter al on al.lager_id = ll.lager_id and al.profile_id = ll.profile_id
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
      'iban', v_org.iban,
      'iban_kontoinhaber', v_org.iban_kontoinhaber,
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
