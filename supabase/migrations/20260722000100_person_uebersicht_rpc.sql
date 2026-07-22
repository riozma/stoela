-- Zentrale Detail-Ansicht für eine Person: aktuelle Lager-Zuteilungen + Ämtli,
-- live aus personen_lager_rollen / leiter_rollen / aemtli_zuweisungen zusammengeführt
-- (nicht separat gepflegt). Sichtbar für Vereinsleitung/Admin sowie die Person selbst --
-- personen_lager_rollen ist sonst pro Lager RLS-beschränkt (can_access_lager), das würde
-- der Vereinsleitung sonst Zuteilungen in Lagern verstecken, in denen sie nicht selbst
-- im Team ist.
create or replace function public.person_uebersicht(p_person_id uuid)
returns json
language plpgsql
stable security definer
set search_path to 'public'
as $$
declare
  v_org_id uuid;
  v_result json;
begin
  select organisation_id into v_org_id from personen where id = p_person_id;
  if v_org_id is null then
    raise exception 'Person nicht gefunden.';
  end if;

  if not (
    public.is_org_leitung(v_org_id)
    or exists (select 1 from personen where id = p_person_id and profile_id = auth.uid())
  ) then
    raise exception 'Keine Berechtigung.';
  end if;

  select json_build_object(
    'lager_rollen', coalesce((
      select json_agg(json_build_object(
        'lager_id', l.id, 'lager_name', l.name, 'jahr', l.jahr, 'rolle', plr.rolle, 'status', plr.status
      ) order by l.jahr desc)
      from personen_lager_rollen plr
      join lager l on l.id = plr.lager_id
      where plr.person_id = p_person_id
    ), '[]'::json),
    'aemtli', coalesce((
      select json_agg(json_build_object(
        'lager_id', l.id, 'lager_name', l.name, 'jahr', l.jahr, 'aemtli_name', a.name
      ) order by l.jahr desc, a.name)
      from leiter_rollen lr
      join anmeldungen_leiter al on al.id = lr.anmeldung_leiter_id
      join aemtli a on a.id = lr.aemtli_id
      join lager l on l.id = al.lager_id
      where al.person_id = p_person_id
    ), '[]'::json)
  ) into v_result;

  return v_result;
end;
$$;

grant execute on function public.person_uebersicht(uuid) to authenticated;
