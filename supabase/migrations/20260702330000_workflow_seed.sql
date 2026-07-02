-- Standard-Fahrplan und Ämtli-Meta für Stöckli Lager

do $$
declare
  v_org uuid;
begin
  select id into v_org from organisation where slug = 'stoeckli' limit 1;

  insert into org_todo_vorlagen (organisation_id, titel, beschreibung, ebene, monate_vor_lager, kategorie, zustaendig, aemtli_name, sortierung) values
  -- 9 Monate
  (v_org, 'Küchenteam suchen', 'Leiter/innen fürs Küche-Ämtli finden und ansprechen.', 'lager', 9, 'team', 'lalei', null, 10),
  (v_org, 'Leitungsteam erfassen', 'Alle Leiter/innen sollen sich anmelden (provisorisch möglich). Spätestens 3 Monate vor Lager bestätigen.', 'lager', 9, 'team', 'lalei', null, 11),
  -- 9 Monate Lagerleitung
  (v_org, 'Lagerhaus bestätigen & Vertrag', 'Lagerhaus für das Jahr reservieren und Vertrag fixieren.', 'lager', 9, 'logistik', 'lalei', null, 20),
  -- 7 Monate
  (v_org, 'Anreise planen / Car reservieren', 'Bei Anreise mit Car: Fahrzeug reservieren. An- und Abreise im Programm als Sonderblöcke erfassen.', 'lager', 7, 'logistik', 'lalei', null, 30),
  (v_org, 'Vorweekend planen', 'Datum und Ort festlegen, Programm im Vorweekend-Bereich anlegen.', 'lager', 7, 'vorweekend', 'lalei', null, 31),
  (v_org, 'Finanzen-Ämtli klären', 'Wird meist vom Vorjahr übernommen. Budget-Vorbereitung starten (Google Drive / Excel).', 'lager', 7, 'finanzen', 'aemtli', 'Finanzen', 32),
  -- 6 Monate
  (v_org, 'Ämtli an Leiter verteilen', 'Rollen zuweisen – Küche, Finanzen, Werbung, Motto, Material, etc.', 'lager', 6, 'team', 'lalei', null, 40),
  (v_org, 'TN-Anmeldung live schalten', 'Lager-Status auf «Anmeldung offen» setzen.', 'lager', 6, 'werbung', 'lalei', null, 41),
  (v_org, 'Werbung starten', 'Flyer, Schulbesuche, Social Media – siehe Ämtli Werbung.', 'lager', 6, 'werbung', 'aemtli', 'Werbung', 42),
  -- 5 Monate
  (v_org, 'Motto & Zweiwochenraster', 'In eCamp erstellen – spätestens zum Vorweekend fertig.', 'lager', 5, 'programm', 'aemtli', 'Motto', 50),
  (v_org, 'Jugendurlaub Info & Ausstellung', 'Leiter/innen informieren und Jugendurlaub ausstellen – spätestens Vorweekend.', 'lager', 5, 'team', 'lalei', null, 51),
  -- 4.5–5 Vorweekend (deadline dynamisch über vorweekend_start)
  (v_org, 'Vorweekend durchführen', 'Motto vorstellen, Teambuilding, Tagesteams, Feinprogramm in eCamp.', 'lager', 4.5, 'vorweekend', 'alle', null, 60),
  -- 4 Monate
  (v_org, 'Feinprogramm an Coach', 'Feinprogramm von jedem Leiter weiterleiten.', 'lager', 4, 'programm', 'lalei', null, 70),
  (v_org, 'TJ & S Bestellung', 'Lagerleitung mit Material-Chef: Bestellung TJ/S.', 'lager', 4, 'logistik', 'aemtli', 'Material', 71),
  -- 3 Monate
  (v_org, 'Leiter-Bestätigung fällig', 'Alle provisorischen Anmeldungen müssen bestätigt sein (An-/Abreisedaten).', 'lager', 3, 'team', 'lalei', null, 80),
  (v_org, 'Küche: Abklärung & Küchenauto', 'Mit Küche abklären ob alles passt, Küchenauto nötig?', 'lager', 3, 'logistik', 'kueche', null, 81),
  (v_org, 'Sponsoring-Anfragen', 'Ämtli Sponsoring: Sponsoren kontaktieren.', 'lager', 3, 'finanzen', 'aemtli', 'Sponsoring', 82),
  (v_org, 'Plakate aufhängen', 'Werbung: Plakate verteilen und aufhängen.', 'lager', 3, 'werbung', 'aemtli', 'Werbung', 83),
  (v_org, 'Kuchenstände organisieren', 'Ämtli Kuchenstand: Standorte und Einteilung.', 'lager', 3, 'werbung', 'aemtli', 'Kuchenstand', 84),
  -- 1 Monat
  (v_org, 'Gruppenzuteilung', 'Wenn Anmeldungen weitgehend da: Gruppen bilden.', 'lager', 1, 'team', 'lalei', null, 90),
  (v_org, 'Elterninfo erstellen & verschicken', 'Elternbrief mit Terminen, Packliste, Beitrag – in App generieren.', 'lager', 1, 'eltern', 'lalei', null, 91),
  -- 0.5 Monat
  (v_org, 'Lagerhaus Folgejahr fixieren', 'Optional: Lagerhaus für nächstes Jahr reservieren.', 'lager', 0.5, 'logistik', 'lalei', null, 100),
  (v_org, 'Physisches Lagerprogramm', 'Optional: Programm drucken/verschicken, Link aus Vorjahr importieren.', 'lager', 0.5, 'programm', 'lalei', null, 101),
  -- Während Lager
  (v_org, 'Programm von eCamp übertragen', 'Feinprogramm aus eCamp in diese App importieren.', 'lager', 0, 'programm', 'lalei', null, 110),
  (v_org, 'Höck täglich pflegen', 'Tägliche Höck-Notizen im Programm.', 'lager', 0, 'lager', 'alle', null, 111),
  -- Nach Lager
  (v_org, 'Diashow vorbereiten', 'Material und Ablauf Diashow.', 'lager', -0.5, 'nachlager', 'lalei', null, 120),
  (v_org, 'Rechnungen Lagerhaus & Anreise', 'Kassier: offene Rechnungen begleichen.', 'lager', -0.5, 'nachlager', 'aemtli', 'Finanzen', 121),
  (v_org, 'Kurse & Kursbedarf', 'Anmeldungen für Leiterkurse klären.', 'lager', -1, 'nachlager', 'lalei', null, 122),
  (v_org, 'Leiter für nächstes Jahr abfragen', 'Grobe Rückmeldung wer wieder kommt.', 'lager', -1, 'nachlager', 'lalei', null, 123),
  (v_org, 'Feedback-Höck & Learnings', 'Feedback besprechen, Learnings in Ämtli-Bereichen festhalten.', 'lager', -1, 'nachlager', 'alle', null, 124),
  -- Verein
  (v_org, 'Mitgliederversammlung (MV)', 'Jährliche MV vorbereiten und durchführen.', 'verein', null, 'verein', 'lalei', null, 200);

  -- Ämtli anlegen falls fehlen
  insert into aemtli (name, beschreibung) values
    ('Werbung', 'Flyer, Social Media, Schulbesuche'),
    ('Motto', 'Motto und Zweiwochenraster in eCamp'),
    ('Sponsoring', 'Sponsoren anfragen'),
    ('Kuchenstand', 'Kuchenstände organisieren'),
    ('Material', 'Materialbestellung TJ/S')
  on conflict (name) do nothing;

  insert into org_aemtli_meta (organisation_id, aemtli_id, seiten_typ, beschreibung, hinweise_md, extra_felder)
  select v_org, a.id, x.seiten_typ, x.beschreibung, x.hinweise_md, x.extra_felder::jsonb
  from (values
    ('Finanzen', 'finanzen', 'Budget, Quittungen, TN-Beiträge', E'Budget fürs nächste Jahr und Lager auf **Google Drive** und in **Excel** pflegen.\n\nQuittungen und Kassenführung über das Finanzen-Dashboard.', '{}'),
    ('Werbung', 'werbung', 'Flyer, Social Media, Schulbesuche', E'Aufgaben:\n- Erinnerung an Eltern von letztem Jahr\n- Schulbesuche organisieren\n- Flyer erstellen und bestellen\n\n**Social-Media-Logins** und Contentplan hier notieren.', '{"felder":["social_media","content_plan","flyer_link"]}'),
    ('Motto', 'motto', 'Motto & Zweiwochenraster', E'Motto und Zweiwochenraster werden in **eCamp** erstellt – nicht in dieser App.\n\nDeadline: spätestens zum Vorweekend (ca. 5 Monate vor Lager).', '{}'),
    ('Sponsoring', 'sponsoring', 'Sponsoring-Anfragen', 'Ab ca. 3–4 Monate vor Lager Sponsoren kontaktieren.', '{}'),
    ('Kuchenstand', 'kuchenstand', 'Kuchenstände', 'Standorte und Einteilung der Kuchenstände ca. 3 Monate vor Lager.', '{}'),
    ('Material', 'material', 'Material & Bestellungen', 'TJ- und S-Bestellung ca. 4 Monate vor Lager mit Lagerleitung.', '{}')
  ) as x(name, seiten_typ, beschreibung, hinweise_md, extra_felder)
  join aemtli a on a.name = x.name
  on conflict (organisation_id, aemtli_id) do update set
    seiten_typ = excluded.seiten_typ,
    beschreibung = excluded.beschreibung,
    hinweise_md = excluded.hinweise_md,
    extra_felder = excluded.extra_felder;

  insert into org_elterninfo_vorlage (organisation_id, felder, packliste)
  values (v_org,
    '{
      "lagerbeitrag_tn": 340,
      "lagerbeitrag_geschwister": 280,
      "kulturlegi_link": "https://www.jubla.ch/ueber-die-jubla/unterstuetzende/stiftung/kulturlegi",
      "kassier_name": "Manuel Zeltner",
      "kassier_email": "manuelzeltner@gmail.com",
      "kassier_telefon": "076 523 13 08",
      "pfarrei_iban": "CH41 8080 8003 9389 3171 6",
      "pfarrei_name": "Röm. Kath. Pfarrei St. Martin Zuchwil",
      "homepage": "https://www.stoecklilager.ch",
      "besuche_hinweis": "Kein Besuchstag – Erfahrung zeigt negative Wirkung bei heimweh-anfälligen Kindern.",
      "dessertaktien_hinweis": "Dessertaktien am Elternabend – Küche verwöhnt das Lager."
    }'::jsonb,
    '["Schlafsack","Isoliermatte (JG 2009+)","Wanderschuhe","Regenschutz","Rucksack","Hausschuhe","Turnschuhe","Badezeug","Feldflasche mit Name","Taschenlampe","Sonnenhut","Camping-Geschirr"]'::jsonb
  )
  on conflict (organisation_id) do nothing;
end $$;
