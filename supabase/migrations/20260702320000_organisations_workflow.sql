-- Vereins-Wissensspeicher, Lager-Fahrplan, provisorische Leiter-Anmeldung

-- ---------------------------------------------------------------------
-- Organisation (Stöckli Lager – über alle Jahre)
-- ---------------------------------------------------------------------
create table if not exists organisation (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  homepage text,
  notizen text,
  created_at timestamptz not null default now()
);

insert into organisation (name, slug, homepage)
values ('Stöckli Lager', 'stoeckli', 'https://www.stoecklilager.ch')
on conflict (slug) do nothing;

create table if not exists org_personen (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisation (id) on delete cascade,
  profile_id uuid references profiles (id) on delete set null,
  vorname text not null,
  nachname text not null,
  email text,
  telefon text,
  rolle_hinweis text,
  aktiv boolean not null default true,
  notizen text,
  created_at timestamptz not null default now(),
  unique (organisation_id, email)
);

create table if not exists org_aemtli_meta (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisation (id) on delete cascade,
  aemtli_id uuid not null references aemtli (id) on delete cascade,
  seiten_typ text not null default 'generic'
    check (seiten_typ in ('generic', 'finanzen', 'werbung', 'motto', 'sponsoring', 'kuchenstand', 'material')),
  beschreibung text,
  hinweise_md text,
  default_checkliste jsonb not null default '[]',
  extra_felder jsonb not null default '{}',
  unique (organisation_id, aemtli_id)
);

-- Todo-Vorlagen (relativ zum Lagerstart oder fix für Verein)
create table if not exists org_todo_vorlagen (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisation (id) on delete cascade,
  titel text not null,
  beschreibung text,
  ebene text not null default 'lager'
    check (ebene in ('lager', 'verein')),
  monate_vor_lager numeric,
  kategorie text not null default 'vorbereitung'
    check (kategorie in (
      'team', 'logistik', 'vorweekend', 'programm', 'werbung', 'finanzen',
      'eltern', 'lager', 'nachlager', 'verein'
    )),
  zustaendig text not null default 'lalei'
    check (zustaendig in ('lalei', 'kueche', 'aemtli', 'alle')),
  aemtli_name text,
  sortierung int not null default 0,
  aktiv boolean not null default true
);

create table if not exists lager_todos (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  vorlage_id uuid references org_todo_vorlagen (id) on delete set null,
  titel text not null,
  beschreibung text,
  kategorie text not null default 'vorbereitung',
  zustaendig text not null default 'lalei',
  aemtli_name text,
  faellig_am date,
  erledigt boolean not null default false,
  erledigt_am timestamptz,
  sortierung int not null default 0,
  created_at timestamptz not null default now()
);

-- Lager erweitern
alter table lager add column if not exists organisation_id uuid references organisation (id);
alter table lager add column if not exists vor_lager_id uuid references lager (id) on delete set null;
alter table lager add column if not exists vorweekend_start date;
alter table lager add column if not exists vorweekend_ende date;
alter table lager add column if not exists elterninfo_config jsonb not null default '{}';

update lager set organisation_id = (select id from organisation where slug = 'stoeckli' limit 1)
where organisation_id is null;

-- Leiter: provisorisch / von Vorjahr
alter table anmeldungen_leiter add column if not exists anmeldung_art text not null default 'fix'
  check (anmeldung_art in ('provisorisch', 'fix'));
alter table anmeldungen_leiter add column if not exists bestaetigen_bis date;
alter table anmeldungen_leiter add column if not exists von_vorjahr boolean not null default false;
alter table anmeldungen_leiter add column if not exists von_lager_id uuid references lager (id) on delete set null;

-- Programm: Sonderblöcke (Anreise, Abreise, Vorweekend)
alter table programmbloecke add column if not exists block_typ text not null default 'programm'
  check (block_typ in ('programm', 'anreise', 'abreise', 'vorweekend'));
alter table programmbloecke add column if not exists sonderfelder jsonb not null default '{}';

-- Vorweekend
create table if not exists vorweekend_programm (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  tag date not null,
  start_zeit time,
  end_zeit time,
  titel text not null,
  ort text,
  beschreibung text,
  sortierung int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists vorweekend_anmeldungen (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  anmeldung_leiter_id uuid references anmeldungen_leiter (id) on delete cascade,
  profile_id uuid references profiles (id) on delete set null,
  vorname text not null,
  nachname text not null,
  anwesend_von timestamptz,
  anwesend_bis timestamptz,
  notiz text,
  created_at timestamptz not null default now()
);

-- Elterninfo-Vorlage (org-weit)
create table if not exists org_elterninfo_vorlage (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisation (id) on delete cascade unique,
  felder jsonb not null default '{}',
  packliste jsonb not null default '[]',
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------
create or replace function public.lager_faelligkeit(p_start date, p_monate_vor numeric)
returns date
language sql
immutable
as $$
  select (p_start - (p_monate_vor * interval '1 month'))::date;
$$;

create or replace function public.lager_todos_generieren(p_lager_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
  v_start date;
  v_cnt int := 0;
  v_row record;
begin
  if not public.can_access_lager(p_lager_id) then
    raise exception 'Kein Zugriff auf dieses Lager.';
  end if;

  select organisation_id, start_datum into v_org, v_start from lager where id = p_lager_id;
  if v_org is null then
    select id into v_org from organisation where slug = 'stoeckli' limit 1;
    update lager set organisation_id = v_org where id = p_lager_id;
  end if;

  for v_row in
    select * from org_todo_vorlagen
    where organisation_id = v_org and aktiv and ebene = 'lager'
    order by sortierung, monate_vor_lager desc nulls last
  loop
    if exists (
      select 1 from lager_todos
      where lager_id = p_lager_id and vorlage_id = v_row.id
    ) then
      continue;
    end if;

    insert into lager_todos (
      lager_id, vorlage_id, titel, beschreibung, kategorie, zustaendig, aemtli_name,
      faellig_am, sortierung
    ) values (
      p_lager_id,
      v_row.id,
      v_row.titel,
      v_row.beschreibung,
      v_row.kategorie,
      v_row.zustaendig,
      v_row.aemtli_name,
      case when v_start is not null and v_row.monate_vor_lager is not null
        then public.lager_faelligkeit(v_start, v_row.monate_vor_lager)
        else null end,
      v_row.sortierung
    );
    v_cnt := v_cnt + 1;
  end loop;

  return v_cnt;
end;
$$;

create or replace function public.lager_leiter_von_vorjahr(p_lager_id uuid, p_vor_lager_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_start date;
  v_bestaetigen_bis date;
  v_cnt int := 0;
  v_row record;
begin
  if not public.is_lager_leitung(p_lager_id) then
    raise exception 'Nur Lagerleitung darf Leiter übernehmen.';
  end if;

  select start_datum into v_start from lager where id = p_lager_id;
  v_bestaetigen_bis := case when v_start is not null then (v_start - interval '3 months')::date else null end;

  for v_row in
    select * from anmeldungen_leiter
    where lager_id = p_vor_lager_id
      and status in ('bestaetigt', 'angemeldet')
  loop
    if exists (
      select 1 from anmeldungen_leiter
      where lager_id = p_lager_id
        and (
          (profile_id is not null and profile_id = v_row.profile_id)
          or (lower(email) = lower(v_row.email) and v_row.email is not null)
          or (lower(vorname) = lower(v_row.vorname) and lower(nachname) = lower(v_row.nachname))
        )
    ) then
      continue;
    end if;

    insert into anmeldungen_leiter (
      lager_id, profile_id, vorname, nachname, email, telefon, geburtsdatum, geschlecht,
      anwesend_von, anwesend_bis, status, anmeldung_art, bestaetigen_bis, von_vorjahr, von_lager_id
    ) values (
      p_lager_id,
      v_row.profile_id,
      v_row.vorname,
      v_row.nachname,
      v_row.email,
      v_row.telefon,
      v_row.geburtsdatum,
      v_row.geschlecht,
      null,
      null,
      'angemeldet',
      'provisorisch',
      v_bestaetigen_bis,
      true,
      p_vor_lager_id
    );
    v_cnt := v_cnt + 1;
  end loop;

  update lager set vor_lager_id = p_vor_lager_id where id = p_lager_id;
  return v_cnt;
end;
$$;

create or replace function public.leiter_bestaetigen(p_anmeldung_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager uuid;
  v_profile uuid;
  v_email text;
begin
  select lager_id, profile_id, email into v_lager, v_profile, v_email
  from anmeldungen_leiter where id = p_anmeldung_id;

  if v_profile is distinct from auth.uid() and not public.is_lager_leitung(v_lager) then
    raise exception 'Nicht berechtigt.';
  end if;

  update anmeldungen_leiter
  set anmeldung_art = 'fix', status = 'bestaetigt'
  where id = p_anmeldung_id;
end;
$$;

grant execute on function public.lager_todos_generieren(uuid) to authenticated;
grant execute on function public.lager_leiter_von_vorjahr(uuid, uuid) to authenticated;
grant execute on function public.leiter_bestaetigen(uuid) to authenticated;
grant execute on function public.lager_faelligkeit(date, numeric) to authenticated;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table organisation enable row level security;
alter table org_personen enable row level security;
alter table org_aemtli_meta enable row level security;
alter table org_todo_vorlagen enable row level security;
alter table lager_todos enable row level security;
alter table vorweekend_programm enable row level security;
alter table vorweekend_anmeldungen enable row level security;
alter table org_elterninfo_vorlage enable row level security;

create policy "organisation: lesen" on organisation for select to authenticated using (true);
create policy "org_personen: team" on org_personen for all to authenticated using (true) with check (true);
create policy "org_aemtli_meta: team" on org_aemtli_meta for all to authenticated using (true) with check (true);
create policy "org_todo_vorlagen: team" on org_todo_vorlagen for select to authenticated using (true);
create policy "lager_todos: lagerteam" on lager_todos
  for all to authenticated using (public.can_access_lager(lager_id)) with check (public.can_access_lager(lager_id));
create policy "vorweekend_programm: lagerteam" on vorweekend_programm
  for all to authenticated using (public.can_access_lager(lager_id)) with check (public.can_access_lager(lager_id));
create policy "vorweekend_anmeldungen: lagerteam" on vorweekend_anmeldungen
  for all to authenticated using (public.can_access_lager(lager_id)) with check (public.can_access_lager(lager_id));
create policy "org_elterninfo: team" on org_elterninfo_vorlage for all to authenticated using (true) with check (true);
