-- Stöckli Lager App: Grundschema
-- Ein Jugendlager (J+S/Jubla) pro Jahr = eine Zeile in "lager".
-- Alle anderen Tabellen hängen per lager_id daran, ausser dem
-- Ämtli-Katalog und den Learnings, die bewusst jahresübergreifend leben.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- Lager (Saison)
-- ---------------------------------------------------------------------
create table lager (
  id uuid primary key default gen_random_uuid(),
  jahr int not null,
  name text not null,
  ort text,
  start_datum date,
  end_datum date,
  status text not null default 'planung'
    check (status in ('planung', 'anmeldung_offen', 'laufend', 'abgeschlossen', 'archiviert')),
  ecamp_camp_id text,      -- optionale Referenz zu eCamp
  jubla_ablauf_id text,    -- optionale Referenz zu jubla.db
  created_at timestamptz not null default now(),
  unique (jahr, name)
);

-- ---------------------------------------------------------------------
-- Profiles: 1:1 zu auth.users, wird per Trigger befüllt
-- ---------------------------------------------------------------------
create table profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  vorname text,
  nachname text,
  email text not null,
  telefon text,
  jubla_person_id text,
  created_at timestamptz not null default now()
);

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- Team-Zuordnung pro Lagerjahr
-- ---------------------------------------------------------------------
create table lager_leiter (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete cascade,
  rolle text not null default 'leiter'
    check (rolle in ('lagerleitung', 'leiter', 'aemtli_verantwortlich')),
  status text not null default 'eingeladen'
    check (status in ('eingeladen', 'bestaetigt', 'abgesagt')),
  unique (lager_id, profile_id)
);

-- Helper: ist der aktuelle User bestätigtes Teammitglied dieses Lagers?
create function public.is_lager_team(p_lager_id uuid)
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from lager_leiter
    where lager_id = p_lager_id
      and profile_id = auth.uid()
      and status = 'bestaetigt'
  );
$$;

-- ---------------------------------------------------------------------
-- TN-Anmeldungen (öffentliches Formular, kein Login nötig)
-- ---------------------------------------------------------------------
create table anmeldungen_tn (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  vorname text not null,
  nachname text not null,
  geburtsdatum date not null,
  allergien text,
  notfallkontakt text not null,
  eltern_email text not null,
  status text not null default 'angemeldet'
    check (status in ('angemeldet', 'bestaetigt', 'abgesagt', 'warteliste')),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Ämtli: globaler Katalog, überlebt Lagerjahre
-- ---------------------------------------------------------------------
create table aemtli (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  beschreibung text,
  aktiv boolean not null default true
);

create table aemtli_zuweisungen (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  aemtli_id uuid not null references aemtli (id),
  profile_id uuid references profiles (id),
  checkliste jsonb not null default '[]',
  status text not null default 'offen'
    check (status in ('offen', 'in_arbeit', 'erledigt')),
  unique (lager_id, aemtli_id)
);

-- Learnings hängen am Ämtli (nicht am Lagerjahr) -> bleiben für kommende Teams sichtbar
create table aemtli_learnings (
  id uuid primary key default gen_random_uuid(),
  aemtli_id uuid not null references aemtli (id) on delete cascade,
  lager_id uuid not null references lager (id) on delete cascade,
  autor_id uuid references profiles (id),
  text text not null,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Einkaufsliste (v.a. Ämtli "Küche"), pro Lager
-- ---------------------------------------------------------------------
create table einkaufsliste_items (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  aemtli_id uuid references aemtli (id),
  name text not null,
  menge numeric,
  einheit text,
  kategorie text,
  erledigt boolean not null default false,
  erstellt_von uuid references profiles (id),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Reminders, versendet über eine Edge Function via Resend
-- ---------------------------------------------------------------------
create table reminders (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  titel text not null,
  nachricht text,
  faellig_am timestamptz not null,
  ziel_rolle text,
  ziel_aemtli_id uuid references aemtli (id),
  gesendet_am timestamptz,
  status text not null default 'geplant'
    check (status in ('geplant', 'gesendet', 'fehlgeschlagen'))
);

-- ---------------------------------------------------------------------
-- Row Level Security
--
-- Bewusst grosszügig: Stöckli-Lager ist ein kleines, vertrauenswürdiges
-- Leiterteam ohne eigenes Admin-Rollensystem. Jedes bestätigte
-- Teammitglied eines Lagers darf dessen operative Daten lesen/schreiben.
-- Ämtli-Katalog & Learnings sind absichtlich global lesbar, damit Wissen
-- nicht verloren geht, wenn jemand nicht mehr im aktuellen Lagerteam ist.
-- ---------------------------------------------------------------------

alter table lager enable row level security;
alter table profiles enable row level security;
alter table lager_leiter enable row level security;
alter table anmeldungen_tn enable row level security;
alter table aemtli enable row level security;
alter table aemtli_zuweisungen enable row level security;
alter table aemtli_learnings enable row level security;
alter table einkaufsliste_items enable row level security;
alter table reminders enable row level security;

-- lager: alle eingeloggten Leiter sehen alle Saisons (Historie/Übergabe),
-- schreiben dürfen alle eingeloggten Leiter (kein Admin-Konzept bisher).
create policy "lager: select für eingeloggte" on lager
  for select to authenticated using (true);
create policy "lager: insert/update für eingeloggte" on lager
  for all to authenticated using (true) with check (true);

-- profiles: jeder sieht alle (Team-Verzeichnis), ändern nur die eigene Zeile.
create policy "profiles: select für eingeloggte" on profiles
  for select to authenticated using (true);
create policy "profiles: update eigene Zeile" on profiles
  for update to authenticated using (auth.uid() = id);

-- lager_leiter: eingeloggte sehen alle Zuordnungen, ändern eigene Einladung
-- (annehmen/absagen) oder fügen neue Team-Mitglieder hinzu.
create policy "lager_leiter: select für eingeloggte" on lager_leiter
  for select to authenticated using (true);
create policy "lager_leiter: insert für eingeloggte" on lager_leiter
  for insert to authenticated with check (true);
create policy "lager_leiter: update eigene Zeile" on lager_leiter
  for update to authenticated using (auth.uid() = profile_id);

-- anmeldungen_tn: öffentliches Formular darf einfügen, wenn die Anmeldung
-- für dieses Lager offen ist; lesen/bearbeiten nur das jeweilige Lagerteam.
create policy "anmeldungen_tn: insert öffentlich bei offener Anmeldung" on anmeldungen_tn
  for insert to anon, authenticated
  with check (
    exists (select 1 from lager where id = lager_id and status = 'anmeldung_offen')
  );
create policy "anmeldungen_tn: select/update für Lagerteam" on anmeldungen_tn
  for all to authenticated
  using (public.is_lager_team(lager_id))
  with check (public.is_lager_team(lager_id));

-- aemtli: Katalog ist geteiltes Wissen, alle eingeloggten Leiter pflegen ihn.
create policy "aemtli: select für eingeloggte" on aemtli
  for select to authenticated using (true);
create policy "aemtli: insert/update für eingeloggte" on aemtli
  for all to authenticated using (true) with check (true);

-- aemtli_zuweisungen: nur das jeweilige Lagerteam.
create policy "aemtli_zuweisungen: für Lagerteam" on aemtli_zuweisungen
  for all to authenticated
  using (public.is_lager_team(lager_id))
  with check (public.is_lager_team(lager_id));

-- aemtli_learnings: absichtlich global lesbar (Übergabe-Wissen soll
-- niemandem verloren gehen); schreiben darf jedes eingeloggte Teammitglied.
create policy "aemtli_learnings: select für eingeloggte" on aemtli_learnings
  for select to authenticated using (true);
create policy "aemtli_learnings: insert für Lagerteam" on aemtli_learnings
  for insert to authenticated
  with check (public.is_lager_team(lager_id));

-- einkaufsliste_items: nur das jeweilige Lagerteam.
create policy "einkaufsliste_items: für Lagerteam" on einkaufsliste_items
  for all to authenticated
  using (public.is_lager_team(lager_id))
  with check (public.is_lager_team(lager_id));

-- reminders: nur das jeweilige Lagerteam sieht/verwaltet sie; der Versand
-- selbst läuft über eine Edge Function mit Service-Role, nicht über RLS.
create policy "reminders: für Lagerteam" on reminders
  for all to authenticated
  using (public.is_lager_team(lager_id))
  with check (public.is_lager_team(lager_id));
