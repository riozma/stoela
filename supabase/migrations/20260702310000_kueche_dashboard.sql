-- Küche-Dashboard: Uhrzeiten, Essensgewohnheiten, allgemeine Küchennotizen

alter table mahlzeit_vorlagen
  add column if not exists uhrzeit time;

alter table mahlzeiten
  add column if not exists uhrzeit time;

alter table anmeldungen_tn
  add column if not exists essensgewohnheiten text;

alter table anmeldungen_leiter
  add column if not exists essensgewohnheiten text;

create table if not exists kueche_notizen (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  titel text not null,
  inhalt text not null,
  kategorie text not null default 'allgemein'
    check (kategorie in ('allgemein', 'allergie', 'planung', 'einkauf', 'hygiene')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table kueche_notizen enable row level security;

create policy "kueche_notizen: lagerteam" on kueche_notizen
  for all to authenticated
  using (public.can_access_lager(lager_id))
  with check (public.can_access_lager(lager_id));
