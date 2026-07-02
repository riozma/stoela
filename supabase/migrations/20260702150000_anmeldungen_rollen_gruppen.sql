-- TN-Anmeldung erweitern: Geschlecht, AHV-Nr, Rolle (TN oder HL)
alter table anmeldungen_tn add column geschlecht text check (geschlecht in ('m', 'w', 'd'));
alter table anmeldungen_tn add column ahv_nr text;
alter table anmeldungen_tn add column rolle text not null default 'TN' check (rolle in ('TN', 'HL'));

-- Leiter-Anmeldung: eigene Tabelle, unabhängig vom App-Login (lager_leiter)
create table anmeldungen_leiter (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  vorname text not null,
  nachname text not null,
  geburtsdatum date,
  geschlecht text check (geschlecht in ('m', 'w', 'd')),
  ahv_nr text,
  email text not null,
  telefon text,
  anwesend_von date,
  anwesend_bis date,
  status text not null default 'angemeldet' check (status in ('angemeldet', 'bestaetigt', 'abgesagt')),
  created_at timestamptz not null default now()
);

alter table anmeldungen_leiter enable row level security;

create policy "anmeldungen_leiter: insert öffentlich bei offener Anmeldung" on anmeldungen_leiter
  for insert to anon, authenticated
  with check (
    exists (select 1 from lager where id = lager_id and status = 'anmeldung_offen')
  );
create policy "anmeldungen_leiter: select/update für Lagerteam" on anmeldungen_leiter
  for all to authenticated
  using (public.is_lager_team(lager_id))
  with check (public.is_lager_team(lager_id));

-- Leiter <-> Ämtli/Rollen (nutzt den bestehenden aemtli-Katalog: Lagerleitung,
-- Finanzen, Küche, ... plus frei erstellbare)
create table leiter_rollen (
  id uuid primary key default gen_random_uuid(),
  anmeldung_leiter_id uuid not null references anmeldungen_leiter (id) on delete cascade,
  aemtli_id uuid not null references aemtli (id),
  unique (anmeldung_leiter_id, aemtli_id)
);

alter table leiter_rollen enable row level security;

create policy "leiter_rollen: für Lagerteam" on leiter_rollen
  for all to authenticated
  using (
    exists (
      select 1 from anmeldungen_leiter al
      where al.id = anmeldung_leiter_id and public.is_lager_team(al.lager_id)
    )
  )
  with check (
    exists (
      select 1 from anmeldungen_leiter al
      where al.id = anmeldung_leiter_id and public.is_lager_team(al.lager_id)
    )
  );

insert into aemtli (name, beschreibung)
values
  ('Lagerleitung', 'Gesamtverantwortung fürs Lager'),
  ('Finanzen', 'Budget und Abrechnung')
on conflict (name) do nothing;

-- Lagergruppen (z.B. für gemischte Kleingruppen übers ganze Lager)
create table lagergruppen (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table gruppen_mitglieder (
  id uuid primary key default gen_random_uuid(),
  lagergruppe_id uuid not null references lagergruppen (id) on delete cascade,
  anmeldung_tn_id uuid references anmeldungen_tn (id) on delete cascade,
  anmeldung_leiter_id uuid references anmeldungen_leiter (id) on delete cascade,
  check (
    (anmeldung_tn_id is not null and anmeldung_leiter_id is null) or
    (anmeldung_tn_id is null and anmeldung_leiter_id is not null)
  )
);

alter table lagergruppen enable row level security;
alter table gruppen_mitglieder enable row level security;

create policy "lagergruppen: für Lagerteam" on lagergruppen
  for all to authenticated
  using (public.is_lager_team(lager_id))
  with check (public.is_lager_team(lager_id));

create policy "gruppen_mitglieder: für Lagerteam" on gruppen_mitglieder
  for all to authenticated
  using (
    exists (select 1 from lagergruppen lg where lg.id = lagergruppe_id and public.is_lager_team(lg.lager_id))
  )
  with check (
    exists (select 1 from lagergruppen lg where lg.id = lagergruppe_id and public.is_lager_team(lg.lager_id))
  );
