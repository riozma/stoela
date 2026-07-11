-- Profil-Entfernung soll nur noch im Verein möglich sein, nicht mehr pro Lager.
-- verein_leiter_entfernen entfernte bisher nur die Vereins-Mitgliedschaft,
-- liess aber App-Zugriff (lager_leiter) auf einzelne Lager des Vereins stehen.
-- Jetzt: cascade -> Person verliert beim Entfernen aus dem Verein auch den
-- App-Zugriff auf alle Lager dieses Vereins.

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

  -- App-Zugriff auf alle Lager dieses Vereins mitentfernen
  delete from lager_leiter
  where profile_id = p_profile_id
    and lager_id in (select id from lager where organisation_id = p_organisation_id);
end;
$$;

grant execute on function public.verein_leiter_entfernen(uuid, uuid) to authenticated;
