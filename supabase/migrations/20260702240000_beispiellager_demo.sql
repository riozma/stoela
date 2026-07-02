-- Beispiellager für manuelzeltner@gmail.com (Demo-Daten zum Testen)
-- Läuft nur wenn das Profil existiert (mindestens einmal eingeloggt).

insert into aemtli (name, beschreibung) values
  ('Sport', 'Sportprogramm und Material'),
  ('Sanität', 'Gesundheit und Erste Hilfe'),
  ('Material', 'Lagermaterial und Ausstattung'),
  ('Programm', 'Programmplanung und Höck')
on conflict (name) do nothing;

do $$
declare
  v_user uuid;
  v_lager uuid;
  v_al_manuel uuid;
  v_al_anna uuid;
  v_al_bruno uuid;
  v_a_kueche uuid;
  v_a_fin uuid;
  v_a_sport uuid;
  v_a_sani uuid;
  v_a_material uuid;
  v_a_programm uuid;
  v_a_leitung uuid;
  v_g1 uuid;
  v_g2 uuid;
  v_tn1 uuid;
  v_tn2 uuid;
  v_tn3 uuid;
  v_iban uuid;
  v_q1 uuid;
  v_q2 uuid;
  v_block1 uuid;
begin
  select id into v_user from profiles where lower(email) = lower('manuelzeltner@gmail.com');
  if v_user is null then
    raise notice 'Beispiellager-Seed übersprungen: manuelzeltner@gmail.com nicht in profiles.';
    return;
  end if;

  update profiles set vorname = coalesce(vorname, 'Manuel'), nachname = coalesce(nachname, 'Zeltner')
  where id = v_user;

  delete from lager where name = 'Beispiellager Demo 2026' and created_by = v_user;

  select id into v_a_kueche from aemtli where name = 'Küche';
  select id into v_a_fin from aemtli where name = 'Finanzen';
  select id into v_a_sport from aemtli where name = 'Sport';
  select id into v_a_sani from aemtli where name = 'Sanität';
  select id into v_a_material from aemtli where name = 'Material';
  select id into v_a_programm from aemtli where name = 'Programm';
  select id into v_a_leitung from aemtli where name = 'Lagerleitung';

  insert into lager (name, jahr, ort, start_datum, end_datum, status, ort_lat, ort_lng, created_by)
  values (
    'Beispiellager Demo 2026', 2026,
    'Pfadiheim Seewen, 6204 Sempach',
    '2026-07-12', '2026-07-25', 'laufend',
    47.1158, 8.1856,
    v_user
  )
  returning id into v_lager;

  insert into lager_leiter (lager_id, profile_id, rolle, status)
  values (v_lager, v_user, 'lagerleitung', 'bestaetigt')
  on conflict (lager_id, profile_id) do update set rolle = 'lagerleitung', status = 'bestaetigt';

  -- Leiter: Manuel (bestätigt), Anna, Bruno + 2 offene Anfragen
  insert into anmeldungen_leiter (lager_id, profile_id, vorname, nachname, email, geschlecht, anwesend_von, anwesend_bis, status)
  values (v_lager, v_user, 'Manuel', 'Zeltner', 'manuelzeltner@gmail.com', 'm', '2026-07-12', '2026-07-25', 'bestaetigt')
  returning id into v_al_manuel;

  insert into anmeldungen_leiter (lager_id, vorname, nachname, email, geschlecht, anwesend_von, anwesend_bis, status)
  values (v_lager, 'Anna', 'Koch', 'anna.koch@example.com', 'w', '2026-07-12', '2026-07-25', 'bestaetigt')
  returning id into v_al_anna;

  insert into anmeldungen_leiter (lager_id, vorname, nachname, email, geschlecht, anwesend_von, anwesend_bis, status)
  values (v_lager, 'Bruno', 'Kassa', 'bruno.kassa@example.com', 'm', '2026-07-12', '2026-07-19', 'bestaetigt')
  returning id into v_al_bruno;

  insert into anmeldungen_leiter (lager_id, vorname, nachname, email, geschlecht, anwesend_von, anwesend_bis, status)
  values
    (v_lager, 'Lara', 'Leiter', 'lara.leiter@example.com', 'w', '2026-07-12', '2026-07-25', 'angefragt'),
    (v_lager, 'Tim', 'Anfrage', 'tim.anfrage@example.com', 'm', '2026-07-15', '2026-07-25', 'angefragt');

  insert into leiter_rollen (anmeldung_leiter_id, aemtli_id) values
    (v_al_manuel, v_a_kueche),
    (v_al_manuel, v_a_fin),
    (v_al_manuel, v_a_leitung),
    (v_al_anna, v_a_sport),
    (v_al_bruno, v_a_sani)
  on conflict do nothing;

  -- Ämtli-Zuweisungen mit To-dos
  insert into aemtli_zuweisungen (lager_id, aemtli_id, profile_id, checkliste, status) values
    (v_lager, v_a_kueche, v_user, '[
      {"id":"k1","text":"Einkaufstermin Woche 1 setzen","done":true},
      {"id":"k2","text":"Kochplan erste Woche prüfen","done":false},
      {"id":"k3","text":"Allergieliste TN durchgehen","done":false}
    ]'::jsonb, 'in_arbeit'),
    (v_lager, v_a_fin, v_user, '[
      {"id":"f1","text":"Quittungen von letzter Woche abarbeiten","done":false},
      {"id":"f2","text":"TN-Beiträge kontrollieren","done":true}
    ]'::jsonb, 'in_arbeit'),
    (v_lager, v_a_sport, null, '[
      {"id":"s1","text":"Seile und Karabiner zählen","done":false},
      {"id":"s2","text":"Sicherheitsbriefing vorbereiten","done":false}
    ]'::jsonb, 'offen'),
    (v_lager, v_a_sani, null, '[
      {"id":"sa1","text":"Erste-Hilfe-Koffer prüfen","done":true},
      {"id":"sa2","text":"Notfallnummern aushängen","done":false}
    ]'::jsonb, 'in_arbeit')
  on conflict (lager_id, aemtli_id) do update set checkliste = excluded.checkliste, status = excluded.status;

  -- Teilnehmer
  insert into anmeldungen_tn (lager_id, vorname, nachname, geburtsdatum, geschlecht, rolle, status, notfallkontakt, eltern_email)
  values (v_lager, 'Lea', 'Muster', '2014-03-15', 'w', 'TN', 'angemeldet', 'Mama 079 111 22 33', 'eltern.muster@example.com')
  returning id into v_tn1;

  insert into anmeldungen_tn (lager_id, vorname, nachname, geburtsdatum, geschlecht, rolle, status, notfallkontakt, eltern_email)
  values (v_lager, 'Noah', 'Beispiel', '2013-08-22', 'm', 'TN', 'angemeldet', 'Papa 079 444 55 66', 'papa@example.com')
  returning id into v_tn2;

  insert into anmeldungen_tn (lager_id, vorname, nachname, geburtsdatum, geschlecht, rolle, status, notfallkontakt, eltern_email)
  values (v_lager, 'Sara', 'Test', '2015-01-10', 'w', 'HL', 'angemeldet', 'Mama 079 777 88 99', 'sara.eltern@example.com')
  returning id into v_tn3;

  insert into tn_finanzen (anmeldung_tn_id, bezahlt, bemerkung, reduktion) values
    (v_tn1, true, null, null),
    (v_tn2, false, 'Zahlung per Post erwartet', null),
    (v_tn3, false, null, '50% Geschwisterrabatt')
  on conflict (anmeldung_tn_id) do nothing;

  -- Gruppen
  insert into lagergruppen (lager_id, name) values (v_lager, 'Gruppe Fuchs') returning id into v_g1;
  insert into lagergruppen (lager_id, name) values (v_lager, 'Gruppe Adler') returning id into v_g2;

  insert into gruppen_mitglieder (lagergruppe_id, anmeldung_tn_id) values
    (v_g1, v_tn1), (v_g2, v_tn2), (v_g2, v_tn3);

  insert into gruppen_mitglieder (lagergruppe_id, anmeldung_leiter_id) values
    (v_g1, v_al_manuel), (v_g2, v_al_anna);

  -- Programmblöcke
  insert into programmbloecke (
    lager_id, code, nummer, titel, tag, start_zeit, end_zeit, ort,
    verantwortlich, sicherheitsueberlegungen, programmabschnitt, material, notizen, quelle
  ) values (
    v_lager, 'LP', '1.1', 'Willkommen am Lager', '2026-07-12',
    '2026-07-12 14:00:00+02', '2026-07-12 16:00:00+02', 'Hauptplatz',
    'Manuel Zeltner, Anna Koch',
    'Wetter beachten, Sonnenschutz',
    '[{"zeit":"14:00","programm":"Ankommen und Zelte","verantwortlich":"Manuel Zeltner"},{"zeit":"15:00","programm":"Lagerregeln","verantwortlich":"Anna Koch"}]'::jsonb,
    '[{"name":"Willkommensbanner","wer":"Material"},{"name":"Wasserkanister","wer":"Küche"}]'::jsonb,
    'Höck morgen vorbereiten', 'manuell'
  ) returning id into v_block1;

  insert into programmbloecke (
    lager_id, code, nummer, titel, tag, start_zeit, end_zeit, ort,
    verantwortlich, programmabschnitt, material, quelle
  ) values (
    v_lager, 'LS', '2.1', 'Seilparcours', '2026-07-13',
    '2026-07-13 09:00:00+02', '2026-07-13 12:00:00+02', 'Wald',
    'Anna Koch',
    '[{"zeit":"09:00","programm":"Sicherheitseinweisung","verantwortlich":"Anna Koch"},{"zeit":"09:30","programm":"Parcours","verantwortlich":"Anna Koch"}]'::jsonb,
    '[{"name":"Helme","wer":"Sport"},{"name":"Seile","wer":"Sport"}]'::jsonb,
    'manuell'
  );

  insert into programmbloecke (
    lager_id, code, titel, tag, start_zeit, end_zeit, verantwortlich, quelle
  ) values (
    v_lager, 'ES', 'Znacht', '2026-07-12',
    '2026-07-12 18:30:00+02', '2026-07-12 19:30:00+02', 'Küche', 'manuell'
  );

  -- Höck
  insert into hoeck_notizen (lager_id, tag, notizen, autor_name, updated_by)
  values (v_lager, '2026-07-13', 'Morgen: Seilparcours – Helme nicht vergessen. Wetter gut.', 'Manuel Zeltner', v_user)
  on conflict (lager_id, tag) do update set notizen = excluded.notizen;

  -- Kochplan
  insert into mahlzeit_vorlagen (lager_id, name, mahlzeit, wochentag, beschreibung, material) values
    (v_lager, 'Rösti mit Salat', 'znacht', 0, 'Klassiker Sonntag', '[{"name":"Kartoffeln","menge":"3","einheit":"kg"},{"name":"Salat","menge":"2","einheit":"Stk"}]'::jsonb),
    (v_lager, 'Pasta Bolognese', 'zmittag', 1, 'Vegetarische Option möglich', '[{"name":"Pasta","menge":"2","einheit":"kg"},{"name":"Hack","menge":"1.5","einheit":"kg"}]'::jsonb);

  insert into mahlzeiten (lager_id, tag, mahlzeit, titel, beschreibung, material) values
    (v_lager, '2026-07-12', 'znacht', 'Grillabend', 'Erster Abend am Lager', '[{"name":"Würste","menge":"40","einheit":"Stk"},{"name":"Brot","menge":"3","einheit":"Laibe"}]'::jsonb);

  -- Einkauf
  insert into einkaufs_termine (lager_id, einkauf_am, frueh_geschlossen, erstellt_von) values
    (v_lager, '2026-07-14 10:00:00+02', false, v_user);

  insert into einkaufsliste_items (lager_id, name, menge, einheit, bereich, mahlzeit, notiz, erledigt, erstellt_von) values
    (v_lager, 'Milch', 10, 'l', 'lager', 'fruehstueck', null, false, v_user),
    (v_lager, 'Tomaten', 2, 'kg', 'lager', 'zmittag', 'Für Salat', true, v_user),
    (v_lager, 'Seile 20m', 4, 'Stk', 'programm', null, 'LP 1.1', false, v_user);

  -- Quittungen
  insert into profile_ibans (profile_id, iban, bezeichnung)
  select v_user, 'CH9300762011623852957', 'Privat'
  where not exists (
    select 1 from profile_ibans where profile_id = v_user and iban = 'CH9300762011623852957'
  );

  select id into v_iban from profile_ibans where profile_id = v_user limit 1;

  if v_iban is not null then
    insert into quittungen (lager_id, einreicher_id, iban_id, betrag, zweck, status) values
      (v_lager, v_user, v_iban, 45.80, 'Baumarkt – Seile und Karabiner', 'pending')
    returning id into v_q1;

    insert into quittungen (lager_id, einreicher_id, iban_id, betrag, zweck, status, bearbeitet_von, bearbeitet_am) values
      (v_lager, v_user, v_iban, 128.50, 'Coop – Vorräte Woche 1', 'bezahlt', v_user, now() - interval '2 days')
    returning id into v_q2;

    insert into quittungen (lager_id, einreicher_id, iban_id, betrag, zweck, status, ablehnungsgrund, bearbeitet_von, bearbeitet_am) values
      (v_lager, v_user, v_iban, 89.00, 'Diverse Snacks', 'abgelehnt', 'Kein Beleg im richtigen Format', v_user, now() - interval '1 day');
  end if;

  -- Reminder
  insert into reminders (lager_id, titel, nachricht, faellig_am, status) values
    (v_lager, 'Leiteranfragen prüfen', 'Lara und Tim warten auf Freischaltung.', now() + interval '1 day', 'geplant'),
    (v_lager, 'Einkauf Deadline', 'Letzte Einträge für Einkauf am Montag.', '2026-07-13 06:00:00+02', 'geplant');

  raise notice 'Beispiellager Demo 2026 erstellt für user % (lager_id=%)', v_user, v_lager;
end $$;
