-- Alle Ämtli anlegen + Meta-Hinweise

do $$
declare
  v_org uuid;
begin
  select id into v_org from organisation where slug = 'stoeckli' limit 1;

  insert into aemtli (name, beschreibung) values
    ('Kiosk', 'Lagerkiosk nach dem Mittag'),
    ('Telefon', 'Telefonzeiten für Kinder'),
    ('Gute Fee', 'Leitungsspiele, Mörderli'),
    ('HL-Team', 'Hilfsleiter'),
    ('Krankenpflege', 'Gesundheit & Medikamente'),
    ('Foto Diashow', 'Fotos & Diashow'),
    ('Büro Bastelmat', 'Bastelmaterial-Inventar'),
    ('Disco', 'Disco-Material'),
    ('Skiweekend', 'Skiweekend Organisation'),
    ('Hauswart', 'Lagerhaus & Abwart'),
    ('Geländespielwiese', 'Wiesen in der Umgebung'),
    ('Lagerhaus nächstes Jahr', 'Lagerhaus für Folgejahr'),
    ('Verkleidung', 'Verkleidungsbestand'),
    ('Social Media', 'Social Media Betreuung')
  on conflict (name) do nothing;

  insert into org_aemtli_meta (organisation_id, aemtli_id, seiten_typ, beschreibung, hinweise_md, extra_felder)
  select v_org, a.id, x.seiten_typ, x.beschreibung, x.hinweise_md, x.extra_felder::jsonb
  from (values
    ('Kiosk', 'kiosk', 'Lagerkiosk', E'Nach dem Mittag (gerade/ungerade Gruppen).\nSüssigkeiten, Postkarten bestellen.\nGeld am Anreisetag sammeln – Buchführung in dieser App.', '{"felder":["postkarte_bestellt","gruppe_heute"]}'),
    ('Telefon', 'telefon', 'Telefonzeiten', E'Kinder telefonieren nach Hause – Zeiten in Elterninfo kommunizieren.\nStöla-Handy nutzen.', '{}'),
    ('Gute Fee', 'gute_fee', 'Gute Fee & Mörderli', E'Auflockerung vor Höck, Leitergeschenk (mit Kassier absprechen).\n**Mörderli-Spiel** direkt in der App – während Programm nicht erlaubt.', '{}'),
    ('HL-Team', 'hl', 'Hilfsleiter', E'Dashandy im HL-Zimmer, HL-Zimmer ordentlich halten.\nHL länger wach – Aktivitäten organisieren.', '{}'),
    ('Krankenpflege', 'krankenpflege', 'Gesundheit', E'Apotheke/Arzt/Krankenhaus vorher informieren.\nGesundheitsangaben aus TN-Anmeldung kontrollieren.', '{}'),
    ('Foto Diashow', 'foto', 'Foto & Diashow', E'Lagerfoto mit Kiosk bestellen.\nDiashow nach Lager, Website-Galerie aktualisieren.', '{}'),
    ('Büro Bastelmat', 'bastel', 'Bastelmaterial', E'Mehrjahres-Inventar (Vereins-Wissensspeicher).\nWährend Lager Ordnung halten.', '{}'),
    ('Disco', 'disco', 'Disco', E'Material für Disco sicherstellen.', '{}'),
    ('Skiweekend', 'skiweekend', 'Skiweekend', E'Mit Kassier Budget klären.\nTerminumfrage auf Org-Ebene.', '{}'),
    ('Hauswart', 'hauswart', 'Hauswart', E'Gute Beziehung zum Abwart.\nKaputt-Meldungen, Abnahme & Abgabe Lagerhaus.', '{}'),
    ('Geländespielwiese', 'gelaende', 'Geländespielwiesen', E'Bei Bauern in der Umgebung fragen.\nAm Schluss Flasche Wein als Dankeschön.', '{}'),
    ('Lagerhaus nächstes Jahr', 'generic', 'Folgejahr', E'Lagerhaus für nächstes Jahr finden und reservieren.', '{}'),
    ('Verkleidung', 'verkleidung', 'Verkleidungen', E'Mit Motto-Team absprechen.\nBestand pflegen oder Neues organisieren.', '{}'),
    ('Social Media', 'werbung', 'Social Media', E'Während & nach Lager für Eltern, Kinder, ehemalige Jublas.\nLogins im Werbung-Ämtli.', '{"felder":["social_media","content_plan"]}')
  ) as x(name, seiten_typ, beschreibung, hinweise_md, extra_felder)
  join aemtli a on a.name = x.name
  on conflict (organisation_id, aemtli_id) do update set
    seiten_typ = excluded.seiten_typ,
    beschreibung = excluded.beschreibung,
    hinweise_md = excluded.hinweise_md;
end $$;
