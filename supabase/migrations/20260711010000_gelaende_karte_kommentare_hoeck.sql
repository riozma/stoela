-- Geländespielwiese: Google-Maps-Pins, lagerweite Sichtbarkeit + Kommentare,
-- optionale Wiesen-Auswahl im Höck.

-- ---------------------------------------------------------------------
-- gelaendespielwiesen: Lesen für alle Team-Mitglieder, Schreiben nur für
-- das Ämtli «Geländespielwiese» (bzw. Lalei) – bisher durfte jeder mit
-- Lagerzugriff auch bearbeiten/löschen.
-- ---------------------------------------------------------------------
drop policy if exists "gelaende: team" on gelaendespielwiesen;

create policy "gelaende: select team" on gelaendespielwiesen for select to authenticated
  using (can_access_lager(lager_id));

create policy "gelaende: insert aemtli" on gelaendespielwiesen for insert to authenticated
  with check (hat_aemtli(lager_id, 'Geländespielwiese'));

create policy "gelaende: update aemtli" on gelaendespielwiesen for update to authenticated
  using (hat_aemtli(lager_id, 'Geländespielwiese'))
  with check (hat_aemtli(lager_id, 'Geländespielwiese'));

create policy "gelaende: delete aemtli" on gelaendespielwiesen for delete to authenticated
  using (hat_aemtli(lager_id, 'Geländespielwiese'));

-- ---------------------------------------------------------------------
-- Kommentare zu einer Wiese (für alle Team-Mitglieder, nicht nur das Ämtli)
-- ---------------------------------------------------------------------
create table if not exists gelaendespielwiesen_kommentare (
  id uuid primary key default gen_random_uuid(),
  wiese_id uuid not null references gelaendespielwiesen (id) on delete cascade,
  profile_id uuid references profiles (id) on delete set null,
  autor_name text not null,
  text text not null,
  created_at timestamptz not null default now()
);

alter table gelaendespielwiesen_kommentare enable row level security;

create policy "gelaende_kommentare: select team" on gelaendespielwiesen_kommentare for select to authenticated
  using (
    exists (
      select 1 from gelaendespielwiesen w
      where w.id = wiese_id and can_access_lager(w.lager_id)
    )
  );

create policy "gelaende_kommentare: insert team" on gelaendespielwiesen_kommentare for insert to authenticated
  with check (
    exists (
      select 1 from gelaendespielwiesen w
      where w.id = wiese_id and can_access_lager(w.lager_id)
    )
  );

-- ---------------------------------------------------------------------
-- Höck: optionale Wiesen-Auswahl pro Tag
-- ---------------------------------------------------------------------
create table if not exists hoeck_tag_wiese (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  tag date not null,
  wiese_id uuid references gelaendespielwiesen (id) on delete set null,
  unique (lager_id, tag)
);

alter table hoeck_tag_wiese enable row level security;

create policy "hoeck_tag_wiese: team" on hoeck_tag_wiese for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));
