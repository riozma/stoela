-- MVP-Lücken: Motto-Ämtli, Material-Chef/J+S-Ämtli, Lalei-Statistik

alter table lager add column if not exists motto text;

-- ---------------------------------------------------------------------
-- Motto: Vorschläge + Abstimmung
-- ---------------------------------------------------------------------
create table if not exists motto_vorschlaege (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  vorschlag text not null,
  stimmen int not null default 0,
  created_at timestamptz not null default now()
);

alter table motto_vorschlaege enable row level security;

create policy "motto_vorschlaege: team" on motto_vorschlaege for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));

-- ---------------------------------------------------------------------
-- Material-Chef / J+S: Bestell- und Rückgabe-Checkliste
-- ---------------------------------------------------------------------
create table if not exists material_bestellungen (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  artikel text not null,
  menge text,
  kategorie text not null default 'zu_bestellen'
    check (kategorie in ('zu_bestellen', 'bestellt', 'geliefert', 'zurueckgesendet')),
  notiz text,
  created_at timestamptz not null default now()
);

alter table material_bestellungen enable row level security;

create policy "material_bestellungen: team" on material_bestellungen for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));
