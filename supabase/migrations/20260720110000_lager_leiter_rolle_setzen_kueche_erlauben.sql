-- lager_leiter.rolle erlaubt seit "kueche_als_team_rolle" auch 'kueche',
-- aber die RPC zum Ändern der Rolle prüfte weiterhin nur gegen
-- ('leiter','lagerleitung') und lehnte 'kueche' mit "Ungültige Rolle." ab.
create or replace function public.lager_leiter_rolle_setzen(
  p_lager_leiter_id uuid,
  p_rolle text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row lager_leiter%rowtype;
  v_lalei int;
begin
  if p_rolle not in ('leiter', 'lagerleitung', 'kueche') then
    raise exception 'Ungültige Rolle.';
  end if;

  select * into v_row from lager_leiter where id = p_lager_leiter_id;
  if not found then
    raise exception 'Team-Eintrag nicht gefunden.';
  end if;

  if not public.is_lager_leitung(v_row.lager_id) then
    raise exception 'Nur Lagerleitung darf Rollen ändern.';
  end if;

  v_lalei := public.lager_lalei_anzahl(v_row.lager_id);

  if v_row.rolle = 'lagerleitung' and p_rolle <> 'lagerleitung' and v_lalei <= 1 then
    raise exception 'Es muss mindestens eine Person die Rolle Lagerleitung (Lalei) behalten.';
  end if;

  update lager_leiter set rolle = p_rolle where id = p_lager_leiter_id;
end;
$$;
