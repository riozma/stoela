-- Verein als Überorganisation: Lager, Events und der Ämtli-Katalog hängen
-- daran, sodass Wissen (Ämtli-Inhalte, Learnings) jahresübergreifend auf
-- Vereinsebene bestehen bleibt statt an einem einzelnen Lager zu kleben.
create table verein (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

alter table verein enable row level security;
create policy "verein: für eingeloggte" on verein
  for all to authenticated using (true) with check (true);

insert into verein (name) values ('Stöcklilager Zuchwil');

alter table lager add column verein_id uuid references verein (id);
update lager set verein_id = (select id from verein limit 1);
alter table lager alter column verein_id set not null;

-- Leichte, einzelne Anlässe neben den grossen Lagern (z.B. Vereinsanlässe,
-- Vorbereitungstreffen), ebenfalls auf Vereinsebene.
create table events (
  id uuid primary key default gen_random_uuid(),
  verein_id uuid not null references verein (id) on delete cascade,
  name text not null,
  datum date,
  ort text,
  beschreibung text,
  created_at timestamptz not null default now()
);

alter table events enable row level security;
create policy "events: für eingeloggte" on events
  for all to authenticated using (true) with check (true);

-- Ämtli explizit auf Vereinsebene verorten + Seiteninhalt für die Ämtli
-- selbst gestaltbar machen (Einleitung, Anleitungen/Links, Standard-ToDos,
-- Verweise auf Ämtli-Funktionen -- als geordnete Liste von Blöcken, damit
-- Reihenfolge und Inhalt frei bearbeitbar sind).
alter table aemtli add column verein_id uuid references verein (id);
update aemtli set verein_id = (select id from verein limit 1);
alter table aemtli add column seiten_inhalt jsonb not null default '[]';

-- Learnings sollen als Vereins-Wissen zum Ämtli stehen bleiben, auch ohne
-- zwingenden Bezug zu einem einzelnen Lager.
alter table aemtli_learnings alter column lager_id drop not null;
