-- Leiter-Anfragen (Login erforderlich), Einkaufsliste erweitern, Höck

-- ---------------------------------------------------------------------
-- Leiter: Profil-Verknüpfung + Status 'angefragt'
-- ---------------------------------------------------------------------
alter table anmeldungen_leiter add column if not exists profile_id uuid references profiles (id);

alter table anmeldungen_leiter drop constraint if exists anmeldungen_leiter_status_check;
alter table anmeldungen_leiter add constraint anmeldungen_leiter_status_check
  check (status in ('angefragt', 'angemeldet', 'bestaetigt', 'abgesagt', 'abgelehnt'));

create unique index if not exists anmeldungen_leiter_eine_offene_anfrage
  on anmeldungen_leiter (lager_id, profile_id)
  where profile_id is not null and status = 'angefragt';

-- Öffentliche TN/Lager-Info für Anmeldeformulare
create or replace function public.get_lager_anmeldung_info(p_lager_id uuid)
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
    'status', l.status
  )
  from lager l
  where l.id = p_lager_id
    and l.status = 'anmeldung_offen';
$$;

grant execute on function public.get_lager_anmeldung_info(uuid) to anon, authenticated;

-- Leiter-Anfrage genehmigen → Team-Zugang
create or replace function public.leiter_anfrage_bearbeiten(
  p_anmeldung_id uuid,
  p_entscheidung text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager_id uuid;
  v_profile_id uuid;
begin
  select lager_id, profile_id into v_lager_id, v_profile_id
  from anmeldungen_leiter
  where id = p_anmeldung_id and status = 'angefragt';

  if v_lager_id is null then
    raise exception 'Anfrage nicht gefunden oder bereits bearbeitet.';
  end if;

  if not public.is_lager_leitung(v_lager_id) then
    raise exception 'Nur die Lagerleitung darf Leiter-Anfragen bearbeiten.';
  end if;

  if p_entscheidung = 'genehmigen' then
    if v_profile_id is null then
      raise exception 'Anfrage hat kein verknüpftes Profil.';
    end if;
    update anmeldungen_leiter set status = 'bestaetigt' where id = p_anmeldung_id;
    insert into lager_leiter (lager_id, profile_id, rolle, status)
    values (v_lager_id, v_profile_id, 'leiter', 'bestaetigt')
    on conflict (lager_id, profile_id) do update set status = 'bestaetigt';
  elsif p_entscheidung = 'ablehnen' then
    update anmeldungen_leiter set status = 'abgelehnt' where id = p_anmeldung_id;
  else
    raise exception 'Ungültige Entscheidung.';
  end if;
end;
$$;

grant execute on function public.leiter_anfrage_bearbeiten(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- Einkaufsliste erweitern
-- ---------------------------------------------------------------------
insert into aemtli (name, beschreibung)
values ('Küche', 'Einkauf und Mahlzeiten')
on conflict (name) do nothing;

alter table einkaufsliste_items
  add column if not exists bereich text not null default 'lager'
    check (bereich in ('privat', 'lager', 'programm')),
  add column if not exists mahlzeit text
    check (mahlzeit is null or mahlzeit in ('fruehstueck', 'zmittag', 'znacht', 'jause')),
  add column if not exists programm_block_id uuid references programmbloecke (id) on delete set null,
  add column if not exists notiz text;

create table if not exists einkaufs_termine (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  einkauf_am timestamptz not null,
  frueh_geschlossen boolean not null default false,
  erstellt_von uuid references profiles (id),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Höck (Tagesbesprechung)
-- ---------------------------------------------------------------------
create table if not exists hoeck_notizen (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  tag date not null,
  notizen text,
  updated_by uuid references profiles (id),
  updated_at timestamptz not null default now(),
  unique (lager_id, tag)
);

-- ---------------------------------------------------------------------
-- Hilfsfunktionen Berechtigungen
-- ---------------------------------------------------------------------
create or replace function public.is_kueche(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from aemtli_zuweisungen az
    join aemtli a on a.id = az.aemtli_id
    where az.lager_id = p_lager_id
      and az.profile_id = auth.uid()
      and a.name = 'Küche'
  )
  or exists (
    select 1
    from leiter_rollen lr
    join anmeldungen_leiter al on al.id = lr.anmeldung_leiter_id
    join aemtli a on a.id = lr.aemtli_id
    join profiles p on p.id = auth.uid()
    where al.lager_id = p_lager_id
      and lower(al.email) = lower(p.email)
      and a.name = 'Küche'
      and al.status = 'bestaetigt'
  )
  or public.is_lager_leitung(p_lager_id);
$$;

create or replace function public.darf_einkauf_item_bearbeiten(p_item_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from einkaufsliste_items e
    where e.id = p_item_id
      and public.can_access_lager(e.lager_id)
      and (e.erstellt_von = auth.uid() or public.is_kueche(e.lager_id))
  );
$$;

-- ---------------------------------------------------------------------
-- RLS Updates
-- ---------------------------------------------------------------------
drop policy if exists "anmeldungen_leiter: insert öffentlich bei offener Anmeldung" on anmeldungen_leiter;
drop policy if exists "anmeldungen_leiter: select/update für Lagerteam" on anmeldungen_leiter;

create policy "anmeldungen_leiter: insert eigene Anfrage" on anmeldungen_leiter
  for insert to authenticated
  with check (
    profile_id = auth.uid()
    and exists (select 1 from lager where id = lager_id and status = 'anmeldung_offen')
  );

create policy "anmeldungen_leiter: select eigene Anfrage" on anmeldungen_leiter
  for select to authenticated
  using (profile_id = auth.uid() or public.can_access_lager(lager_id));

create policy "anmeldungen_leiter: update für Lagerteam" on anmeldungen_leiter
  for update to authenticated
  using (public.can_access_lager(lager_id))
  with check (public.can_access_lager(lager_id));

drop policy if exists "einkaufsliste_items: für Lagerteam" on einkaufsliste_items;

create policy "einkaufsliste: select für Lagerteam" on einkaufsliste_items
  for select to authenticated
  using (public.can_access_lager(lager_id));

create policy "einkaufsliste: insert für Lagerteam" on einkaufsliste_items
  for insert to authenticated
  with check (public.can_access_lager(lager_id));

create policy "einkaufsliste: update für Ersteller oder Küche" on einkaufsliste_items
  for update to authenticated
  using (public.darf_einkauf_item_bearbeiten(id))
  with check (public.darf_einkauf_item_bearbeiten(id));

create policy "einkaufsliste: delete für Ersteller oder Küche" on einkaufsliste_items
  for delete to authenticated
  using (public.darf_einkauf_item_bearbeiten(id));

alter table einkaufs_termine enable row level security;
alter table hoeck_notizen enable row level security;

create policy "einkaufs_termine: für Lagerteam" on einkaufs_termine
  for all to authenticated
  using (public.can_access_lager(lager_id))
  with check (public.can_access_lager(lager_id));

grant execute on function public.is_kueche(uuid) to authenticated;
grant execute on function public.darf_einkauf_item_bearbeiten(uuid) to authenticated;
