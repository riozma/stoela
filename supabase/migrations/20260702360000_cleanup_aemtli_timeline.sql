-- Sport & Programm als Ämtli entfernen; Skiweekend-Programm

delete from aemtli_zuweisungen
where aemtli_id in (select id from aemtli where name in ('Sport', 'Programm'));

delete from leiter_rollen
where aemtli_id in (select id from aemtli where name in ('Sport', 'Programm'));

delete from org_aemtli_meta
where aemtli_id in (select id from aemtli where name in ('Sport', 'Programm'));

delete from lager_todos
where aemtli_name in ('Sport', 'Programm');

delete from aemtli where name in ('Sport', 'Programm');

-- Skiweekend Timetable & Anmeldungen (Org-Ebene)
create table if not exists org_skiweekend_programm (
  id uuid primary key default gen_random_uuid(),
  skiweekend_id uuid not null references org_skiweekend (id) on delete cascade,
  tag date not null,
  start_zeit time,
  end_zeit time,
  titel text not null,
  ort text,
  beschreibung text,
  sortierung int not null default 0
);

create table if not exists org_skiweekend_anmeldungen (
  id uuid primary key default gen_random_uuid(),
  skiweekend_id uuid not null references org_skiweekend (id) on delete cascade,
  vorname text not null,
  nachname text not null,
  anwesend_von date,
  anwesend_bis date,
  notiz text,
  created_at timestamptz not null default now()
);

alter table org_skiweekend_programm enable row level security;
alter table org_skiweekend_anmeldungen enable row level security;

create policy "skiweekend_prog: team" on org_skiweekend_programm for all to authenticated using (true) with check (true);
create policy "skiweekend_anm: team" on org_skiweekend_anmeldungen for all to authenticated using (true) with check (true);

-- Feature-Freischaltung pro Ämtli (relativ zum Lagerstart)
alter table org_aemtli_meta add column if not exists aktiv_ab_monate numeric;
alter table org_aemtli_meta add column if not exists aktiv_bis_monate numeric;
alter table org_aemtli_meta add column if not exists feature_schluessel text;

update org_aemtli_meta m set
  aktiv_ab_monate = x.ab, aktiv_bis_monate = x.bis, feature_schluessel = x.key
from aemtli a
join (values
  ('Gute Fee', 'gute_fee', 0, null),
  ('Kiosk', 'kiosk', 0, null),
  ('Skiweekend', 'skiweekend', null, null),
  ('Motto', 'motto', null, 5),
  ('Werbung', 'werbung', null, 6),
  ('Sponsoring', 'sponsoring', null, 4),
  ('Kuchenstand', 'kuchenstand', null, 3)
) as x(name, key, ab, bis) on a.name = x.name
where m.aemtli_id = a.id;
