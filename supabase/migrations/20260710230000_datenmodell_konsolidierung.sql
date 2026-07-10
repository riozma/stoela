-- Datenmodell-Konsolidierung
-- scope:
--   global          = personenübergreifend (profiles)
--   organisation    = jahresunabhängige Vereinsvorlage
--   organisation_jahr = Vereinsdaten eines Jahres
--   lager           = genau ein Lager / Jahr
--   projection      = abgeleitete, nicht-kanonische Lesedarstellung

-- ---------------------------------------------------------------------
-- 1. Ämtli: statische Org-Vorlage und jährliche Lagerwerte trennen
-- ---------------------------------------------------------------------
create table if not exists public.lager_aemtli_daten (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references public.lager(id) on delete cascade,
  aemtli_id uuid not null references public.aemtli(id) on delete cascade,
  bezugsjahr int not null,
  werte jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  unique (lager_id, aemtli_id)
);

comment on table public.lager_aemtli_daten is
  'Scope lager: jährlich veränderliche Ämtli-Werte. Statische Beschreibung/Felddefinition bleibt in org_aemtli_meta.';
comment on column public.lager_aemtli_daten.bezugsjahr is
  'Explizites Bezugsjahr; entspricht lager.jahr und macht exportierte Variablen eindeutig.';

alter table public.lager_aemtli_daten enable row level security;

create policy "lager_aemtli_daten: lagerteam"
  on public.lager_aemtli_daten
  for all to authenticated
  using (public.can_access_lager(lager_id))
  with check (public.can_access_lager(lager_id));

-- Bestehende org-weite Werte als Ausgangswert je Lager/Jahr übernehmen.
insert into public.lager_aemtli_daten (lager_id, aemtli_id, bezugsjahr, werte)
select
  l.id,
  m.aemtli_id,
  l.jahr,
  coalesce(m.extra_felder, '{}'::jsonb) - 'felder'
from public.lager l
join public.org_aemtli_meta m on m.organisation_id = l.organisation_id
where coalesce(m.extra_felder, '{}'::jsonb) - 'felder' <> '{}'::jsonb
on conflict (lager_id, aemtli_id) do nothing;

-- In org_aemtli_meta bleibt nur die statische Felddefinition.
update public.org_aemtli_meta
set extra_felder = jsonb_build_object(
  'felder',
  coalesce(extra_felder->'felder', '[]'::jsonb)
)
where extra_felder is not null;

comment on column public.org_aemtli_meta.extra_felder is
  'Scope organisation: nur Felddefinition (felder[]). Jahreswerte liegen in lager_aemtli_daten.';

-- ---------------------------------------------------------------------
-- 2. Todos: Ämtli per FK statt veränderlichem Namen referenzieren
-- ---------------------------------------------------------------------
alter table public.org_todo_vorlagen
  add column if not exists aemtli_id uuid references public.aemtli(id) on delete set null;

alter table public.lager_todos
  add column if not exists aemtli_id uuid references public.aemtli(id) on delete set null;

update public.org_todo_vorlagen v
set aemtli_id = a.id
from public.aemtli a
where v.aemtli_id is null
  and v.aemtli_name is not null
  and lower(trim(a.name)) = lower(trim(v.aemtli_name));

update public.lager_todos t
set aemtli_id = a.id
from public.aemtli a
where t.aemtli_id is null
  and t.aemtli_name is not null
  and lower(trim(a.name)) = lower(trim(t.aemtli_name));

create unique index if not exists lager_todos_lager_vorlage_uidx
  on public.lager_todos (lager_id, vorlage_id)
  where vorlage_id is not null;

create or replace function public.todo_aemtli_id_aufloesen()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.aemtli_id is null and new.aemtli_name is not null then
    select id into new.aemtli_id
    from aemtli
    where lower(trim(name)) = lower(trim(new.aemtli_name))
    limit 1;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_lager_todo_aemtli_id on public.lager_todos;
create trigger trg_lager_todo_aemtli_id
before insert or update of aemtli_name, aemtli_id on public.lager_todos
for each row execute function public.todo_aemtli_id_aufloesen();

drop trigger if exists trg_org_todo_aemtli_id on public.org_todo_vorlagen;
create trigger trg_org_todo_aemtli_id
before insert or update of aemtli_name, aemtli_id on public.org_todo_vorlagen
for each row execute function public.todo_aemtli_id_aufloesen();

-- ---------------------------------------------------------------------
-- 3. Personen: Profile sind kanonisch, Lagerzeilen sind Teilnahme
-- ---------------------------------------------------------------------
-- Mehrere aktive Teilnahmen desselben Login-Profils auflösen:
-- bestätigt > angemeldet > angefragt, danach ältester Datensatz.
with rangiert as (
  select
    id,
    row_number() over (
      partition by lager_id, profile_id
      order by
        case status
          when 'bestaetigt' then 1
          when 'angemeldet' then 2
          when 'angefragt' then 3
          else 4
        end,
        created_at,
        id
    ) as rn
  from public.anmeldungen_leiter
  where profile_id is not null
    and status not in ('abgesagt', 'abgelehnt')
)
update public.anmeldungen_leiter al
set status = 'abgesagt'
from rangiert r
where al.id = r.id and r.rn > 1;

create unique index if not exists anmeldungen_leiter_ein_aktiv_profil_pro_lager_uidx
  on public.anmeldungen_leiter (lager_id, profile_id)
  where profile_id is not null
    and status not in ('abgesagt', 'abgelehnt');

-- Verknüpfte Vereins-Personen ebenfalls nur einmal aktiv je Verein.
with rangiert as (
  select
    id,
    row_number() over (
      partition by organisation_id, profile_id
      order by created_at, id
    ) as rn
  from public.org_personen
  where profile_id is not null and aktiv
)
update public.org_personen op
set aktiv = false
from rangiert r
where op.id = r.id and r.rn > 1;

create unique index if not exists org_personen_ein_aktives_profil_pro_org_uidx
  on public.org_personen (organisation_id, profile_id)
  where profile_id is not null and aktiv;

-- Verknüpfte Zeilen sind nur technische Snapshots; Identität kommt aus profiles.
update public.anmeldungen_leiter al
set
  vorname = coalesce(p.vorname, al.vorname),
  nachname = coalesce(p.nachname, al.nachname),
  email = coalesce(p.email, al.email),
  telefon = coalesce(p.telefon, al.telefon),
  geburtsdatum = coalesce(p.geburtsdatum, al.geburtsdatum),
  geschlecht = coalesce(p.geschlecht, al.geschlecht),
  ahv_nr = coalesce(p.ahv_nr, al.ahv_nr)
from public.profiles p
where p.id = al.profile_id;

update public.org_personen op
set
  vorname = coalesce(p.vorname, op.vorname),
  nachname = coalesce(p.nachname, op.nachname),
  email = coalesce(p.email, op.email),
  telefon = coalesce(p.telefon, op.telefon)
from public.profiles p
where p.id = op.profile_id;

create or replace function public.leiter_identitaet_aus_profil()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_p profiles%rowtype;
begin
  if new.profile_id is null then return new; end if;
  select * into v_p from profiles where id = new.profile_id;
  if v_p.id is null then return new; end if;

  new.vorname := coalesce(v_p.vorname, new.vorname);
  new.nachname := coalesce(v_p.nachname, new.nachname);
  new.email := coalesce(v_p.email, new.email);
  new.telefon := coalesce(v_p.telefon, new.telefon);
  new.geburtsdatum := coalesce(v_p.geburtsdatum, new.geburtsdatum);
  new.geschlecht := coalesce(v_p.geschlecht, new.geschlecht);
  new.ahv_nr := coalesce(v_p.ahv_nr, new.ahv_nr);
  return new;
end;
$$;

drop trigger if exists trg_leiter_identitaet_aus_profil on public.anmeldungen_leiter;
create trigger trg_leiter_identitaet_aus_profil
before insert or update of profile_id, vorname, nachname, email, telefon, geburtsdatum, geschlecht, ahv_nr
on public.anmeldungen_leiter
for each row execute function public.leiter_identitaet_aus_profil();

comment on column public.anmeldungen_leiter.vorname is
  'Snapshot/Kompatibilität. Bei profile_id ist profiles die kanonische Identitätsquelle.';
comment on column public.org_personen.vorname is
  'Nur für manuelle Personen kanonisch. Bei profile_id ist profiles die Quelle.';

-- Eine TN-Anmeldung pro AHV und Lager (abgesagte Historie ausgenommen).
with rangiert as (
  select
    id,
    row_number() over (
      partition by lager_id, ahv_nr
      order by created_at, id
    ) as rn
  from public.anmeldungen_tn
  where nullif(trim(ahv_nr), '') is not null
    and status <> 'abgesagt'
)
update public.anmeldungen_tn atn
set status = 'abgesagt'
from rangiert r
where atn.id = r.id and r.rn > 1;

create unique index if not exists anmeldungen_tn_eine_aktiv_ahv_pro_lager_uidx
  on public.anmeldungen_tn (lager_id, ahv_nr)
  where nullif(trim(ahv_nr), '') is not null
    and status <> 'abgesagt';

-- Teamzugänge ohne Teilnahme einmalig ergänzen.
insert into public.anmeldungen_leiter (
  lager_id,
  profile_id,
  vorname,
  nachname,
  email,
  telefon,
  geburtsdatum,
  geschlecht,
  ahv_nr,
  anwesend_von,
  anwesend_bis,
  status,
  anmeldung_art
)
select
  ll.lager_id,
  ll.profile_id,
  coalesce(nullif(trim(p.vorname), ''), split_part(p.email, '@', 1), 'Leiter'),
  coalesce(nullif(trim(p.nachname), ''), ''),
  p.email,
  p.telefon,
  p.geburtsdatum,
  p.geschlecht,
  p.ahv_nr,
  l.start_datum,
  l.end_datum,
  case when ll.status = 'bestaetigt' then 'bestaetigt' else 'angemeldet' end,
  'fix'
from public.lager_leiter ll
join public.profiles p on p.id = ll.profile_id
join public.lager l on l.id = ll.lager_id
where not exists (
  select 1
  from public.anmeldungen_leiter al
  where al.lager_id = ll.lager_id
    and al.profile_id = ll.profile_id
    and al.status not in ('abgesagt', 'abgelehnt')
);

-- Künftige direkte Team-INSERTs erzeugen automatisch genau eine Teilnahme.
create or replace function public.ensure_leiter_teilnahme_fuer_team()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_p profiles%rowtype;
  v_l lager%rowtype;
begin
  if exists (
    select 1 from anmeldungen_leiter al
    where al.lager_id = new.lager_id
      and al.profile_id = new.profile_id
      and al.status not in ('abgesagt', 'abgelehnt')
  ) then
    return new;
  end if;

  select * into v_p from profiles where id = new.profile_id;
  select * into v_l from lager where id = new.lager_id;
  if v_p.id is null or v_l.id is null then return new; end if;

  insert into anmeldungen_leiter (
    lager_id, profile_id, vorname, nachname, email, telefon,
    geburtsdatum, geschlecht, ahv_nr, anwesend_von, anwesend_bis,
    status, anmeldung_art
  )
  values (
    new.lager_id,
    new.profile_id,
    coalesce(nullif(trim(v_p.vorname), ''), split_part(v_p.email, '@', 1), 'Leiter'),
    coalesce(nullif(trim(v_p.nachname), ''), ''),
    v_p.email,
    v_p.telefon,
    v_p.geburtsdatum,
    v_p.geschlecht,
    v_p.ahv_nr,
    v_l.start_datum,
    v_l.end_datum,
    case when new.status = 'bestaetigt' then 'bestaetigt' else 'angemeldet' end,
    'fix'
  )
  on conflict do nothing;

  return new;
end;
$$;

drop trigger if exists trg_ensure_leiter_teilnahme_fuer_team on public.lager_leiter;
create trigger trg_ensure_leiter_teilnahme_fuer_team
after insert or update of status on public.lager_leiter
for each row execute function public.ensure_leiter_teilnahme_fuer_team();

-- Kanonische Leseansicht: Profilfelder für Login-Leiter, Snapshot nur für manuelle.
create or replace view public.leiter_teilnahmen
with (security_invoker = true)
as
select
  al.id,
  al.lager_id,
  al.profile_id,
  coalesce(p.vorname, al.vorname) as vorname,
  coalesce(p.nachname, al.nachname) as nachname,
  coalesce(p.email, al.email) as email,
  coalesce(p.telefon, al.telefon) as telefon,
  coalesce(p.geburtsdatum, al.geburtsdatum) as geburtsdatum,
  coalesce(p.geschlecht, al.geschlecht) as geschlecht,
  coalesce(p.ahv_nr, al.ahv_nr) as ahv_nr,
  al.anwesend_von,
  al.anwesend_bis,
  al.essensgewohnheiten,
  al.status,
  al.anmeldung_art,
  al.bestaetigen_bis,
  al.von_vorjahr,
  al.von_lager_id,
  al.created_at
from public.anmeldungen_leiter al
left join public.profiles p on p.id = al.profile_id;

grant select on public.leiter_teilnahmen to authenticated;

comment on view public.leiter_teilnahmen is
  'Kanonische Leiteransicht: Identität aus profiles, lagerbezogene Teilnahme aus anmeldungen_leiter.';

-- ---------------------------------------------------------------------
-- 4. Termine: lager_termine explizit als Projektion kennzeichnen
-- ---------------------------------------------------------------------
alter table public.lager_termine
  add column if not exists daten_scope text not null default 'lager'
    check (daten_scope in ('lager', 'organisation_jahr', 'projection')),
  add column if not exists bezugsjahr int,
  add column if not exists quelle_typ text,
  add column if not exists quelle_id uuid;

update public.lager_termine lt
set
  bezugsjahr = l.jahr,
  daten_scope = case when lt.typ = 'skiweekend' then 'organisation_jahr' else 'lager' end,
  quelle_typ = case
    when lt.typ = 'lager' then 'lager'
    when lt.typ = 'vorweekend' then 'lager'
    when lt.typ = 'skiweekend' then 'org_skiweekend'
    when lt.beschreibung like 'sync:kuchenstand:%' then 'kuchenstand_standorte'
    else 'lager_termine'
  end,
  quelle_id = case
    when lt.typ in ('lager', 'vorweekend') then l.id
    when lt.beschreibung like 'sync:kuchenstand:%'
      then substring(lt.beschreibung from 'sync:kuchenstand:([0-9a-f-]{36})')::uuid
    else lt.id
  end
from public.lager l
where l.id = lt.lager_id;

comment on table public.lager_termine is
  'Kalender-Lesemodell. quelle_typ/quelle_id bezeichnet die kanonische Quelle; native öffentliche/sonstige Termine haben quelle_typ=lager_termine.';

-- ---------------------------------------------------------------------
-- 5. Jahres-/Scope-Eindeutigkeit
-- ---------------------------------------------------------------------
-- Skiweekend-Duplikate auf einen Datensatz je Verein/Jahr reduzieren.
with rangiert as (
  select
    id,
    first_value(id) over (
      partition by organisation_id, jahr
      order by created_at, id
    ) as behalten,
    row_number() over (
      partition by organisation_id, jahr
      order by created_at, id
    ) as rn
  from public.org_skiweekend
)
update public.org_skiweekend_programm p
set skiweekend_id = r.behalten
from rangiert r
where p.skiweekend_id = r.id and r.rn > 1;

with rangiert as (
  select
    id,
    first_value(id) over (
      partition by organisation_id, jahr
      order by created_at, id
    ) as behalten,
    row_number() over (
      partition by organisation_id, jahr
      order by created_at, id
    ) as rn
  from public.org_skiweekend
)
update public.org_skiweekend_anmeldungen a
set skiweekend_id = r.behalten
from rangiert r
where a.skiweekend_id = r.id and r.rn > 1;

with rangiert as (
  select
    id,
    row_number() over (
      partition by organisation_id, jahr
      order by created_at, id
    ) as rn
  from public.org_skiweekend
)
delete from public.org_skiweekend s
using rangiert r
where s.id = r.id and r.rn > 1;

create unique index if not exists org_skiweekend_org_jahr_uidx
  on public.org_skiweekend (organisation_id, jahr);

with rangiert as (
  select
    id,
    row_number() over (
      partition by organisation_id, lower(trim(name))
      order by updated_at desc, id
    ) as rn,
    sum(bestand) over (
      partition by organisation_id, lower(trim(name))
    ) as bestand_total,
    max(min_bestand) over (
      partition by organisation_id, lower(trim(name))
    ) as min_total
  from public.org_bastel_inventar
)
update public.org_bastel_inventar i
set bestand = r.bestand_total, min_bestand = r.min_total
from rangiert r
where i.id = r.id and r.rn = 1;

with rangiert as (
  select
    id,
    row_number() over (
      partition by organisation_id, lower(trim(name))
      order by updated_at desc, id
    ) as rn
  from public.org_bastel_inventar
)
delete from public.org_bastel_inventar i
using rangiert r
where i.id = r.id and r.rn > 1;

create unique index if not exists org_bastel_inventar_org_name_uidx
  on public.org_bastel_inventar (organisation_id, lower(trim(name)));

-- Lager-Namen sind je Organisation/Jahr eindeutig, nicht global über alle Vereine.
alter table public.lager drop constraint if exists lager_jahr_name_key;
create unique index if not exists lager_org_jahr_name_uidx
  on public.lager (organisation_id, jahr, lower(name));

create index if not exists lager_aemtli_daten_jahr_idx
  on public.lager_aemtli_daten (bezugsjahr, lager_id);

-- ---------------------------------------------------------------------
-- 6. Öffentliche Termine: eine kanonische Quelle = lager_termine
-- ---------------------------------------------------------------------
-- Eine ältere 8-Parameter-Überladung kollidiert mit der neueren Funktion,
-- deren Zeitparameter Defaults haben. Nur die aktuelle Signatur behalten.
drop function if exists public.lager_termin_upsert_cfg(
  uuid, text, text, date, date, text, boolean, integer
);

-- Einmalig bestehende JSON-Termine in die kanonische Tabelle übernehmen.
do $$
declare
  r record;
begin
  for r in select id from public.lager loop
    perform public.lager_termine_sync(r.id);
  end loop;
end;
$$;

-- Danach keine doppelte Speicherung der gleichen Datums-/Zeit-/Ort-Felder.
update public.lager
set elterninfo_config = coalesce(elterninfo_config, '{}'::jsonb)
  - 'elternabend_datum' - 'elternabend_zeit' - 'elternabend_ort'
  - 'kennenlernabend_datum' - 'kennenlernabend_zeit' - 'kennenlernabend_ort'
  - 'diashow_datum' - 'diashow_zeit' - 'diashow_ort'
  - 'lagerrueckblick_datum' - 'lagerrueckblick_zeit' - 'lagerrueckblick_ort';

update public.org_elterninfo_vorlage
set felder = coalesce(felder, '{}'::jsonb)
  - 'elternabend_datum' - 'elternabend_zeit' - 'elternabend_ort'
  - 'kennenlernabend_datum' - 'kennenlernabend_zeit' - 'kennenlernabend_ort'
  - 'diashow_datum' - 'diashow_zeit' - 'diashow_ort'
  - 'lagerrueckblick_datum' - 'lagerrueckblick_zeit' - 'lagerrueckblick_ort';

create or replace function public.lager_termin_scope_setzen()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_lager lager%rowtype;
  v_ski_id uuid;
begin
  select * into v_lager from lager where id = new.lager_id;
  new.bezugsjahr := v_lager.jahr;

  if new.typ = 'lager' then
    new.daten_scope := 'projection';
    new.quelle_typ := 'lager';
    new.quelle_id := new.lager_id;
  elsif new.typ = 'vorweekend' then
    new.daten_scope := 'projection';
    new.quelle_typ := 'lager';
    new.quelle_id := new.lager_id;
  elsif new.typ = 'skiweekend' then
    select s.id into v_ski_id
    from org_skiweekend s
    where s.organisation_id = v_lager.organisation_id and s.jahr = v_lager.jahr
    limit 1;
    new.daten_scope := 'projection';
    new.quelle_typ := 'org_skiweekend';
    new.quelle_id := v_ski_id;
  elsif coalesce(new.beschreibung, '') like 'sync:kuchenstand:%' then
    new.daten_scope := 'projection';
    new.quelle_typ := 'kuchenstand_standorte';
    new.quelle_id := substring(new.beschreibung from 'sync:kuchenstand:([0-9a-f-]{36})')::uuid;
  else
    new.daten_scope := 'lager';
    new.quelle_typ := 'lager_termine';
    new.quelle_id := new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_lager_termin_scope_setzen on public.lager_termine;
create trigger trg_lager_termin_scope_setzen
before insert or update on public.lager_termine
for each row execute function public.lager_termin_scope_setzen();

-- Sync aktualisiert nur Projektionen. Elternabend/Kennenlernabend/Diashow
-- bleiben unverändert, unabhängig davon, auf welcher UI-Seite sie editiert wurden.
create or replace function public.lager_termine_sync(p_lager_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager lager%rowtype;
  v_ski org_skiweekend%rowtype;
  r record;
begin
  select * into v_lager from lager where id = p_lager_id;
  if not found then return; end if;

  perform public.lager_termine_dedupe(p_lager_id);

  if v_lager.start_datum is not null then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'lager', coalesce(v_lager.name, 'Lager'),
      v_lager.start_datum, v_lager.end_datum, v_lager.ort, true, 0
    );
  else
    delete from lager_termine where lager_id = p_lager_id and typ = 'lager';
  end if;

  if v_lager.vorweekend_start is not null then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'vorweekend', 'Vorweekend',
      v_lager.vorweekend_start, v_lager.vorweekend_ende, null, false, 10
    );
  else
    delete from lager_termine where lager_id = p_lager_id and typ = 'vorweekend';
  end if;

  if v_lager.organisation_id is not null then
    select * into v_ski
    from org_skiweekend
    where organisation_id = v_lager.organisation_id and jahr = v_lager.jahr
    limit 1;

    if v_ski.id is not null and v_ski.start_datum is not null then
      perform public.lager_termin_upsert_cfg(
        p_lager_id, 'skiweekend', 'Skiweekend ' || v_ski.jahr::text,
        v_ski.start_datum, v_ski.end_datum, v_ski.ort, true, 50
      );
    else
      delete from lager_termine where lager_id = p_lager_id and typ = 'skiweekend';
    end if;
  end if;

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
      lager_id, typ, titel, start_datum, end_datum, ort,
      beschreibung, oeffentlich, sortierung
    )
    values (
      p_lager_id, 'sonstiges', 'Kuchenstand: ' || r.ort,
      r.datum, r.datum, r.ort,
      'sync:kuchenstand:' || r.id::text,
      true, 60
    );
  end loop;

  perform public.lager_termine_dedupe(p_lager_id);
end;
$$;

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
  v_id uuid;
  v_end date;
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

  v_end := case
    when p_nur_ein_tag or p_end_datum is null then p_start_datum
    else p_end_datum
  end;
  v_titel := case p_typ
    when 'elternabend' then 'Elternabend'
    when 'kennenlernabend' then 'Kennenlernabend'
    else 'Diashow / Lagerrückblick'
  end;

  if p_termin_id is not null then
    select id into v_id
    from lager_termine
    where id = p_termin_id and lager_id = p_lager_id and typ = p_typ;
  else
    select id into v_id
    from lager_termine
    where lager_id = p_lager_id and typ = p_typ
    order by created_at limit 1;
  end if;

  if v_id is null then
    insert into lager_termine (
      lager_id, typ, titel, start_datum, end_datum,
      start_zeit, end_zeit, ort, oeffentlich, sortierung
    )
    values (
      p_lager_id, p_typ, v_titel, p_start_datum, v_end,
      p_start_zeit, p_end_zeit, nullif(trim(p_ort), ''), true,
      case p_typ when 'elternabend' then 20 when 'kennenlernabend' then 30 else 40 end
    )
    returning id into v_id;
  else
    update lager_termine
    set
      start_datum = p_start_datum,
      end_datum = v_end,
      start_zeit = p_start_zeit,
      end_zeit = p_end_zeit,
      ort = nullif(trim(p_ort), ''),
      oeffentlich = true,
      updated_at = now()
    where id = v_id;
  end if;

  return v_id;
end;
$$;

grant execute on function public.lager_termin_oeffentlich_upsert(
  uuid, text, date, date, time, time, text, boolean, uuid
) to authenticated;
