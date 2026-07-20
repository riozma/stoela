-- Org-weite "wer hat aktuell welches Ämtli" -Zuordnung. Wird im
-- Organisation/Team-Tab gepflegt und kaskadiert automatisch auf alle
-- kommenden (noch nicht vergangenen) Lager. Neue Lager erben beim
-- Erstellen entweder diese Org-Zuteilung oder, falls dort nichts
-- gesetzt ist, die Zuteilung des zuletzt vergangenen Lagers.
create table org_aemtli_besetzung (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisation (id) on delete cascade,
  aemtli_id uuid not null references aemtli (id) on delete cascade,
  profile_id uuid references profiles (id),
  updated_at timestamptz not null default now(),
  updated_by uuid references profiles (id),
  unique (organisation_id, aemtli_id)
);

alter table org_aemtli_besetzung enable row level security;

-- Lagerleitung, Admin und normale (bestätigte) Leiter dürfen die
-- Ämtli-Besetzung anpassen -- bewusst nicht nur Admin/Leitung.
create policy "org_aemtli_besetzung: select für Mitglieder" on org_aemtli_besetzung
  for select to authenticated
  using (
    exists (
      select 1 from organisation_mitglieder om
      where om.organisation_id = org_aemtli_besetzung.organisation_id
        and om.profile_id = auth.uid() and om.status = 'mitglied'
    )
  );

create policy "org_aemtli_besetzung: schreiben für Mitglieder" on org_aemtli_besetzung
  for all to authenticated
  using (
    exists (
      select 1 from organisation_mitglieder om
      where om.organisation_id = org_aemtli_besetzung.organisation_id
        and om.profile_id = auth.uid() and om.status = 'mitglied'
    )
  )
  with check (
    exists (
      select 1 from organisation_mitglieder om
      where om.organisation_id = org_aemtli_besetzung.organisation_id
        and om.profile_id = auth.uid() and om.status = 'mitglied'
    )
  );

-- Aufgelöste (mit Fallback-Kette) aktuelle Ämtli-Besetzung eines Vereins
create or replace function public.resolve_org_aemtli_besetzung(p_organisation_id uuid)
returns table (
  aemtli_id uuid,
  aemtli_name text,
  profile_id uuid,
  vorname text,
  nachname text,
  email text,
  quelle text
)
language sql
security definer
stable
set search_path = public
as $$
  with letztes_lager as (
    select id from lager
    where organisation_id = p_organisation_id
      and end_datum is not null and end_datum < current_date
    order by end_datum desc
    limit 1
  )
  select
    a.id as aemtli_id,
    a.name as aemtli_name,
    coalesce(b.profile_id, az.profile_id) as profile_id,
    p.vorname, p.nachname, p.email,
    case
      when b.profile_id is not null then 'organisation'
      when az.profile_id is not null then 'letztes_lager'
      else 'keine'
    end as quelle
  from aemtli a
  left join org_aemtli_besetzung b on b.organisation_id = p_organisation_id and b.aemtli_id = a.id
  left join letztes_lager ll on true
  left join aemtli_zuweisungen az on az.lager_id = ll.id and az.aemtli_id = a.id
  left join profiles p on p.id = coalesce(b.profile_id, az.profile_id)
  where a.aktiv
  order by a.name;
$$;

grant execute on function public.resolve_org_aemtli_besetzung(uuid) to authenticated;

-- Kaskadiert eine geänderte Org-Besetzung sofort auf alle kommenden
-- (noch nicht vergangenen) Lager desselben Vereins.
create or replace function public.kaskadiere_aemtli_besetzung()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  l record;
begin
  if new.profile_id is not null then
    for l in
      select id from lager
      where organisation_id = new.organisation_id
        and (end_datum is null or end_datum >= current_date)
    loop
      insert into aemtli_zuweisungen (lager_id, aemtli_id, profile_id, status)
      values (l.id, new.aemtli_id, new.profile_id, 'offen')
      on conflict (lager_id, aemtli_id) do update set profile_id = excluded.profile_id;
    end loop;
  end if;
  return new;
end;
$$;

create trigger trg_kaskadiere_aemtli_besetzung
  after insert or update on org_aemtli_besetzung
  for each row execute function public.kaskadiere_aemtli_besetzung();

-- Neue Lager erben beim Erstellen die aufgelöste Org-Besetzung
-- (Org-Wert, sonst zuletzt vergangenes Lager).
create or replace function public.seed_aemtli_von_organisation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  if new.organisation_id is null then
    return new;
  end if;
  for r in select aemtli_id, profile_id from public.resolve_org_aemtli_besetzung(new.organisation_id) where profile_id is not null
  loop
    insert into aemtli_zuweisungen (lager_id, aemtli_id, profile_id, status)
    values (new.id, r.aemtli_id, r.profile_id, 'offen')
    on conflict (lager_id, aemtli_id) do nothing;
  end loop;
  return new;
end;
$$;

create trigger trg_seed_aemtli_von_organisation
  after insert on lager
  for each row execute function public.seed_aemtli_von_organisation();
