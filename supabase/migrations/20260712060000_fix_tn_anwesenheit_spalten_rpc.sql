-- Bug: Frontend fragte bei der TN-Liste bereits die Spalten anwesend_von/
-- anwesend_bis ab (und rief eine RPC tn_anwesenheit_speichern auf), aber
-- weder die Spalten noch die RPC existierten in der DB. Der select-Query
-- schlug dadurch STILLE fehl (Fehler wurde im Frontend nicht ausgewertet),
-- wodurch angemeldete TN nie in der Liste erschienen, obwohl sie in der
-- DB vorhanden waren. Fix: Spalten ergänzen + RPC nachbauen.
alter table anmeldungen_tn add column if not exists anwesend_von date;
alter table anmeldungen_tn add column if not exists anwesend_bis date;

create or replace function public.tn_anwesenheit_speichern(p_tn_id uuid, p_anwesend_von date, p_anwesend_bis date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager_id uuid;
begin
  select lager_id into v_lager_id from anmeldungen_tn where id = p_tn_id;
  if v_lager_id is null or not public.is_lager_team(v_lager_id) then
    raise exception 'Kein Zugriff auf diese Anmeldung.';
  end if;
  update anmeldungen_tn set anwesend_von = p_anwesend_von, anwesend_bis = p_anwesend_bis where id = p_tn_id;
end;
$$;

grant execute on function public.tn_anwesenheit_speichern(uuid, date, date) to authenticated;
