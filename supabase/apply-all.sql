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
-- Geo-Felder für den Lagerort (Google Places Autocomplete)
alter table lager add column ort_lat numeric;
alter table lager add column ort_lng numeric;
alter table lager add column ort_place_id text;

-- Programmblöcke (LP/LS/LA/ES) eines Lagers, z.B. aus eCamp-PDF-Import
create table programmbloecke (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  code text not null check (code in ('LP', 'LS', 'LA', 'ES')),
  nummer text,
  titel text not null,
  tag date,
  start_zeit timestamptz,
  end_zeit timestamptz,
  ort text,
  ort_lat numeric,
  ort_lng numeric,
  ort_place_id text,
  verantwortlich text,
  geschichte text,
  sicherheitsueberlegungen text,
  programmabschnitt jsonb not null default '[]',
  material jsonb not null default '[]',
  notizen text,
  quelle text not null default 'manuell' check (quelle in ('manuell', 'ecamp_pdf')),
  created_at timestamptz not null default now()
);

alter table programmbloecke enable row level security;

create policy "programmbloecke: für Lagerteam" on programmbloecke
  for all to authenticated
  using (public.is_lager_team(lager_id))
  with check (public.is_lager_team(lager_id));
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
-- Öffentliche Anmeldeformulare (TN/Leiter) müssen den Lagernamen und Status
-- ohne Login lesen können, aber nur solange die Anmeldung offen ist.
create policy "lager: select öffentlich bei offener Anmeldung" on lager
  for select to anon
  using (status = 'anmeldung_offen');
-- Verschärfte Zugriffskontrolle: nur Ersteller/in oder freigeschaltete Teammitglieder
-- sehen ein Lager. Öffentliche TN-Seite nur über RPC mit Basisdaten.

alter table lager add column if not exists created_by uuid references profiles (id);

-- Bestehende Lager: Ersteller/in aus erster Lagerleitung ableiten
update lager l
set created_by = ll.profile_id
from lager_leiter ll
where l.id = ll.lager_id
  and ll.rolle = 'lagerleitung'
  and ll.status = 'bestaetigt'
  and l.created_by is null;

-- ---------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------

create or replace function public.can_access_lager(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from lager l
    where l.id = p_lager_id
      and (
        l.created_by = auth.uid()
        or exists (
          select 1 from lager_leiter ll
          where ll.lager_id = p_lager_id
            and ll.profile_id = auth.uid()
            and ll.status = 'bestaetigt'
        )
      )
  );
$$;

create or replace function public.is_lager_leitung(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from lager_leiter ll
    where ll.lager_id = p_lager_id
      and ll.profile_id = auth.uid()
      and ll.status = 'bestaetigt'
      and ll.rolle = 'lagerleitung'
  )
  or exists (
    select 1 from lager l
    where l.id = p_lager_id and l.created_by = auth.uid()
  );
$$;

create or replace function public.is_lager_team(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.can_access_lager(p_lager_id);
$$;

create or replace function public.shares_lager_with(p_profile_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from lager_leiter ll1
    join lager_leiter ll2 on ll1.lager_id = ll2.lager_id
    where ll1.profile_id = auth.uid()
      and ll1.status = 'bestaetigt'
      and ll2.profile_id = p_profile_id
      and ll2.status = 'bestaetigt'
  );
$$;

-- Öffentliche Willkommensseite für TN (kein Programm!)
create or replace function public.get_lager_willkommen(p_lager_id uuid)
returns json
language sql
security definer
stable
set search_path = public
as $$
  select json_build_object(
    'id', l.id,
    'name', l.name,
    'ort', l.ort,
    'start_datum', l.start_datum,
    'end_datum', l.end_datum,
    'ort_lat', l.ort_lat,
    'ort_lng', l.ort_lng,
    'status', l.status
  )
  from lager l
  where l.id = p_lager_id
    and l.status <> 'archiviert';
$$;

grant execute on function public.get_lager_willkommen(uuid) to anon, authenticated;

-- Teammitglied per E-Mail freischalten (nur Lagerleitung)
create or replace function public.freischalten_teammitglied(
  p_lager_id uuid,
  p_email text,
  p_rolle text default 'leiter'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_leiter_id uuid;
begin
  if not public.is_lager_leitung(p_lager_id) then
    raise exception 'Nur die Lagerleitung darf Teammitglieder freischalten.';
  end if;

  select id into v_profile_id from profiles where lower(email) = lower(trim(p_email));
  if v_profile_id is null then
    raise exception 'Kein Profil mit dieser E-Mail gefunden. Die Person muss sich zuerst einloggen.';
  end if;

  insert into lager_leiter (lager_id, profile_id, rolle, status)
  values (p_lager_id, v_profile_id, p_rolle, 'bestaetigt')
  on conflict (lager_id, profile_id) do update
    set rolle = excluded.rolle, status = 'bestaetigt'
  returning id into v_leiter_id;

  return v_leiter_id;
end;
$$;

grant execute on function public.freischalten_teammitglied(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- RLS Policies ersetzen
-- ---------------------------------------------------------------------

-- lager
drop policy if exists "lager: select für eingeloggte" on lager;
drop policy if exists "lager: insert/update für eingeloggte" on lager;
drop policy if exists "lager: select öffentlich bei offener Anmeldung" on lager;

create policy "lager: select für berechtigte" on lager
  for select to authenticated
  using (public.can_access_lager(id));

create policy "lager: insert für eingeloggte" on lager
  for insert to authenticated
  with check (created_by = auth.uid());

create policy "lager: update für Lagerteam" on lager
  for update to authenticated
  using (public.can_access_lager(id))
  with check (public.can_access_lager(id));

create policy "lager: delete für Lagerleitung" on lager
  for delete to authenticated
  using (public.is_lager_leitung(id));

-- Keine breite Lager-SELECT-Policy für Anmeldung: öffentliche Seiten nutzen RPCs
-- (get_lager_anmeldung_info, get_lager_willkommen). Siehe Migration 20260702270000.

-- profiles
drop policy if exists "profiles: select für eingeloggte" on profiles;
drop policy if exists "profiles: update eigene Zeile" on profiles;

create policy "profiles: select eigenes oder Lagerteam" on profiles
  for select to authenticated
  using (
    auth.uid() = id
    or public.shares_lager_with(id)
    or exists (
      select 1 from lager_leiter ll
      where ll.profile_id = auth.uid()
        and ll.rolle = 'lagerleitung'
        and ll.status = 'bestaetigt'
    )
  );

create policy "profiles: update eigene Zeile" on profiles
  for update to authenticated
  using (auth.uid() = id);

-- lager_leiter
drop policy if exists "lager_leiter: select für eingeloggte" on lager_leiter;
drop policy if exists "lager_leiter: insert für eingeloggte" on lager_leiter;
drop policy if exists "lager_leiter: update eigene Zeile" on lager_leiter;

create policy "lager_leiter: select für berechtigte" on lager_leiter
  for select to authenticated
  using (public.can_access_lager(lager_id) or profile_id = auth.uid());

create policy "lager_leiter: insert für Lagerleitung" on lager_leiter
  for insert to authenticated
  with check (
    public.is_lager_leitung(lager_id)
    or exists (
      select 1 from lager l
      where l.id = lager_id and l.created_by = auth.uid()
    )
  );

create policy "lager_leiter: update für Lagerleitung oder eigene Zeile" on lager_leiter
  for update to authenticated
  using (public.is_lager_leitung(lager_id) or profile_id = auth.uid());

create policy "lager_leiter: delete für Lagerleitung" on lager_leiter
  for delete to authenticated
  using (public.is_lager_leitung(lager_id));

-- aemtli: nur für berechtigte Lagerteams (nicht global mehr)
drop policy if exists "aemtli: select für eingeloggte" on aemtli;
drop policy if exists "aemtli: insert/update für eingeloggte" on aemtli;

create policy "aemtli: select für Lagerteam" on aemtli
  for select to authenticated
  using (
    exists (
      select 1 from lager_leiter ll
      where ll.profile_id = auth.uid() and ll.status = 'bestaetigt'
    )
  );

create policy "aemtli: insert/update für Lagerteam" on aemtli
  for all to authenticated
  using (
    exists (
      select 1 from lager_leiter ll
      where ll.profile_id = auth.uid() and ll.status = 'bestaetigt'
    )
  )
  with check (
    exists (
      select 1 from lager_leiter ll
      where ll.profile_id = auth.uid() and ll.status = 'bestaetigt'
    )
  );

-- aemtli_learnings: nur für berechtigte
drop policy if exists "aemtli_learnings: select für eingeloggte" on aemtli_learnings;
drop policy if exists "aemtli_learnings: insert für Lagerteam" on aemtli_learnings;

create policy "aemtli_learnings: select für Lagerteam" on aemtli_learnings
  for select to authenticated
  using (public.can_access_lager(lager_id));

create policy "aemtli_learnings: insert für Lagerteam" on aemtli_learnings
  for insert to authenticated
  with check (public.can_access_lager(lager_id));

create policy "aemtli_learnings: update/delete für Lagerteam" on aemtli_learnings
  for all to authenticated
  using (public.can_access_lager(lager_id))
  with check (public.can_access_lager(lager_id));
