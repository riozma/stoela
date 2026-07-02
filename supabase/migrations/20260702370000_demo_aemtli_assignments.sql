-- Demo: Mehr Ämtli-Zuweisungen für manuelzeltner@gmail.com
-- Damit der Demo-User alle neuen Ämtli-Tabs sehen kann

do $$
declare
  v_user uuid;
  v_lager uuid;
  v_al_manuel uuid;
  v_a_kiosk uuid;
  v_a_gute_fee uuid;
  v_a_skiweekend uuid;
  v_a_gelaende uuid;
  v_a_bastel uuid;
  v_a_sponsoring uuid;
  v_a_foto uuid;
  v_a_kuchenstand uuid;
begin
  select id into v_user from profiles where lower(email) = lower('manuelzeltner@gmail.com');
  if v_user is null then
    raise notice 'Demo-Ämtli-Seed übersprungen: manuelzeltner@gmail.com nicht in profiles.';
    return;
  end if;

  -- Neuestes Beispiellager des Demo-Users
  select id into v_lager
  from lager
  where created_by = v_user and name = 'Beispiellager Demo 2026'
  limit 1;

  if v_lager is null then
    raise notice 'Demo-Lager nicht gefunden – Seed übersprungen.';
    return;
  end if;

  select id into v_al_manuel
  from anmeldungen_leiter
  where lager_id = v_lager and lower(email) = lower('manuelzeltner@gmail.com')
  limit 1;

  if v_al_manuel is null then
    raise notice 'Demo-Leiteranmeldung nicht gefunden – Seed übersprungen.';
    return;
  end if;

  select id into v_a_kiosk       from aemtli where name = 'Kiosk'                 limit 1;
  select id into v_a_gute_fee    from aemtli where name = 'Gute Fee'               limit 1;
  select id into v_a_skiweekend  from aemtli where name = 'Skiweekend'             limit 1;
  select id into v_a_gelaende    from aemtli where name = 'Geländespielwiese'      limit 1;
  select id into v_a_bastel      from aemtli where name = 'Büro Bastelmat'         limit 1;
  select id into v_a_sponsoring  from aemtli where name = 'Sponsoring'             limit 1;
  select id into v_a_foto        from aemtli where name = 'Foto Diashow'           limit 1;
  select id into v_a_kuchenstand from aemtli where name = 'Kuchenstand'            limit 1;

  -- Leiter-Rollen zuweisen (damit die Tabs im Nav erscheinen)
  insert into leiter_rollen (anmeldung_leiter_id, aemtli_id)
  select v_al_manuel, a
  from (values
    (v_a_kiosk), (v_a_gute_fee), (v_a_skiweekend), (v_a_gelaende),
    (v_a_bastel), (v_a_sponsoring), (v_a_foto), (v_a_kuchenstand)
  ) as t(a)
  where a is not null
  on conflict do nothing;

  raise notice 'Demo-Ämtli-Zuweisungen für % (lager=%)', v_user, v_lager;
end $$;
