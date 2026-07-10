-- Vereins-Links & Zugänge (sichtbarkeitsgesteuert) + dynamische TN-Lagerinfo

-- ---------------------------------------------------------------------
-- org_ressourcen: Links (URL) und Zugänge (Benutzer/Passwort)
-- Kein direkter Tabellenzugriff – nur über Security-Definer-RPCs
-- ---------------------------------------------------------------------
create table if not exists org_ressourcen (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisation (id) on delete cascade,
  typ text not null check (typ in ('link', 'zugang')),
  titel text not null,
  url text,
  benutzername text,
  passwort text,
  notiz text,
  sichtbarkeit text not null default 'alle'
    check (sichtbarkeit in ('alle', 'leitung', 'admin', 'ausgewaehlt')),
  sortierung int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references profiles (id) on delete set null
);

create table if not exists org_ressourcen_zugriff (
  ressource_id uuid not null references org_ressourcen (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete cascade,
  primary key (ressource_id, profile_id)
);

create index if not exists org_ressourcen_org_idx on org_ressourcen (organisation_id, sortierung);
create index if not exists org_ressourcen_zugriff_profile_idx on org_ressourcen_zugriff (profile_id);

alter table org_ressourcen enable row level security;
alter table org_ressourcen_zugriff enable row level security;

-- Keine direkten SELECT/INSERT/UPDATE/DELETE-Policies – Zugriff nur via RPC

create or replace function public.org_ressource_darf_sehen(
  p_organisation_id uuid,
  p_sichtbarkeit text,
  p_ressource_id uuid
)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  if not public.is_org_mitglied(p_organisation_id) then
    return false;
  end if;

  case p_sichtbarkeit
    when 'alle' then return true;
    when 'leitung' then return public.is_org_leitung(p_organisation_id);
    when 'admin' then return public.is_org_admin(p_organisation_id);
    when 'ausgewaehlt' then
      return exists (
        select 1
        from org_ressourcen_zugriff z
        where z.ressource_id = p_ressource_id
          and z.profile_id = auth.uid()
      );
    else return false;
  end case;
end;
$$;

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
    case when r.typ = 'link' then r.url else null end as url,
    case when r.typ = 'zugang' then r.benutzername else null end as benutzername,
    case when r.typ = 'zugang' then r.passwort else null end as passwort,
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
    ) as zugewiesene_profile_ids
  from org_ressourcen r
  where r.organisation_id = p_organisation_id
    and public.org_ressource_darf_sehen(r.organisation_id, r.sichtbarkeit, r.id)
  order by r.sortierung, r.titel;
end;
$$;

create or replace function public.org_ressource_speichern(
  p_organisation_id uuid,
  p_id uuid default null,
  p_typ text default 'link',
  p_titel text default null,
  p_url text default null,
  p_benutzername text default null,
  p_passwort text default null,
  p_notiz text default null,
  p_sichtbarkeit text default 'alle',
  p_sortierung int default 0,
  p_zugewiesene_profile_ids uuid[] default '{}'::uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_titel text := nullif(trim(p_titel), '');
  v_pid uuid;
begin
  if not public.is_org_admin(p_organisation_id) then
    raise exception 'Nur Vereins-Admins dürfen Links und Zugänge verwalten.';
  end if;

  if v_titel is null then
    raise exception 'Titel ist Pflicht.';
  end if;

  if p_typ not in ('link', 'zugang') then
    raise exception 'Ungültiger Typ.';
  end if;

  if p_sichtbarkeit not in ('alle', 'leitung', 'admin', 'ausgewaehlt') then
    raise exception 'Ungültige Sichtbarkeit.';
  end if;

  if p_typ = 'link' and nullif(trim(p_url), '') is null then
    raise exception 'URL ist für Links Pflicht.';
  end if;

  if p_typ = 'zugang' and nullif(trim(p_benutzername), '') is null and nullif(trim(p_passwort), '') is null then
    raise exception 'Benutzername oder Passwort ist für Zugänge Pflicht.';
  end if;

  if p_id is null then
    insert into org_ressourcen (
      organisation_id, typ, titel, url, benutzername, passwort, notiz,
      sichtbarkeit, sortierung, created_by
    )
    values (
      p_organisation_id,
      p_typ,
      v_titel,
      nullif(trim(p_url), ''),
      nullif(trim(p_benutzername), ''),
      nullif(trim(p_passwort), ''),
      nullif(trim(p_notiz), ''),
      p_sichtbarkeit,
      coalesce(p_sortierung, 0),
      auth.uid()
    )
    returning id into v_id;
  else
    update org_ressourcen
    set
      typ = p_typ,
      titel = v_titel,
      url = nullif(trim(p_url), ''),
      benutzername = coalesce(nullif(trim(p_benutzername), ''), benutzername),
      passwort = coalesce(nullif(trim(p_passwort), ''), passwort),
      notiz = nullif(trim(p_notiz), ''),
      sichtbarkeit = p_sichtbarkeit,
      sortierung = coalesce(p_sortierung, sortierung),
      updated_at = now()
    where id = p_id
      and organisation_id = p_organisation_id
    returning id into v_id;

    if v_id is null then
      raise exception 'Eintrag nicht gefunden.';
    end if;
  end if;

  delete from org_ressourcen_zugriff where ressource_id = v_id;

  if p_sichtbarkeit = 'ausgewaehlt' then
    foreach v_pid in array coalesce(p_zugewiesene_profile_ids, '{}'::uuid[])
    loop
      if v_pid is null then continue; end if;
      if not exists (
        select 1 from organisation_mitglieder om
        where om.organisation_id = p_organisation_id
          and om.profile_id = v_pid
          and om.status = 'mitglied'
      ) then
        continue;
      end if;
      insert into org_ressourcen_zugriff (ressource_id, profile_id)
      values (v_id, v_pid)
      on conflict do nothing;
    end loop;
  end if;

  return v_id;
end;
$$;

create or replace function public.org_ressource_loeschen(
  p_organisation_id uuid,
  p_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_org_admin(p_organisation_id) then
    raise exception 'Nur Vereins-Admins dürfen Links und Zugänge löschen.';
  end if;

  delete from org_ressourcen
  where id = p_id
    and organisation_id = p_organisation_id;

  if not found then
    raise exception 'Eintrag nicht gefunden.';
  end if;
end;
$$;

grant execute on function public.list_org_ressourcen(uuid) to authenticated;
grant execute on function public.org_ressource_speichern(uuid, uuid, text, text, text, text, text, text, text, int, uuid[]) to authenticated;
grant execute on function public.org_ressource_loeschen(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- TN-Anmeldung: Lagerfelder + Elterninfo + Lalei-Kontakt dynamisch
-- ---------------------------------------------------------------------
create or replace function public.get_lager_tn_anmeldung_info(p_lager_id uuid)
returns json
language plpgsql
security definer
stable
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
begin
  select * into v_lager from lager where id = p_lager_id and status = 'anmeldung_offen';
  if not found then
    return null;
  end if;

  if v_lager.organisation_id is not null then
    select felder into v_org_felder
    from org_elterninfo_vorlage
    where organisation_id = v_lager.organisation_id;
  end if;

  v_cfg := coalesce(v_lager.elterninfo_config, '{}'::jsonb);
  v_merged := coalesce(v_org_felder, '{}'::jsonb) || v_cfg;

  v_kontakt_name := nullif(trim(coalesce(
    v_merged->>'lagerleiter_name',
    v_merged->>'kontakt_name',
    ''
  )), '');

  v_kontakt_email := nullif(trim(coalesce(
    v_merged->>'lagerleiter_email',
    v_merged->>'kontakt_email',
    ''
  )), '');

  v_kontakt_telefon := nullif(trim(coalesce(
    v_merged->>'lagerleiter_telefon',
    v_merged->>'kontakt_telefon',
    ''
  )), '');

  v_kontakt_adresse := nullif(trim(coalesce(
    v_merged->>'lagerleiter_adresse',
    ''
  )), '');

  -- Fallback: bestätigte Lagerleitung aus dem Lager
  if v_kontakt_name is null or v_kontakt_email is null then
    select
      coalesce(v_kontakt_name, nullif(trim(concat_ws(' ', al.vorname, al.nachname)), '')),
      coalesce(v_kontakt_email, nullif(trim(al.email), '')),
      coalesce(v_kontakt_telefon, nullif(trim(al.telefon), ''))
    into v_kontakt_name, v_kontakt_email, v_kontakt_telefon
    from lager_leiter ll
    join anmeldungen_leiter al on al.id = ll.anmeldung_leiter_id
    where ll.lager_id = p_lager_id
      and ll.rolle = 'lagerleitung'
      and ll.status = 'bestaetigt'
    order by al.nachname, al.vorname
    limit 1;
  end if;

  v_lageradresse := nullif(trim(coalesce(
    v_merged->>'lageradresse',
    v_lager.ort,
    ''
  )), '');

  v_lagertelefon := nullif(trim(coalesce(
    v_merged->>'lagertelefon',
    v_lager.telefon_zeiten,
    ''
  )), '');

  return json_build_object(
    'id', v_lager.id,
    'name', v_lager.name,
    'jahr', v_lager.jahr,
    'ort', v_lager.ort,
    'start_datum', v_lager.start_datum,
    'end_datum', v_lager.end_datum,
    'status', v_lager.status,
    'organisation_id', v_lager.organisation_id,
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
      'elternabend_datum', coalesce(v_merged->>'elternabend_datum', ''),
      'elternabend_ort', coalesce(v_merged->>'elternabend_ort', ''),
      'kennenlernabend_datum', coalesce(v_merged->>'kennenlernabend_datum', ''),
      'kennenlernabend_ort', coalesce(v_merged->>'kennenlernabend_ort', ''),
      'lagerrueckblick_datum', coalesce(v_merged->>'diashow_datum', v_merged->>'lagerrueckblick_datum', ''),
      'lagerrueckblick_ort', coalesce(v_merged->>'diashow_ort', v_merged->>'lagerrueckblick_ort', ''),
      'reise_besammlung', coalesce(v_merged->>'reise_besammlung', ''),
      'reise_abfahrt', coalesce(v_merged->>'reise_abfahrt', ''),
      'reise_rueckkehr', coalesce(v_merged->>'reise_rueckkehr', ''),
      'einzahlungsfrist', coalesce(v_merged->>'einzahlungsfrist', ''),
      'versicherung_hinweis', coalesce(v_merged->>'versicherung_hinweis', 'Versicherung ist Sache der Teilnehmenden.')
    )
  );
end;
$$;
