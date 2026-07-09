-- Bereinigt Stöcklilager Zuchwil: alle Leiter/TN im laufenden Lager und in der Organisation,
-- ausser manuelzeltner@gmail.com behält vollen Zugriff.

do $$
declare
  v_org uuid;
  v_lager uuid;
  v_manuel uuid;
begin
  select id into v_manuel
  from profiles
  where lower(email) = lower('manuelzeltner@gmail.com')
  limit 1;

  if v_manuel is null then
    raise exception 'Profil manuelzeltner@gmail.com nicht gefunden';
  end if;

  select id into v_org
  from organisation
  where lower(slug) = 'stoeckli'
     or lower(name) like '%stöcklilager%'
     or lower(name) like '%stoecklilager%'
  order by created_at desc
  limit 1;

  if v_org is null then
    raise exception 'Organisation Stöcklilager nicht gefunden';
  end if;

  select id into v_lager
  from lager
  where organisation_id = v_org
    and status in ('laufend', 'anmeldung_offen')
  order by start_datum desc nulls last
  limit 1;

  if v_lager is null then
    select id into v_lager
    from lager
    where organisation_id = v_org
    order by jahr desc, created_at desc
    limit 1;
  end if;

  if v_lager is null then
    raise exception 'Kein Lager für Organisation gefunden';
  end if;

  -- Teilnehmer im Lager
  delete from tn_finanzen
  where anmeldung_tn_id in (select id from anmeldungen_tn where lager_id = v_lager);

  delete from gruppen_mitglieder
  where lagergruppe_id in (select id from lagergruppen where lager_id = v_lager);

  delete from lagergruppen where lager_id = v_lager;
  delete from anmeldungen_tn where lager_id = v_lager;

  -- Leiter im Lager (Manuel behalten)
  delete from leiter_rollen
  where anmeldung_leiter_id in (
    select id from anmeldungen_leiter
    where lager_id = v_lager
      and (profile_id is distinct from v_manuel)
  );

  delete from gruppen_mitglieder
  where anmeldung_leiter_id in (
    select id from anmeldungen_leiter
    where lager_id = v_lager
      and (profile_id is distinct from v_manuel)
  );

  delete from anmeldungen_leiter
  where lager_id = v_lager
    and (profile_id is distinct from v_manuel);

  delete from lager_leiter
  where lager_id = v_lager
    and profile_id is distinct from v_manuel;

  -- Organisation: alle manuellen Personen entfernen
  update org_personen set aktiv = false where organisation_id = v_org;

  -- Organisation: alle Mitglieder ausser Manuel entfernen
  delete from organisation_mitglieder
  where organisation_id = v_org
    and profile_id is distinct from v_manuel;

  -- Manuel als Admin sicherstellen
  insert into organisation_mitglieder (
    organisation_id, profile_id, rolle, status, angefragt_am, bestaetigt_am
  ) values (
    v_org, v_manuel, 'admin', 'mitglied', now(), now()
  )
  on conflict (organisation_id, profile_id) do update
    set rolle = 'admin',
        status = 'mitglied',
        bestaetigt_am = coalesce(organisation_mitglieder.bestaetigt_am, now());

  -- Manuel als Lagerleitung im laufenden Lager sicherstellen
  insert into lager_leiter (lager_id, profile_id, rolle, status)
  values (v_lager, v_manuel, 'lagerleitung', 'bestaetigt')
  on conflict (lager_id, profile_id) do update
    set rolle = 'lagerleitung',
        status = 'bestaetigt';

  if not exists (
    select 1 from anmeldungen_leiter
    where lager_id = v_lager and profile_id = v_manuel
  ) then
    insert into anmeldungen_leiter (
      lager_id, profile_id, vorname, nachname, email, status, anmeldung_art
    )
    select
      v_lager,
      v_manuel,
      coalesce(p.vorname, 'Manuel'),
      coalesce(p.nachname, 'Zeltner'),
      p.email,
      'bestaetigt',
      'fix'
    from profiles p
    where p.id = v_manuel;
  end if;

  raise notice 'Bereinigt: org=%, lager=%, manuel=%', v_org, v_lager, v_manuel;
end $$;
