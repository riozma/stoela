-- Verein als übergeordnete Struktur für Lager
-- - Lager gehören zu einer Organisation (Verein)
-- - Login-Leiter/innen im Lager müssen Vereinsmitglied sein
-- - Beitrittsanfragen + Mitgliederverwaltung

-- Verein-Name vereinheitlichen
insert into organisation (name, slug, homepage)
values ('Stöcklilager Zuchwil', 'stoeckli', 'https://www.stoecklilager.ch')
on conflict (slug) do update set
  name = excluded.name,
  homepage = coalesce(excluded.homepage, organisation.homepage);

-- ---------------------------------------------------------------------
-- Vereins-Mitglieder (inkl. Beitrittsstatus)
-- ---------------------------------------------------------------------
create table if not exists organisation_mitglieder (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references organisation (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete cascade,
  rolle text not null default 'mitglied'
    check (rolle in ('mitglied', 'leitung', 'admin')),
  status text not null default 'angefragt'
    check (status in ('angefragt', 'mitglied', 'abgelehnt')),
  angefragt_am timestamptz not null default now(),
  bestaetigt_am timestamptz,
  bestaetigt_von uuid references profiles (id) on delete set null,
  notiz text,
  unique (organisation_id, profile_id)
);

alter table organisation_mitglieder enable row level security;

-- ---------------------------------------------------------------------
-- Helper
-- ---------------------------------------------------------------------
create or replace function public.is_org_mitglied(p_organisation_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from organisation_mitglieder om
    where om.organisation_id = p_organisation_id
      and om.profile_id = auth.uid()
      and om.status = 'mitglied'
  );
$$;

create or replace function public.is_org_leitung(p_organisation_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from organisation_mitglieder om
    where om.organisation_id = p_organisation_id
      and om.profile_id = auth.uid()
      and om.status = 'mitglied'
      and om.rolle in ('leitung', 'admin')
  );
$$;

create or replace function public.list_meine_vereine()
returns table (
  organisation_id uuid,
  slug text,
  name text,
  homepage text,
  meine_rolle text,
  mein_status text
)
language sql
security definer
stable
set search_path = public
as $$
  select
    o.id as organisation_id,
    o.slug,
    o.name,
    o.homepage,
    om.rolle as meine_rolle,
    om.status as mein_status
  from organisation_mitglieder om
  join organisation o on o.id = om.organisation_id
  where om.profile_id = auth.uid()
  order by o.name;
$$;

create or replace function public.list_vereinslager(p_organisation_id uuid)
returns table (
  id uuid,
  jahr int,
  name text,
  ort text,
  start_datum date,
  end_datum date,
  status text,
  can_edit boolean
)
language sql
security definer
stable
set search_path = public
as $$
  select
    l.id,
    l.jahr,
    l.name,
    l.ort,
    l.start_datum,
    l.end_datum,
    l.status,
    public.can_access_lager(l.id) as can_edit
  from lager l
  where l.organisation_id = p_organisation_id
    and public.is_org_mitglied(p_organisation_id)
  order by l.start_datum nulls last, l.jahr desc, l.name;
$$;

create or replace function public.verein_beitrittsanfrage_stellen(p_organisation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet.';
  end if;

  insert into organisation_mitglieder (
    organisation_id, profile_id, rolle, status, angefragt_am
  ) values (
    p_organisation_id, auth.uid(), 'mitglied', 'angefragt', now()
  )
  on conflict (organisation_id, profile_id) do update set
    status = case
      when organisation_mitglieder.status = 'mitglied' then 'mitglied'
      else 'angefragt'
    end,
    angefragt_am = now();
end;
$$;

create or replace function public.verein_beitrittsanfrage_entscheiden(
  p_organisation_id uuid,
  p_profile_id uuid,
  p_entscheidung text,
  p_org_person_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  if not public.is_org_leitung(p_organisation_id) then
    raise exception 'Nur Vereinsleitung darf Beitritte entscheiden.';
  end if;

  if p_entscheidung = 'genehmigen' then
    insert into organisation_mitglieder (
      organisation_id, profile_id, rolle, status, angefragt_am, bestaetigt_am, bestaetigt_von
    ) values (
      p_organisation_id, p_profile_id, 'mitglied', 'mitglied', now(), now(), auth.uid()
    )
    on conflict (organisation_id, profile_id) do update set
      status = 'mitglied',
      bestaetigt_am = now(),
      bestaetigt_von = auth.uid();

    if p_org_person_id is not null then
      update org_personen
      set profile_id = p_profile_id
      where id = p_org_person_id
        and organisation_id = p_organisation_id;
    else
      select email into v_email from profiles where id = p_profile_id;
      if v_email is not null then
        update org_personen
        set profile_id = p_profile_id
        where organisation_id = p_organisation_id
          and profile_id is null
          and email is not null
          and lower(email) = lower(v_email);
      end if;
    end if;
  elsif p_entscheidung = 'ablehnen' then
    insert into organisation_mitglieder (
      organisation_id, profile_id, rolle, status, angefragt_am, bestaetigt_von
    ) values (
      p_organisation_id, p_profile_id, 'mitglied', 'abgelehnt', now(), auth.uid()
    )
    on conflict (organisation_id, profile_id) do update set
      status = 'abgelehnt',
      bestaetigt_von = auth.uid();
  else
    raise exception 'Ungültige Entscheidung.';
  end if;
end;
$$;

grant execute on function public.is_org_mitglied(uuid) to authenticated;
grant execute on function public.is_org_leitung(uuid) to authenticated;
grant execute on function public.list_meine_vereine() to authenticated;
grant execute on function public.list_vereinslager(uuid) to authenticated;
grant execute on function public.verein_beitrittsanfrage_stellen(uuid) to authenticated;
grant execute on function public.verein_beitrittsanfrage_entscheiden(uuid, uuid, text, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Lager lesen für Vereinsmitglieder (Gastansicht)
-- ---------------------------------------------------------------------
create or replace function public.can_view_lager(p_lager_id uuid)
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
        public.can_access_lager(p_lager_id)
        or exists (
          select 1
          from organisation_mitglieder om
          where om.organisation_id = l.organisation_id
            and om.profile_id = auth.uid()
            and om.status = 'mitglied'
        )
      )
  );
$$;

grant execute on function public.can_view_lager(uuid) to authenticated;

drop policy if exists "lager: select für berechtigte" on lager;
create policy "lager: select für berechtigte" on lager
  for select to authenticated
  using (public.can_view_lager(id));

-- ---------------------------------------------------------------------
-- Backfill: alle bestehenden Lager dem Verein Stöcklilager Zuchwil zuordnen
-- ---------------------------------------------------------------------
update lager
set organisation_id = (select id from organisation where slug = 'stoeckli' limit 1)
where organisation_id is null;

-- Creator = admin
insert into organisation_mitglieder (
  organisation_id, profile_id, rolle, status, angefragt_am, bestaetigt_am
)
select distinct
  l.organisation_id,
  l.created_by,
  'admin',
  'mitglied',
  now(),
  now()
from lager l
where l.organisation_id is not null
  and l.created_by is not null
on conflict (organisation_id, profile_id) do update set
  status = 'mitglied',
  rolle = case
    when organisation_mitglieder.rolle = 'admin' then 'admin'
    else 'admin'
  end,
  bestaetigt_am = coalesce(organisation_mitglieder.bestaetigt_am, now());

-- Lagerleitung/Leiter aus lager_leiter
insert into organisation_mitglieder (
  organisation_id, profile_id, rolle, status, angefragt_am, bestaetigt_am
)
select distinct
  l.organisation_id,
  ll.profile_id,
  case when ll.rolle = 'lagerleitung' then 'leitung' else 'mitglied' end,
  'mitglied',
  now(),
  now()
from lager_leiter ll
join lager l on l.id = ll.lager_id
where l.organisation_id is not null
  and ll.profile_id is not null
  and ll.status = 'bestaetigt'
on conflict (organisation_id, profile_id) do update set
  status = 'mitglied',
  rolle = case
    when organisation_mitglieder.rolle = 'admin' then 'admin'
    when excluded.rolle = 'leitung' then 'leitung'
    else organisation_mitglieder.rolle
  end,
  bestaetigt_am = coalesce(organisation_mitglieder.bestaetigt_am, now());

-- Bereits bestätigte Leiter-Anmeldungen mit Login
insert into organisation_mitglieder (
  organisation_id, profile_id, rolle, status, angefragt_am, bestaetigt_am
)
select distinct
  l.organisation_id,
  al.profile_id,
  'mitglied',
  'mitglied',
  now(),
  now()
from anmeldungen_leiter al
join lager l on l.id = al.lager_id
where l.organisation_id is not null
  and al.profile_id is not null
  and al.status in ('bestaetigt', 'angemeldet')
on conflict (organisation_id, profile_id) do update set
  status = 'mitglied',
  bestaetigt_am = coalesce(organisation_mitglieder.bestaetigt_am, now());

-- Manuelle Vereins-Personen mit Login ebenfalls als Mitglied markieren
insert into organisation_mitglieder (
  organisation_id, profile_id, rolle, status, angefragt_am, bestaetigt_am
)
select distinct
  op.organisation_id,
  op.profile_id,
  'mitglied',
  'mitglied',
  now(),
  now()
from org_personen op
where op.profile_id is not null
on conflict (organisation_id, profile_id) do update set
  status = 'mitglied',
  bestaetigt_am = coalesce(organisation_mitglieder.bestaetigt_am, now());

-- ---------------------------------------------------------------------
-- RLS Vereins-Mitglieder
-- ---------------------------------------------------------------------
drop policy if exists "org_mitglieder: select own org" on organisation_mitglieder;
drop policy if exists "org_mitglieder: insert request" on organisation_mitglieder;
drop policy if exists "org_mitglieder: update org lead" on organisation_mitglieder;
drop policy if exists "org_mitglieder: delete org lead or self" on organisation_mitglieder;

create policy "org_mitglieder: select own org" on organisation_mitglieder
  for select to authenticated
  using (
    profile_id = auth.uid()
    or public.is_org_mitglied(organisation_id)
  );

create policy "org_mitglieder: insert request" on organisation_mitglieder
  for insert to authenticated
  with check (
    (profile_id = auth.uid() and status = 'angefragt' and rolle = 'mitglied')
    or public.is_org_leitung(organisation_id)
  );

create policy "org_mitglieder: update org lead" on organisation_mitglieder
  for update to authenticated
  using (public.is_org_leitung(organisation_id))
  with check (public.is_org_leitung(organisation_id));

create policy "org_mitglieder: delete org lead or self" on organisation_mitglieder
  for delete to authenticated
  using (
    public.is_org_leitung(organisation_id)
    or profile_id = auth.uid()
  );

-- Organisation verwalten
drop policy if exists "organisation: insert authenticated" on organisation;
drop policy if exists "organisation: update org lead" on organisation;

create policy "organisation: insert authenticated" on organisation
  for insert to authenticated
  with check (true);

create policy "organisation: update org lead" on organisation
  for update to authenticated
  using (public.is_org_leitung(id))
  with check (public.is_org_leitung(id));

-- Org-Personen + Vorlagen nur für Vereinsmitglieder
drop policy if exists "org_personen: team" on org_personen;
drop policy if exists "org_aemtli_meta: team" on org_aemtli_meta;
drop policy if exists "org_todo_vorlagen: team" on org_todo_vorlagen;
drop policy if exists "org_elterninfo: team" on org_elterninfo_vorlage;

create policy "org_personen: lesen vereinsmitglieder" on org_personen
  for select to authenticated
  using (public.is_org_mitglied(organisation_id));

create policy "org_personen: schreiben vereinsleitung" on org_personen
  for all to authenticated
  using (public.is_org_leitung(organisation_id))
  with check (public.is_org_leitung(organisation_id));

create policy "org_aemtli_meta: vereinsmitglieder" on org_aemtli_meta
  for all to authenticated
  using (public.is_org_mitglied(organisation_id))
  with check (public.is_org_mitglied(organisation_id));

create policy "org_todo_vorlagen: vereinsmitglieder" on org_todo_vorlagen
  for all to authenticated
  using (public.is_org_mitglied(organisation_id))
  with check (public.is_org_mitglied(organisation_id));

create policy "org_elterninfo: vereinsmitglieder" on org_elterninfo_vorlage
  for all to authenticated
  using (public.is_org_mitglied(organisation_id))
  with check (public.is_org_mitglied(organisation_id));

-- ---------------------------------------------------------------------
-- Leiter im Lager nur als Vereinsmitglied (für Login-Profile)
-- ---------------------------------------------------------------------
drop policy if exists "anmeldungen_leiter: insert eigene Anfrage" on anmeldungen_leiter;
create policy "anmeldungen_leiter: insert eigene Anfrage" on anmeldungen_leiter
  for insert to authenticated
  with check (
    profile_id = auth.uid()
    and exists (
      select 1
      from lager l
      join organisation_mitglieder om on om.organisation_id = l.organisation_id
      where l.id = lager_id
        and l.status in ('planung', 'anmeldung_offen', 'laufend')
        and om.profile_id = auth.uid()
        and om.status = 'mitglied'
    )
  );

create or replace function public.ensure_leiter_ist_vereinsmitglied()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_org uuid;
begin
  if new.profile_id is null then
    return new;
  end if;

  select organisation_id into v_org from lager where id = new.lager_id;
  if v_org is null then
    return new;
  end if;

  if not exists (
    select 1
    from organisation_mitglieder om
    where om.organisation_id = v_org
      and om.profile_id = new.profile_id
      and om.status = 'mitglied'
  ) then
    raise exception 'Leiter/in muss zuerst Vereinsmitglied sein.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_leiter_ist_vereinsmitglied on anmeldungen_leiter;
create trigger trg_leiter_ist_vereinsmitglied
before insert or update of profile_id, lager_id
on anmeldungen_leiter
for each row
execute function public.ensure_leiter_ist_vereinsmitglied();

