-- Dynamische Zusatzfelder für die Leiteranmeldung: Text, Einzelauswahl
-- (Checkbox/Radio), Mehrfachauswahl - von der Lalei pro Lager definiert.
create table leiter_anmeldung_felder (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager(id) on delete cascade,
  typ text not null check (typ in ('text', 'einzelauswahl', 'mehrfachauswahl')),
  label text not null,
  optionen text[] not null default '{}',
  pflicht boolean not null default false,
  sortierung int not null default 0,
  created_at timestamptz not null default now()
);

create table leiter_anmeldung_antworten (
  id uuid primary key default gen_random_uuid(),
  anmeldung_leiter_id uuid not null references anmeldungen_leiter(id) on delete cascade,
  feld_id uuid not null references leiter_anmeldung_felder(id) on delete cascade,
  wert text,
  wert_liste text[],
  unique (anmeldung_leiter_id, feld_id)
);

alter table leiter_anmeldung_felder enable row level security;
alter table leiter_anmeldung_antworten enable row level security;

create policy "leiter_anmeldung_felder: select lagerteam oder leiter_anmeldung_offen" on leiter_anmeldung_felder
for select using (
  can_access_lager(lager_id)
  or exists (select 1 from lager l where l.id = lager_id and l.leiter_anmeldung_status = 'offen')
);

create policy "leiter_anmeldung_felder: verwalten lagerleitung" on leiter_anmeldung_felder
for all using (is_lager_leitung(lager_id)) with check (is_lager_leitung(lager_id));

create policy "leiter_anmeldung_antworten: select lagerteam" on leiter_anmeldung_antworten
for select using (
  exists (
    select 1 from anmeldungen_leiter al
    where al.id = anmeldung_leiter_id and can_access_lager(al.lager_id)
  )
);

create policy "leiter_anmeldung_antworten: insert eigene oder lagerteam" on leiter_anmeldung_antworten
for insert with check (
  exists (
    select 1 from anmeldungen_leiter al
    where al.id = anmeldung_leiter_id
      and (al.profile_id = auth.uid() or can_access_lager(al.lager_id))
  )
);

create policy "leiter_anmeldung_antworten: update eigene oder lagerteam" on leiter_anmeldung_antworten
for update using (
  exists (
    select 1 from anmeldungen_leiter al
    where al.id = anmeldung_leiter_id
      and (al.profile_id = auth.uid() or can_access_lager(al.lager_id))
  )
);
