-- Höck-Typen (Verein-Ebene, gelten für alle Lager/Jahre des Vereins) und
-- ihre Traktanden (Checkliste, was besprochen werden soll). Standard-
-- Typen (Starthöck/Lagerhöck/Vorweekend/Feedbackhöck) werden pro Verein
-- automatisch angelegt; Lalei kann weitere eigene Typen erstellen, die
-- optional ins Folgejahr übernommen werden (uebernehmen_naechstes_jahr).
-- Da Höck-Typen und Traktanden nur im Verein gespeichert sind (nicht pro
-- Lager kopiert), gelten Änderungen automatisch für alle Lager - keine
-- separate "Übernahme"-Logik nötig.
create table hoeck_typen (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisation(id) on delete cascade,
  name text not null,
  ist_standard boolean not null default false,
  uebernehmen_naechstes_jahr boolean not null default true,
  sortierung int not null default 0,
  created_at timestamptz not null default now(),
  unique (organisation_id, name)
);

create table hoeck_traktanden (
  id uuid primary key default gen_random_uuid(),
  hoeck_typ_id uuid not null references hoeck_typen(id) on delete cascade,
  text text not null,
  sortierung int not null default 0,
  created_at timestamptz not null default now()
);

-- Abhak-Status pro Lager und Tag (ein Traktandum kann an mehreren Tagen wiederkehren).
create table hoeck_traktanden_erledigt (
  lager_id uuid not null references lager(id) on delete cascade,
  tag date not null,
  traktandum_id uuid not null references hoeck_traktanden(id) on delete cascade,
  erledigt_am timestamptz not null default now(),
  primary key (lager_id, tag, traktandum_id)
);

alter table hoeck_typen enable row level security;
alter table hoeck_traktanden enable row level security;
alter table hoeck_traktanden_erledigt enable row level security;

create policy "hoeck_typen: select org-mitglieder" on hoeck_typen
for select using (is_org_mitglied(organisation_id) or is_org_leitung(organisation_id));

create policy "hoeck_typen: verwalten org-leitung" on hoeck_typen
for all using (is_org_leitung(organisation_id)) with check (is_org_leitung(organisation_id));

create policy "hoeck_traktanden: select via typ" on hoeck_traktanden
for select using (
  exists (select 1 from hoeck_typen t where t.id = hoeck_typ_id and (is_org_mitglied(t.organisation_id) or is_org_leitung(t.organisation_id)))
);

create policy "hoeck_traktanden: verwalten via typ" on hoeck_traktanden
for all using (
  exists (select 1 from hoeck_typen t where t.id = hoeck_typ_id and is_org_leitung(t.organisation_id))
) with check (
  exists (select 1 from hoeck_typen t where t.id = hoeck_typ_id and is_org_leitung(t.organisation_id))
);

create policy "hoeck_traktanden_erledigt: select lagerteam" on hoeck_traktanden_erledigt
for select using (can_access_lager(lager_id));

create policy "hoeck_traktanden_erledigt: insert lagerteam" on hoeck_traktanden_erledigt
for insert with check (can_access_lager(lager_id));

create policy "hoeck_traktanden_erledigt: delete lagerteam" on hoeck_traktanden_erledigt
for delete using (can_access_lager(lager_id));

-- Standard-Typen + Default-Traktanden für einen Verein sicherstellen (idempotent).
create or replace function public.hoeck_typen_sicherstellen(p_organisation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lagerhoeck_id uuid;
  v_starthoeck_id uuid;
begin
  if not exists (select 1 from hoeck_typen where organisation_id = p_organisation_id and name = 'Lagerhöck') then
    insert into hoeck_typen (organisation_id, name, ist_standard, sortierung)
    values (p_organisation_id, 'Lagerhöck', true, 1)
    returning id into v_lagerhoeck_id;
    insert into hoeck_traktanden (hoeck_typ_id, text, sortierung) values
      (v_lagerhoeck_id, 'Feedback vom Tag', 1),
      (v_lagerhoeck_id, 'Vorstellen des nächsten Tages: Motto und Feinprogramm', 2),
      (v_lagerhoeck_id, 'Rollenzuteilung', 3),
      (v_lagerhoeck_id, 'Nachtruhe', 4),
      (v_lagerhoeck_id, 'Tagwach', 5),
      (v_lagerhoeck_id, 'Allgemeines im Lager', 6);
  end if;

  if not exists (select 1 from hoeck_typen where organisation_id = p_organisation_id and name = 'Starthöck') then
    insert into hoeck_typen (organisation_id, name, ist_standard, sortierung)
    values (p_organisation_id, 'Starthöck', true, 0)
    returning id into v_starthoeck_id;
    insert into hoeck_traktanden (hoeck_typ_id, text, sortierung) values
      (v_starthoeck_id, 'Ämtli verteilen', 1),
      (v_starthoeck_id, 'Optional: Motto festlegen', 2),
      (v_starthoeck_id, 'Planungsstand dokumentieren', 3),
      (v_starthoeck_id, 'Sicherstellen, dass alle im Lager (System) aufgenommen sind', 4),
      (v_starthoeck_id, 'Küchenteam besprechen', 5);
  end if;

  if not exists (select 1 from hoeck_typen where organisation_id = p_organisation_id and name = 'Vorweekend') then
    insert into hoeck_typen (organisation_id, name, ist_standard, sortierung)
    values (p_organisation_id, 'Vorweekend', true, 2)
    returning id into v_lagerhoeck_id;
    insert into hoeck_traktanden (hoeck_typ_id, text, sortierung) values
      (v_lagerhoeck_id, 'Feinprogramm erarbeiten', 1),
      (v_lagerhoeck_id, 'Weiteres Lagerbezogenes besprechen', 2);
  end if;

  if not exists (select 1 from hoeck_typen where organisation_id = p_organisation_id and name = 'Feedbackhöck') then
    insert into hoeck_typen (organisation_id, name, ist_standard, sortierung)
    values (p_organisation_id, 'Feedbackhöck', true, 3);
  end if;
end;
$$;

grant execute on function public.hoeck_typen_sicherstellen(uuid) to authenticated;
