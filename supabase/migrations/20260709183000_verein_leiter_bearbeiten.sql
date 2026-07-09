-- Vereinsleitung darf Login-Leiter (Name + Vereinsrolle) bearbeiten, inkl. Admin-Konten.

create or replace function public.is_org_admin(p_organisation_id uuid)
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
      and om.rolle = 'admin'
  );
$$;

create or replace function public.verein_leiter_bearbeiten(
  p_organisation_id uuid,
  p_profile_id uuid,
  p_vorname text,
  p_nachname text,
  p_rolle text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vorname text := nullif(trim(p_vorname), '');
  v_nachname text := nullif(trim(p_nachname), '');
  v_rolle text := nullif(trim(p_rolle), '');
begin
  if not public.is_org_admin(p_organisation_id) then
    raise exception 'Nur Vereins-Admins dürfen Leiter bearbeiten.';
  end if;

  if v_vorname is null or v_nachname is null then
    raise exception 'Vorname und Nachname sind Pflicht.';
  end if;

  if v_rolle is null or v_rolle not in ('mitglied', 'leitung', 'admin') then
    raise exception 'Ungültige Rolle.';
  end if;

  if not exists (
    select 1
    from organisation_mitglieder om
    where om.organisation_id = p_organisation_id
      and om.profile_id = p_profile_id
      and om.status = 'mitglied'
  ) then
    raise exception 'Leiter ist kein aktives Vereinsmitglied.';
  end if;

  update profiles
  set vorname = v_vorname,
      nachname = v_nachname
  where id = p_profile_id;

  update organisation_mitglieder
  set rolle = v_rolle
  where organisation_id = p_organisation_id
    and profile_id = p_profile_id;

  update org_personen
  set vorname = v_vorname,
      nachname = v_nachname,
      rolle_hinweis = initcap(v_rolle)
  where organisation_id = p_organisation_id
    and profile_id = p_profile_id
    and aktiv = true;
end;
$$;

grant execute on function public.verein_leiter_bearbeiten(uuid, uuid, text, text, text) to authenticated;

create or replace function public.verein_leiter_entfernen(
  p_organisation_id uuid,
  p_profile_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_count integer;
begin
  if not public.is_org_admin(p_organisation_id) then
    raise exception 'Nur Vereins-Admins dürfen Leiter entfernen.';
  end if;

  if not exists (
    select 1
    from organisation_mitglieder om
    where om.organisation_id = p_organisation_id
      and om.profile_id = p_profile_id
      and om.status = 'mitglied'
  ) then
    raise exception 'Leiter ist kein aktives Vereinsmitglied.';
  end if;

  if exists (
    select 1
    from organisation_mitglieder om
    where om.organisation_id = p_organisation_id
      and om.profile_id = p_profile_id
      and om.rolle = 'admin'
  ) then
    select count(*) into v_admin_count
    from organisation_mitglieder om
    where om.organisation_id = p_organisation_id
      and om.status = 'mitglied'
      and om.rolle = 'admin';

    if v_admin_count <= 1 then
      raise exception 'Der letzte Vereins-Admin kann nicht entfernt werden.';
    end if;
  end if;

  delete from organisation_mitglieder
  where organisation_id = p_organisation_id
    and profile_id = p_profile_id;

  update org_personen
  set aktiv = false,
      profile_id = null
  where organisation_id = p_organisation_id
    and profile_id = p_profile_id;
end;
$$;

grant execute on function public.verein_leiter_entfernen(uuid, uuid) to authenticated;
