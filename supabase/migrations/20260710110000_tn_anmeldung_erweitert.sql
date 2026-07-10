-- Erweiterte TN-Anmeldung: Elternkontakt, Dokumente, Lagerinfo für Formular.

-- Elternkontakt (gleich für Geschwister in einer Anmeldung)
create table if not exists tn_eltern_kontakte (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  eltern_email text not null,
  eltern_vorname text not null,
  eltern_nachname text not null,
  telefon text not null,
  adresse text not null,
  plz text not null,
  ort text not null,
  aufenthaltsort text,
  aufenthaltsort_unbekannt boolean not null default false,
  created_at timestamptz not null default now()
);

alter table anmeldungen_tn
  add column if not exists eltern_kontakt_id uuid references tn_eltern_kontakte (id) on delete set null,
  add column if not exists essensgewohnheiten_sonstiges text,
  add column if not exists sonstige_info text,
  add column if not exists kind_nr int not null default 1;

create table if not exists tn_anmeldung_dokumente (
  id uuid primary key default gen_random_uuid(),
  anmeldung_tn_id uuid not null references anmeldungen_tn (id) on delete cascade,
  typ text not null check (typ in ('krankenkasse_vorne', 'krankenkasse_hinten', 'impfung')),
  storage_path text not null,
  dateiname text,
  created_at timestamptz not null default now()
);

alter table tn_eltern_kontakte enable row level security;
alter table tn_anmeldung_dokumente enable row level security;

create policy "tn_eltern_kontakte: insert bei offener anmeldung" on tn_eltern_kontakte
  for insert to anon, authenticated
  with check (
    exists (
      select 1 from lager l
      where l.id = lager_id and l.status = 'anmeldung_offen'
    )
  );

create policy "tn_eltern_kontakte: lesen lagerteam" on tn_eltern_kontakte
  for select to authenticated
  using (exists (select 1 from lager l where l.id = lager_id and public.can_access_lager(l.id)));

create policy "tn_anmeldung_dokumente: insert bei offener anmeldung" on tn_anmeldung_dokumente
  for insert to anon, authenticated
  with check (
    exists (
      select 1
      from anmeldungen_tn t
      join lager l on l.id = t.lager_id
      where t.id = anmeldung_tn_id and l.status = 'anmeldung_offen'
    )
  );

create policy "tn_anmeldung_dokumente: lesen lagerteam" on tn_anmeldung_dokumente
  for select to authenticated
  using (
    exists (
      select 1
      from anmeldungen_tn t
      where t.id = anmeldung_tn_id and public.can_access_lager(t.lager_id)
    )
  );

-- Storage-Bucket für Uploads (Versicherungskarte, Impfausweis)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'tn-anmeldungen',
  'tn-anmeldungen',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
on conflict (id) do nothing;

create policy "tn-anmeldungen: upload bei offener anmeldung" on storage.objects
  for insert to anon, authenticated
  with check (
    bucket_id = 'tn-anmeldungen'
    and (storage.foldername(name))[1] is not null
  );

create policy "tn-anmeldungen: lesen lagerteam" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'tn-anmeldungen'
    and exists (
      select 1
      from lager l
      where l.id::text = (storage.foldername(name))[1]
        and public.can_access_lager(l.id)
    )
  );

-- Lagerinfo + Elterninfo für öffentliches Anmeldeformular
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
  v_merged := v_org_felder || v_cfg;

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
      'anmeldeschluss', v_merged->>'anmeldeschluss',
      'mindestalter', coalesce(v_merged->>'mindestalter', ''),
      'max_teilnehmer', coalesce(v_merged->>'max_teilnehmer', '50'),
      'kosten_erstes_kind', coalesce((v_merged->>'lagerbeitrag_tn')::int, (v_merged->>'lagerbeitrag')::int, 340),
      'kosten_weiteres_kind', coalesce((v_merged->>'lagerbeitrag_geschwister')::int, 280),
      'kontakt_name', coalesce(v_merged->>'lagerleiter_name', v_merged->>'kontakt_name', ''),
      'kontakt_email', coalesce(v_merged->>'lagerleiter_email', v_merged->>'kontakt_email', 'info@stoecklilager.com'),
      'kontakt_telefon', coalesce(v_merged->>'lagerleiter_telefon', v_merged->>'kontakt_telefon', ''),
      'elternabend_datum', v_merged->>'elternabend_datum',
      'kennenlernabend_datum', v_merged->>'kennenlernabend_datum',
      'lagerrueckblick_datum', v_merged->>'diashow_datum',
      'versicherung_hinweis', coalesce(v_merged->>'versicherung_hinweis', 'Versicherung ist Sache der Teilnehmenden.')
    )
  );
end;
$$;

grant execute on function public.get_lager_tn_anmeldung_info(uuid) to anon, authenticated;

-- handle_new_user: Namen bei E-Mail-Registrierung übernehmen
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vorname text;
  v_nachname text;
  v_full text;
begin
  v_vorname := nullif(trim(coalesce(
    new.raw_user_meta_data->>'given_name',
    new.raw_user_meta_data->>'vorname',
    ''
  )), '');

  v_nachname := nullif(trim(coalesce(
    new.raw_user_meta_data->>'family_name',
    new.raw_user_meta_data->>'nachname',
    ''
  )), '');

  if v_vorname is null and v_nachname is null then
    v_full := nullif(trim(coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      ''
    )), '');

    if v_full is not null then
      v_vorname := nullif(split_part(v_full, ' ', 1), '');
      v_nachname := nullif(trim(regexp_replace(v_full, '^\S+\s*', '')), '');
    end if;
  end if;

  insert into public.profiles (id, email, vorname, nachname)
  values (new.id, new.email, v_vorname, v_nachname);

  return new;
end;
$$;
