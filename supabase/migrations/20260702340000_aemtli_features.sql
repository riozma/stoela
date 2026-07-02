-- Ämtli-Features: Kiosk, Mörderli, Kuchenstand, Gesundheit, Inventar, Gelände, Höck-Rollen, Statistik

-- ---------------------------------------------------------------------
-- TN Gesundheitsangaben
-- ---------------------------------------------------------------------
alter table anmeldungen_tn add column if not exists medikamente text;
alter table anmeldungen_tn add column if not exists gesundheit_bemerkungen text;
alter table anmeldungen_tn add column if not exists eltern_aufenthaltsort text;
alter table anmeldungen_tn add column if not exists impfausweis_hinweis text;

alter table lager add column if not exists telefon_zeiten text;
alter table lager add column if not exists kiosk_gruppe_modus text not null default 'ungerade'
  check (kiosk_gruppe_modus in ('gerade', 'ungerade', 'alle'));

-- ---------------------------------------------------------------------
-- Höck-Rollen (Flughöhe pro Block)
-- ---------------------------------------------------------------------
create table if not exists hoeck_rollen (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  tag date not null,
  block_id uuid references programmbloecke (id) on delete set null,
  titel text not null,
  leiter_name text,
  anmeldung_leiter_id uuid references anmeldungen_leiter (id) on delete set null,
  start_zeit time,
  end_zeit time,
  dauer_min int,
  vorbereitung text,
  sortierung int not null default 0,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Kiosk
-- ---------------------------------------------------------------------
create table if not exists kiosk_artikel (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  name text not null,
  preis numeric(10, 2) not null default 0,
  kategorie text,
  aktiv boolean not null default true,
  sortierung int not null default 0
);

create table if not exists kiosk_guthaben (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  anmeldung_tn_id uuid not null references anmeldungen_tn (id) on delete cascade,
  betrag_start numeric(10, 2) not null default 0,
  betrag_ausgezahlt numeric(10, 2) not null default 0,
  notiz text,
  unique (lager_id, anmeldung_tn_id)
);

create table if not exists kiosk_kaeufe (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  anmeldung_tn_id uuid not null references anmeldungen_tn (id) on delete cascade,
  artikel_id uuid references kiosk_artikel (id) on delete set null,
  artikel_name text not null,
  preis numeric(10, 2) not null,
  menge int not null default 1,
  tag date not null default current_date,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Gute Fee / Mörderli
-- ---------------------------------------------------------------------
create table if not exists gute_fee_spiel (
  lager_id uuid primary key references lager (id) on delete cascade,
  aktiv boolean not null default false,
  oeffentlich boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists gute_fee_liste (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  typ text not null check (typ in ('ort', 'gegenstand')),
  wert text not null,
  sortierung int not null default 0
);

create table if not exists gute_fee_spieler (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  anmeldung_leiter_id uuid not null references anmeldungen_leiter (id) on delete cascade,
  status text not null default 'lebend' check (status in ('lebend', 'tot')),
  ziel_ort text,
  ziel_gegenstand text,
  ziel_leiter_id uuid references anmeldungen_leiter (id) on delete set null,
  unique (lager_id, anmeldung_leiter_id)
);

create table if not exists gute_fee_ereignisse (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  moerder_id uuid references anmeldungen_leiter (id) on delete set null,
  opfer_id uuid references anmeldungen_leiter (id) on delete set null,
  bestaetigt boolean not null default false,
  notiz text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Kuchenstand
-- ---------------------------------------------------------------------
create table if not exists kuchenstand_standorte (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  ort text not null,
  datum date,
  notiz text,
  sortierung int not null default 0
);

create table if not exists kuchenstand_schichten (
  id uuid primary key default gen_random_uuid(),
  standort_id uuid not null references kuchenstand_standorte (id) on delete cascade,
  start_zeit time,
  end_zeit time,
  titel text
);

create table if not exists kuchenstand_anmeldungen (
  id uuid primary key default gen_random_uuid(),
  schicht_id uuid not null references kuchenstand_schichten (id) on delete cascade,
  anmeldung_leiter_id uuid references anmeldungen_leiter (id) on delete set null,
  vorname text not null,
  nachname text not null,
  was text,
  menge text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Org-weit: Sponsoring, Inventar, Geländewiesen-Vorlage, Skiweekend
-- ---------------------------------------------------------------------
create table if not exists org_sponsoring (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisation (id) on delete cascade,
  jahr int not null,
  sponsor text not null,
  betrag numeric(12, 2),
  material text,
  danke_gesendet boolean not null default false,
  notiz text,
  created_at timestamptz not null default now()
);

create table if not exists org_bastel_inventar (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisation (id) on delete cascade,
  name text not null,
  bestand int not null default 0,
  min_bestand int not null default 0,
  einheit text default 'Stk',
  notiz text,
  updated_at timestamptz not null default now()
);

create table if not exists org_skiweekend (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisation (id) on delete cascade,
  jahr int not null,
  ort text,
  start_datum date,
  end_datum date,
  budget numeric(12, 2),
  notiz text,
  created_at timestamptz not null default now()
);

create table if not exists org_skiweekend_umfrage (
  id uuid primary key default gen_random_uuid(),
  skiweekend_id uuid not null references org_skiweekend (id) on delete cascade,
  profile_id uuid references profiles (id) on delete set null,
  name text not null,
  antwort text not null,
  created_at timestamptz not null default now()
);

create table if not exists gelaendespielwiesen (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  name text not null,
  lat numeric(10, 7),
  lng numeric(10, 7),
  bauer_name text,
  bauer_telefon text,
  status text not null default 'offen' check (status in ('offen', 'zusage', 'abgelehnt', 'bedankt')),
  notiz text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Programm-Statistik (Leiter-Beteiligung)
-- ---------------------------------------------------------------------
create or replace function public.lager_programm_statistik(p_lager_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_result jsonb := '[]'::jsonb;
  v_row record;
  v_total int;
  v_leiter record;
  v_anwesend_tage int;
  v_bloecke_total int;
begin
  if not public.is_lager_leitung(p_lager_id) then
    raise exception 'Nur Lagerleitung.';
  end if;

  select count(*) into v_bloecke_total from programmbloecke where lager_id = p_lager_id;

  for v_leiter in
    select id, vorname, nachname, anwesend_von, anwesend_bis
    from anmeldungen_leiter
    where lager_id = p_lager_id and status = 'bestaetigt'
  loop
    select count(distinct pb.id) into v_total
    from programmbloecke pb
    where pb.lager_id = p_lager_id
      and (
        pb.verantwortlich ilike '%' || v_leiter.vorname || '%'
        or exists (
          select 1 from jsonb_array_elements(coalesce(pb.verantwortlich_zuordnungen, '[]'::jsonb)) z
          where (z->>'anmeldung_leiter_id')::uuid = v_leiter.id
        )
      );

    v_anwesend_tage := case
      when v_leiter.anwesend_von is not null and v_leiter.anwesend_bis is not null
        then (v_leiter.anwesend_bis - v_leiter.anwesend_von) + 1
      else null end;

    v_result := v_result || jsonb_build_array(jsonb_build_object(
      'leiter_id', v_leiter.id,
      'name', v_leiter.vorname || ' ' || v_leiter.nachname,
      'bloecke_absolut', v_total,
      'bloecke_total', v_bloecke_total,
      'anteil_prozent', case when v_bloecke_total > 0 then round(v_total::numeric / v_bloecke_total * 100, 1) else 0 end,
      'anwesend_tage', v_anwesend_tage
    ));
  end loop;

  return v_result;
end;
$$;

grant execute on function public.lager_programm_statistik(uuid) to authenticated;

-- Gute Fee: Zuweisung
create or replace function public.gute_fee_zuweisen(p_lager_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orte text[];
  v_gegen text[];
  v_spieler uuid[];
  v_i int;
  v_j int;
  v_ziel uuid;
  v_cnt int := 0;
begin
  if not public.can_access_lager(p_lager_id) then raise exception 'Kein Zugriff.'; end if;

  select array_agg(wert order by sortierung) into v_orte from gute_fee_liste where lager_id = p_lager_id and typ = 'ort';
  select array_agg(wert order by sortierung) into v_gegen from gute_fee_liste where lager_id = p_lager_id and typ = 'gegenstand';
  select array_agg(anmeldung_leiter_id order by random()) into v_spieler
  from gute_fee_spieler where lager_id = p_lager_id and status = 'lebend';

  if coalesce(array_length(v_orte, 1), 0) < 2 or coalesce(array_length(v_gegen, 1), 0) < 2 then
    raise exception 'Mindestens 2 Orte und 2 Gegenstände nötig.';
  end if;
  if coalesce(array_length(v_spieler, 1), 0) < 2 then
    raise exception 'Mindestens 2 Spieler nötig.';
  end if;

  for v_i in 1..array_length(v_spieler, 1) loop
    v_j := 1 + floor(random() * array_length(v_spieler, 1))::int;
    while v_spieler[v_j] = v_spieler[v_i] loop
      v_j := 1 + floor(random() * array_length(v_spieler, 1))::int;
    end loop;
    v_ziel := v_spieler[v_j];
    update gute_fee_spieler set
      ziel_ort = v_orte[1 + floor(random() * array_length(v_orte, 1))::int],
      ziel_gegenstand = v_gegen[1 + floor(random() * array_length(v_gegen, 1))::int],
      ziel_leiter_id = v_ziel
    where lager_id = p_lager_id and anmeldung_leiter_id = v_spieler[v_i];
    v_cnt := v_cnt + 1;
  end loop;

  update gute_fee_spiel set aktiv = true, updated_at = now() where lager_id = p_lager_id;
  return v_cnt;
end;
$$;

grant execute on function public.gute_fee_zuweisen(uuid) to authenticated;

-- RLS
alter table hoeck_rollen enable row level security;
alter table kiosk_artikel enable row level security;
alter table kiosk_guthaben enable row level security;
alter table kiosk_kaeufe enable row level security;
alter table gute_fee_spiel enable row level security;
alter table gute_fee_liste enable row level security;
alter table gute_fee_spieler enable row level security;
alter table gute_fee_ereignisse enable row level security;
alter table kuchenstand_standorte enable row level security;
alter table kuchenstand_schichten enable row level security;
alter table kuchenstand_anmeldungen enable row level security;
alter table org_sponsoring enable row level security;
alter table org_bastel_inventar enable row level security;
alter table org_skiweekend enable row level security;
alter table org_skiweekend_umfrage enable row level security;
alter table gelaendespielwiesen enable row level security;

create policy "hoeck_rollen: team" on hoeck_rollen for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));
create policy "kiosk: team" on kiosk_artikel for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));
create policy "kiosk_guthaben: team" on kiosk_guthaben for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));
create policy "kiosk_kaeufe: team" on kiosk_kaeufe for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));
create policy "gute_fee: team" on gute_fee_spiel for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));
create policy "gute_fee_liste: team" on gute_fee_liste for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));
create policy "gute_fee_spieler: team" on gute_fee_spieler for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));
create policy "gute_fee_ereign: team" on gute_fee_ereignisse for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));
create policy "kuchenstand: team" on kuchenstand_standorte for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));
create policy "kuchenstand_schicht: team" on kuchenstand_schichten for all to authenticated
  using (exists (select 1 from kuchenstand_standorte s join lager l on l.id = s.lager_id where s.id = standort_id and can_access_lager(l.id)))
  with check (exists (select 1 from kuchenstand_standorte s where s.id = standort_id));
create policy "kuchenstand_anm: team" on kuchenstand_anmeldungen for all to authenticated
  using (true) with check (true);
create policy "org_sponsoring: team" on org_sponsoring for all to authenticated using (true) with check (true);
create policy "org_bastel: team" on org_bastel_inventar for all to authenticated using (true) with check (true);
create policy "org_ski: team" on org_skiweekend for all to authenticated using (true) with check (true);
create policy "org_ski_umfrage: team" on org_skiweekend_umfrage for all to authenticated using (true) with check (true);
create policy "gelaende: team" on gelaendespielwiesen for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));

-- Alle Ämtli + Meta
alter table org_aemtli_meta drop constraint if exists org_aemtli_meta_seiten_typ_check;
alter table org_aemtli_meta add constraint org_aemtli_meta_seiten_typ_check
  check (seiten_typ in (
    'generic', 'finanzen', 'werbung', 'motto', 'sponsoring', 'kuchenstand', 'material',
    'kiosk', 'telefon', 'gute_fee', 'hl', 'krankenpflege', 'foto', 'bastel', 'disco',
    'skiweekend', 'hauswart', 'gelaende', 'verkleidung'
  ));
