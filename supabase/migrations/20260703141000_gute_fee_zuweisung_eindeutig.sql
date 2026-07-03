create or replace function public.gute_fee_zuweisen(p_lager_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_orte text[];
  v_gegenstaende text[];
  v_spieler uuid[];
  v_spieler_anzahl int;
  v_offset int;
  v_i int;
  v_ziel_index int;
begin
  if not public.can_access_lager(p_lager_id) then
    raise exception 'Kein Zugriff.';
  end if;

  select array_agg(x.wert)
    into v_orte
  from (
    select wert
    from gute_fee_liste
    where lager_id = p_lager_id
      and typ = 'ort'
      and nullif(trim(wert), '') is not null
    order by random()
  ) as x;

  select array_agg(x.wert)
    into v_gegenstaende
  from (
    select wert
    from gute_fee_liste
    where lager_id = p_lager_id
      and typ = 'gegenstand'
      and nullif(trim(wert), '') is not null
    order by random()
  ) as x;

  select array_agg(anmeldung_leiter_id order by random())
    into v_spieler
  from gute_fee_spieler
  where lager_id = p_lager_id
    and status = 'lebend';

  v_spieler_anzahl := coalesce(array_length(v_spieler, 1), 0);

  if v_spieler_anzahl < 2 then
    raise exception 'Mindestens 2 lebende Spieler nötig.';
  end if;

  if coalesce(array_length(v_orte, 1), 0) < v_spieler_anzahl then
    raise exception 'Mindestens % Orte nötig (aktuell %).', v_spieler_anzahl, coalesce(array_length(v_orte, 1), 0);
  end if;

  if coalesce(array_length(v_gegenstaende, 1), 0) < v_spieler_anzahl then
    raise exception 'Mindestens % Gegenstände nötig (aktuell %).', v_spieler_anzahl, coalesce(array_length(v_gegenstaende, 1), 0);
  end if;

  -- Ein zufälliger Ring stellt sicher: keine Selbstzuweisung, jede Zielperson genau 1x.
  v_offset := 1 + floor(random() * (v_spieler_anzahl - 1))::int;

  for v_i in 1..v_spieler_anzahl loop
    v_ziel_index := ((v_i + v_offset - 1) % v_spieler_anzahl) + 1;

    update gute_fee_spieler
    set
      ziel_ort = v_orte[v_i],
      ziel_gegenstand = v_gegenstaende[v_i],
      ziel_leiter_id = v_spieler[v_ziel_index]
    where lager_id = p_lager_id
      and anmeldung_leiter_id = v_spieler[v_i];
  end loop;

  update gute_fee_spiel
  set aktiv = true, updated_at = now()
  where lager_id = p_lager_id;

  return v_spieler_anzahl;
end;
$$;

grant execute on function public.gute_fee_zuweisen(uuid) to authenticated;
