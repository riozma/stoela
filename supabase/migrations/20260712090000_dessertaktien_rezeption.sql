-- Dessertaktien: Zustupf pro Leiterteam am Anreisetag, finanziert das
-- Dessert. Wird an der Rezeption erfasst, ist danach in Küche und
-- Finanzen/Kassier-Ämtli sichtbar (nur Beiträge > 0).
create table dessertaktien (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager(id) on delete cascade,
  name text not null,
  betrag numeric not null check (betrag >= 0),
  erfasst_von uuid references profiles(id),
  created_at timestamptz not null default now()
);

alter table dessertaktien enable row level security;

create policy "dessertaktien: select für Lagerteam" on dessertaktien
for select using (can_access_lager(lager_id));

create policy "dessertaktien: insert für Lagerteam" on dessertaktien
for insert with check (can_access_lager(lager_id));

create policy "dessertaktien: delete für Lagerleitung" on dessertaktien
for delete using (is_lager_leitung(lager_id));
