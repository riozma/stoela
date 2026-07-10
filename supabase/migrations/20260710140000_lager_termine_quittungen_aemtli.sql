-- Lager-Termine (Kalender), Quittungs-Kategorien, Ämtli-Dokumente, Leiter-ICS

-- ---------------------------------------------------------------------
-- Zentraler Lager-Kalender
-- ---------------------------------------------------------------------
alter table lager add column if not exists kalender_token uuid not null default gen_random_uuid();

create table if not exists lager_termine (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  typ text not null check (typ in (
    'lager', 'elternabend', 'kennenlernabend', 'diashow',
    'vorweekend', 'skiweekend', 'hoeck', 'sonstiges'
  )),
  titel text not null,
  start_datum date,
  end_datum date,
  start_zeit time,
  end_zeit time,
  ort text,
  beschreibung text,
  oeffentlich boolean not null default false,
  sortierung int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists lager_termine_lager_idx on lager_termine (lager_id, start_datum);

alter table lager_termine enable row level security;

create policy "lager_termine: lagerteam lesen"
  on lager_termine for select to authenticated
  using (public.can_access_lager(lager_id));

create policy "lager_termine: leitung schreiben"
  on lager_termine for all to authenticated
  using (
    exists (
      select 1 from lager l
      where l.id = lager_termine.lager_id
        and (
          l.created_by = auth.uid()
          or exists (
            select 1 from lager_leiter ll
            where ll.lager_id = l.id
              and ll.profile_id = auth.uid()
              and ll.rolle = 'lagerleitung'
              and ll.status = 'bestaetigt'
          )
        )
    )
  )
  with check (
    exists (
      select 1 from lager l
      where l.id = lager_termine.lager_id
        and (
          l.created_by = auth.uid()
          or exists (
            select 1 from lager_leiter ll
            where ll.lager_id = l.id
              and ll.profile_id = auth.uid()
              and ll.rolle = 'lagerleitung'
              and ll.status = 'bestaetigt'
          )
        )
    )
  );

-- Öffentliche Termine für TN-Anmeldung (nur lesen)
create policy "lager_termine: oeffentlich anon"
  on lager_termine for select to anon
  using (
    oeffentlich = true
    and exists (
      select 1 from lager l
      where l.id = lager_termine.lager_id
        and l.status = 'anmeldung_offen'
    )
  );

-- ---------------------------------------------------------------------
-- Quittungen: Kategorie + Richtung
-- ---------------------------------------------------------------------
alter table quittungen
  add column if not exists kategorie text,
  add column if not exists richtung text not null default 'ausgabe'
    check (richtung in ('einnahme', 'ausgabe'));

-- ---------------------------------------------------------------------
-- Ämtli-Mehrjahresdokumente (Organisation)
-- ---------------------------------------------------------------------
alter table org_aemtli_meta
  add column if not exists dokumente_links jsonb not null default '[]';

create table if not exists org_aemtli_dokumente (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisation (id) on delete cascade,
  aemtli_id uuid not null references aemtli (id) on delete cascade,
  titel text not null,
  storage_path text not null,
  dateiname text,
  created_at timestamptz not null default now(),
  created_by uuid references profiles (id) on delete set null,
  unique (organisation_id, aemtli_id, storage_path)
);

alter table org_aemtli_dokumente enable row level security;

create policy "org_aemtli_dokumente: mitglieder lesen"
  on org_aemtli_dokumente for select to authenticated
  using (public.is_org_mitglied(organisation_id));

create policy "org_aemtli_dokumente: leitung schreiben"
  on org_aemtli_dokumente for all to authenticated
  using (public.is_org_leitung(organisation_id))
  with check (public.is_org_leitung(organisation_id));

insert into storage.buckets (id, name, public, file_size_limit)
values ('org-aemtli-dokumente', 'org-aemtli-dokumente', false, 20971520)
on conflict (id) do nothing;

create policy "org_aemtli_docs: lesen"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'org-aemtli-dokumente'
    and exists (
      select 1 from org_aemtli_dokumente d
      where d.storage_path = name
        and public.is_org_mitglied(d.organisation_id)
    )
  );

create policy "org_aemtli_docs: upload"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'org-aemtli-dokumente'
    and exists (
      select 1 from org_aemtli_dokumente d
      where d.storage_path = name
        and public.is_org_leitung(d.organisation_id)
    )
  );

-- ---------------------------------------------------------------------
-- Termine aus Lager + Elterninfo synchronisieren
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
begin
  select * into v_lager from lager where id = p_lager_id;
  if not found then return; end if;

  v_cfg := coalesce(v_lager.elterninfo_config, '{}'::jsonb);

  -- Lager-Haupttermin
  if v_lager.start_datum is not null then
    insert into lager_termine (lager_id, typ, titel, start_datum, end_datum, ort, oeffentlich, sortierung)
    values (
      p_lager_id, 'lager', coalesce(v_lager.name, 'Lager'),
      v_lager.start_datum, v_lager.end_datum, v_lager.ort, true, 0
    )
    on conflict do nothing;
    update lager_termine
    set start_datum = v_lager.start_datum, end_datum = v_lager.end_datum, ort = v_lager.ort,
        titel = coalesce(v_lager.name, titel), updated_at = now()
    where lager_id = p_lager_id and typ = 'lager';
  end if;

  -- Vorweekend
  if v_lager.vorweekend_start is not null then
    insert into lager_termine (lager_id, typ, titel, start_datum, end_datum, oeffentlich, sortierung)
    values (p_lager_id, 'vorweekend', 'Vorweekend', v_lager.vorweekend_start, v_lager.vorweekend_ende, false, 10)
    on conflict do nothing;
    update lager_termine
    set start_datum = v_lager.vorweekend_start, end_datum = v_lager.vorweekend_ende, updated_at = now()
    where lager_id = p_lager_id and typ = 'vorweekend';
  end if;

  -- Elterninfo-Termine: nur wenn ISO-Datum (YYYY-MM-DD), sonst bleibt Freitext in elterninfo_config
  if (v_cfg->>'elternabend_datum') ~ '^\d{4}-\d{2}-\d{2}$' then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'elternabend', 'Elternabend',
      (v_cfg->>'elternabend_datum')::date,
      nullif(v_cfg->>'elternabend_ort', ''), true, 20
    );
  end if;
  if (v_cfg->>'kennenlernabend_datum') ~ '^\d{4}-\d{2}-\d{2}$' then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'kennenlernabend', 'Kennenlernabend',
      (v_cfg->>'kennenlernabend_datum')::date,
      nullif(v_cfg->>'kennenlernabend_ort', ''), true, 30
    );
  end if;
  if (v_cfg->>'diashow_datum') ~ '^\d{4}-\d{2}-\d{2}$' then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'diashow', 'Diashow / Lagerrückblick',
      (v_cfg->>'diashow_datum')::date,
      nullif(v_cfg->>'diashow_ort', ''), true, 40
    );
  end if;
end;
$$;

create or replace function public.lager_termin_upsert_cfg(
  p_lager_id uuid,
  p_typ text,
  p_titel text,
  p_datum date,
  p_ort text,
  p_oeffentlich boolean,
  p_sortierung int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_datum is null then return; end if;
  if exists (select 1 from lager_termine where lager_id = p_lager_id and typ = p_typ) then
    update lager_termine
    set start_datum = p_datum, ort = coalesce(p_ort, ort), oeffentlich = p_oeffentlich, updated_at = now()
    where lager_id = p_lager_id and typ = p_typ;
  else
    insert into lager_termine (lager_id, typ, titel, start_datum, ort, oeffentlich, sortierung)
    values (p_lager_id, p_typ, p_titel, p_datum, p_ort, p_oeffentlich, p_sortierung);
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- ICS-Kalender (Download + Abo-Token)
-- ---------------------------------------------------------------------
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
  v_i int := 0;
  v_dt text;
begin
  select * into v_lager from lager where id = p_lager_id;
  if not found then return null; end if;

  if p_token is not null then
    if v_lager.kalender_token is distinct from p_token then
      return null;
    end if;
  elsif auth.uid() is null or not public.can_access_lager(p_lager_id) then
    return null;
  end if;

  v_ics := 'BEGIN:VCALENDAR' || chr(13) || chr(10)
    || 'VERSION:2.0' || chr(13) || chr(10)
    || 'PRODID:-//Stoeckli Lager//DE' || chr(13) || chr(10)
    || 'CALSCALE:GREGORIAN' || chr(13) || chr(10)
    || 'METHOD:PUBLISH' || chr(13) || chr(10)
    || 'X-WR-CALNAME:' || coalesce(v_lager.name, 'Lager') || chr(13) || chr(10);

  for v_t in
    select * from lager_termine
    where lager_id = p_lager_id
    order by coalesce(start_datum, '9999-12-31'::date), sortierung
  loop
    if v_t.start_datum is null then continue; end if;
    v_i := v_i + 1;
    v_dt := to_char(v_t.start_datum, 'YYYYMMDD');
    v_ics := v_ics || 'BEGIN:VEVENT' || chr(13) || chr(10)
      || 'UID:lager-' || p_lager_id::text || '-' || v_t.typ || '-' || v_i || '@stoecklilager.com' || chr(13) || chr(10)
      || 'DTSTART;VALUE=DATE:' || v_dt || chr(13) || chr(10);
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

  v_ics := v_ics || 'END:VCALENDAR';
  return v_ics;
end;
$$;

grant execute on function public.get_lager_kalender_ics(uuid, uuid) to anon, authenticated;
grant execute on function public.lager_termine_sync(uuid) to authenticated;

-- TN-Anmeldung: Termine aus lager_termine
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
  v_elternabend text;
  v_elternabend_ort text;
  v_kennenlern text;
  v_kennenlern_ort text;
  v_diashow text;
  v_diashow_ort text;
begin
  select * into v_lager from lager where id = p_lager_id and status = 'anmeldung_offen';
  if not found then return null; end if;

  perform public.lager_termine_sync(p_lager_id);

  if v_lager.organisation_id is not null then
    select felder into v_org_felder from org_elterninfo_vorlage where organisation_id = v_lager.organisation_id;
  end if;

  v_cfg := coalesce(v_lager.elterninfo_config, '{}'::jsonb);
  v_merged := coalesce(v_org_felder, '{}'::jsonb) || v_cfg;

  select coalesce(to_char(start_datum, 'DD.MM.YYYY'), ''), coalesce(ort, '')
  into v_elternabend, v_elternabend_ort
  from lager_termine where lager_id = p_lager_id and typ = 'elternabend' and oeffentlich limit 1;
  if v_elternabend = '' then
    v_elternabend := coalesce(v_merged->>'elternabend_datum', '');
    v_elternabend_ort := coalesce(v_merged->>'elternabend_ort', '');
  end if;

  select coalesce(to_char(start_datum, 'DD.MM.YYYY'), ''), coalesce(ort, '')
  into v_kennenlern, v_kennenlern_ort
  from lager_termine where lager_id = p_lager_id and typ = 'kennenlernabend' and oeffentlich limit 1;
  if v_kennenlern = '' then
    v_kennenlern := coalesce(v_merged->>'kennenlernabend_datum', '');
    v_kennenlern_ort := coalesce(v_merged->>'kennenlernabend_ort', '');
  end if;

  select coalesce(to_char(start_datum, 'DD.MM.YYYY'), ''), coalesce(ort, '')
  into v_diashow, v_diashow_ort
  from lager_termine where lager_id = p_lager_id and typ = 'diashow' and oeffentlich limit 1;
  if v_diashow = '' then
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
