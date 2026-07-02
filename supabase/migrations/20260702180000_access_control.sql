-- Verschärfte Zugriffskontrolle: nur Ersteller/in oder freigeschaltete Teammitglieder
-- sehen ein Lager. Öffentliche TN-Seite nur über RPC mit Basisdaten.

alter table lager add column if not exists created_by uuid references profiles (id);

-- Bestehende Lager: Ersteller/in aus erster Lagerleitung ableiten
update lager l
set created_by = ll.profile_id
from lager_leiter ll
where l.id = ll.lager_id
  and ll.rolle = 'lagerleitung'
  and ll.status = 'bestaetigt'
  and l.created_by is null;

-- ---------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------

create or replace function public.can_access_lager(p_lager_id uuid)
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
        l.created_by = auth.uid()
        or exists (
          select 1 from lager_leiter ll
          where ll.lager_id = p_lager_id
            and ll.profile_id = auth.uid()
            and ll.status = 'bestaetigt'
        )
      )
  );
$$;

create or replace function public.is_lager_leitung(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from lager_leiter ll
    where ll.lager_id = p_lager_id
      and ll.profile_id = auth.uid()
      and ll.status = 'bestaetigt'
      and ll.rolle = 'lagerleitung'
  )
  or exists (
    select 1 from lager l
    where l.id = p_lager_id and l.created_by = auth.uid()
  );
$$;

create or replace function public.is_lager_team(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.can_access_lager(p_lager_id);
$$;

create or replace function public.shares_lager_with(p_profile_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from lager_leiter ll1
    join lager_leiter ll2 on ll1.lager_id = ll2.lager_id
    where ll1.profile_id = auth.uid()
      and ll1.status = 'bestaetigt'
      and ll2.profile_id = p_profile_id
      and ll2.status = 'bestaetigt'
  );
$$;

-- Öffentliche Willkommensseite für TN (kein Programm!)
create or replace function public.get_lager_willkommen(p_lager_id uuid)
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
    'ort_lat', l.ort_lat,
    'ort_lng', l.ort_lng,
    'status', l.status
  )
  from lager l
  where l.id = p_lager_id
    and l.status <> 'archiviert';
$$;

grant execute on function public.get_lager_willkommen(uuid) to anon, authenticated;

-- Teammitglied per E-Mail freischalten (nur Lagerleitung)
create or replace function public.freischalten_teammitglied(
  p_lager_id uuid,
  p_email text,
  p_rolle text default 'leiter'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_leiter_id uuid;
begin
  if not public.is_lager_leitung(p_lager_id) then
    raise exception 'Nur die Lagerleitung darf Teammitglieder freischalten.';
  end if;

  select id into v_profile_id from profiles where lower(email) = lower(trim(p_email));
  if v_profile_id is null then
    raise exception 'Kein Profil mit dieser E-Mail gefunden. Die Person muss sich zuerst einloggen.';
  end if;

  insert into lager_leiter (lager_id, profile_id, rolle, status)
  values (p_lager_id, v_profile_id, p_rolle, 'bestaetigt')
  on conflict (lager_id, profile_id) do update
    set rolle = excluded.rolle, status = 'bestaetigt'
  returning id into v_leiter_id;

  return v_leiter_id;
end;
$$;

grant execute on function public.freischalten_teammitglied(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- RLS Policies ersetzen
-- ---------------------------------------------------------------------

-- lager
drop policy if exists "lager: select für eingeloggte" on lager;
drop policy if exists "lager: insert/update für eingeloggte" on lager;
drop policy if exists "lager: select öffentlich bei offener Anmeldung" on lager;

create policy "lager: select für berechtigte" on lager
  for select to authenticated
  using (public.can_access_lager(id));

create policy "lager: insert für eingeloggte" on lager
  for insert to authenticated
  with check (created_by = auth.uid());

create policy "lager: update für Lagerteam" on lager
  for update to authenticated
  using (public.can_access_lager(id))
  with check (public.can_access_lager(id));

create policy "lager: delete für Lagerleitung" on lager
  for delete to authenticated
  using (public.is_lager_leitung(id));

-- Anmeldung: minimale Metadaten ohne Login (nur bei offener Anmeldung)
create policy "lager: select anmeldung basis" on lager
  for select to anon, authenticated
  using (status = 'anmeldung_offen');

-- profiles
drop policy if exists "profiles: select für eingeloggte" on profiles;
drop policy if exists "profiles: update eigene Zeile" on profiles;

create policy "profiles: select eigenes oder Lagerteam" on profiles
  for select to authenticated
  using (
    auth.uid() = id
    or public.shares_lager_with(id)
    or exists (
      select 1 from lager_leiter ll
      where ll.profile_id = auth.uid()
        and ll.rolle = 'lagerleitung'
        and ll.status = 'bestaetigt'
    )
  );

create policy "profiles: update eigene Zeile" on profiles
  for update to authenticated
  using (auth.uid() = id);

-- lager_leiter
drop policy if exists "lager_leiter: select für eingeloggte" on lager_leiter;
drop policy if exists "lager_leiter: insert für eingeloggte" on lager_leiter;
drop policy if exists "lager_leiter: update eigene Zeile" on lager_leiter;

create policy "lager_leiter: select für berechtigte" on lager_leiter
  for select to authenticated
  using (public.can_access_lager(lager_id) or profile_id = auth.uid());

create policy "lager_leiter: insert für Lagerleitung" on lager_leiter
  for insert to authenticated
  with check (
    public.is_lager_leitung(lager_id)
    or exists (
      select 1 from lager l
      where l.id = lager_id and l.created_by = auth.uid()
    )
  );

create policy "lager_leiter: update für Lagerleitung oder eigene Zeile" on lager_leiter
  for update to authenticated
  using (public.is_lager_leitung(lager_id) or profile_id = auth.uid());

create policy "lager_leiter: delete für Lagerleitung" on lager_leiter
  for delete to authenticated
  using (public.is_lager_leitung(lager_id));

-- aemtli: nur für berechtigte Lagerteams (nicht global mehr)
drop policy if exists "aemtli: select für eingeloggte" on aemtli;
drop policy if exists "aemtli: insert/update für eingeloggte" on aemtli;

create policy "aemtli: select für Lagerteam" on aemtli
  for select to authenticated
  using (
    exists (
      select 1 from lager_leiter ll
      where ll.profile_id = auth.uid() and ll.status = 'bestaetigt'
    )
  );

create policy "aemtli: insert/update für Lagerteam" on aemtli
  for all to authenticated
  using (
    exists (
      select 1 from lager_leiter ll
      where ll.profile_id = auth.uid() and ll.status = 'bestaetigt'
    )
  )
  with check (
    exists (
      select 1 from lager_leiter ll
      where ll.profile_id = auth.uid() and ll.status = 'bestaetigt'
    )
  );

-- aemtli_learnings: nur für berechtigte
drop policy if exists "aemtli_learnings: select für eingeloggte" on aemtli_learnings;
drop policy if exists "aemtli_learnings: insert für Lagerteam" on aemtli_learnings;

create policy "aemtli_learnings: select für Lagerteam" on aemtli_learnings
  for select to authenticated
  using (public.can_access_lager(lager_id));

create policy "aemtli_learnings: insert für Lagerteam" on aemtli_learnings
  for insert to authenticated
  with check (public.can_access_lager(lager_id));

create policy "aemtli_learnings: update/delete für Lagerteam" on aemtli_learnings
  for all to authenticated
  using (public.can_access_lager(lager_id))
  with check (public.can_access_lager(lager_id));
