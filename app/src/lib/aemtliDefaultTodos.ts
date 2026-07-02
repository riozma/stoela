export interface AemtliTodo {
  id: string
  text: string
  done: boolean
}

export const DEFAULT_TODOS: Record<string, string[]> = {
  // --- Küche ---
  Küche: [
    'Allergien & Unverträglichkeiten aus TN-Anmeldungen prüfen',
    'Kochplan Woche 1 finalisieren und einkaufen',
    'Einkaufstermin Woche 1 einplanen (Car/Budget klären)',
    'Einkaufstermin Woche 2 einplanen',
    'Kochplan an Lagerleitung geben',
    'Mahlzeiten täglich in App erfassen',
    'Kassenstand wöchentlich mit Kassier abgleichen',
  ],

  // --- Finanzen / Kassier ---
  Finanzen: [
    'Budget mit Lagerleitung festlegen',
    'Kiosk-Geld am Anreisetag entgegennehmen',
    'TN-Beiträge bis Anmeldeschluss kontrollieren',
    'Quittungen wöchentlich abarbeiten',
    'Budget-Übersicht à jour halten',
    'Leiter-Auslagen (Quittungen) rechtzeitig auszahlen',
    'Schlussabrechnung nach Lager erstellen',
  ],

  // --- Kiosk ---
  Kiosk: [
    'Süssigkeiten und Postkarten vor Lager bestellen',
    'Postkartenbestellung mit Foto Diashow absprechen',
    'Artikel in App erfassen und Preise festlegen',
    'Geld von TN am Anreisetag kassieren und erfassen',
    'Täglich: Käufe in App erfassen (gerade/ungerade Gruppen)',
    'Restgeld am Lager-Letzttag auszahlen und Abrechnung erstellen',
  ],

  // --- Telefon ---
  Telefon: [
    'Telefonzeiten festlegen (z.B. Di+Do 18–19 Uhr)',
    'Zeiten an Elterninfo weitergeben (Telefon-Ämtli → Elterninfo)',
    'Stöla-Handy laden und im Büro bereitstellen',
    'Gerade/ungerade Gruppen mit Kiosk koordinieren (gleiche Zeit)',
    'Telefonzeiten im Lagerprogramm (Höck) kommunizieren',
  ],

  // --- Gute Fee ---
  'Gute Fee': [
    'Leitergeschenk mit Kassier abklären (Budget)',
    'Orte und Gegenstände für Mörderli in App erfassen',
    'Mörderli-Starttermin im Team besprechen (nicht während Programm)',
    'Spieler aus Leiter-Liste laden und zufällig zuweisen',
    'Board für alle Leiter freischalten',
    'Leitergeschenk kaufen und verstecken',
    'Gute-Fee-Tradition am letzten Abend durchführen',
  ],

  // --- HL-Team ---
  'HL-Team': [
    'Dashandy Stöcklilager im HL-Zimmer bereitstellen',
    'HL-Zimmer-Regeln besprechen (Ordnung, Zeiten)',
    'HL-Aktivitäten für freie Abende planen',
    'Rolle im Lageralltag mit Lagerleitung besprechen',
    'HL im Höck einbeziehen (Verantwortlichkeiten)',
  ],

  // --- Krankenpflege / Sanität ---
  Krankenpflege: [
    'Apotheke / Arzt / Krankenhaus in Lager-Nähe informieren',
    'Gesundheitsangaben aller TN aus Anmeldung prüfen',
    'Erste-Hilfe-Koffer prüfen und auffüllen',
    'Medikamentenliste TN erstellen (wer nimmt was wann)',
    'Notfallnummern sichtbar aushängen',
    'Sanitätsraum einrichten',
    'J&S-Unfallformulare bereithalten',
  ],
  Sanität: [
    'Gesundheitsangaben aller TN aus Anmeldung prüfen',
    'Erste-Hilfe-Koffer prüfen und auffüllen',
    'Medikamentenliste TN erstellen',
    'Notfallnummern sichtbar aushängen',
    'Apotheke / Arzt / Krankenhaus in Lager-Nähe kontaktieren',
  ],

  // --- Foto Diashow ---
  'Foto Diashow': [
    'Lagerfoto (Grosse Gruppenaufnahme) bestellen (via Kiosk)',
    'Kamera / Geräte bereitstellen und Ladekabel einpacken',
    'Täglich Fotos auf sicherem Speicher sichern',
    'Alle Leiter zum Fotos-Hochladen animieren',
    'Diashow nach Lager zusammenstellen (Beamer-Abend)',
    'Highlights für Social Media / Website auswählen',
    'Website-Galerie nach Lager aktualisieren',
  ],

  // --- Büro Bastelmat ---
  'Büro Bastelmat': [
    'Inventar in App prüfen (Mindestbestand-Warnungen)',
    'Fehlende Materialien vor Lager nachbestellen',
    'Bastelecke im Lagerhaus einrichten',
    'Ordnung täglich einhalten (besonders nach Bastelnachmittagen)',
    'Inventar nach Lager aktualisieren (Verbrauch einpflegen)',
    'Nachbestellliste für nächstes Jahr notieren',
  ],

  // --- Disco ---
  Disco: [
    'Musik-Playlist vorbereiten (alters- und themengerecht)',
    'Box, Kabel, Mikrofon und Lichter rechtzeitig einpacken',
    'DJ-Schicht im Programm einplanen',
    'Disco-Material aus Lager prüfen und bereitstellen',
    'Sicherheit: Lautstärke und Ausgang prüfen',
  ],

  // --- Skiweekend ---
  Skiweekend: [
    'Budget mit Kassier klären',
    'Terminumfrage unter Leiter starten',
    'Ort und Skigebiet festlegen',
    'Anmeldungen in App sammeln (wer ist wann dabei)',
    'Timetable in App einpflegen',
    'Fahrt / Unterkunft organisieren',
    'Anmeldeschluss setzen und kommunizieren',
  ],

  // --- Hauswart ---
  Hauswart: [
    'Kontakt mit Abwart / Hausverantwortlichen aufnehmen',
    'Lagerhaus-Zustand bei Ankunft dokumentieren (Fotos)',
    'Kaputt-Meldungen sofort erfassen und Abwart informieren',
    'Haushaltspflichten (Reinigung, Abfall) koordinieren',
    'Abnahme-Protokoll bei Abreise durchführen',
    'Lagerhaus sauber übergeben',
  ],

  // --- Geländespielwiese ---
  Geländespielwiese: [
    'Mögliche Wiesen in der Umgebung auf Karte identifizieren',
    'Bauern persönlich anfragen (Telefon oder klingeln)',
    'Zusagen in App dokumentieren (Bauer, Kontakt)',
    'Wiesen während Lager im guten Zustand lassen',
    'Nach Lager: Dankeschön (Flasche Wein) persönlich vorbeigebracht',
  ],

  // --- Lagerhaus nächstes Jahr ---
  'Lagerhaus nächstes Jahr': [
    'Lagerhaus-Optionen aus Vorjahr prüfen (Learnings)',
    'Mindestens 3 Standorte anfragen',
    'Angebote vergleichen (Preis, Betten, Küche, Distanz)',
    'Entscheid mit Lagerleitung fällen',
    'Reservierung bestätigen (Vertrag unterschreiben)',
    'Anzahlung klären',
  ],

  // --- Verkleidung ---
  Verkleidung: [
    'Bestehenden Bestand sichten und dokumentieren',
    'Mit Motto-Team absprechen: Was wird gebraucht?',
    'Fehlende Verkleidungen rechtzeitig organisieren (Brocki / Bastelmat)',
    'Verkleidungen beschriften und in Kisten verstauen',
    'Bestand nach Lager aktualisieren',
  ],

  // --- Social Media ---
  'Social Media': [
    'Logins sichern und an Nachfolger weitergeben',
    'Content-Plan vor Lager erstellen (was, wann posten)',
    'Während Lager: tägliche Stories / Posts vorbereiten',
    'Highlights mit Foto Diashow koordinieren',
    'Nach Lager: Rückblicks-Post und Diashow-Link posten',
  ],

  // --- Kuchenstand ---
  Kuchenstand: [
    'Datum, Standort und Zeiten festlegen',
    'Bewilligung prüfen (bei Bedarf)',
    'Anmeldungen für Backwaren sammeln (in App)',
    'Schichten einteilen (Aufbau, Verkauf, Abbau)',
    'Kasse und Wechselgeld bereitstellen',
    'Einnahmen nach Kuchenstand mit Kassier abgleichen',
  ],

  // --- Sponsoring ---
  Sponsoring: [
    'Sponsorenliste aus Vorjahr sichten (wer hat gegeben?)',
    'Anschreiben vorbereiten und versenden',
    'Eingehende Zusagen und Spenden dokumentieren',
    'Quittungen / Spendenbestätigungen ausstellen',
    'Nach Lager: Dankeskarte mit Lagerfoto verschicken',
  ],

  // --- Werbung ---
  Werbung: [
    'Plakat- und Flyer-Gestaltung starten (Motto, Datum, Ort)',
    'Druckauftrag erteilen (Anzahl und Format klären)',
    'Verteilplan erstellen (Schulen, Vereine, Auslagen)',
    'Online-Werbung: Social Media, Website, Newsletter',
    'Anmeldeformular / Link in Werbematerial einbinden',
    'Restliche Plakate nach Anmeldeschluss abräumen',
  ],

  // --- Motto ---
  Motto: [
    'Mind. 3 Motto-Vorschläge ausarbeiten',
    'Abstimmung im Leiterteam durchführen',
    'Gewähltes Motto an alle Ämtli kommunizieren',
    'Themenmaterial und Ideen sammeln (Deko, Verkleidung, Programm)',
    'Motto auf Plakate und Werbematerial abstimmen (mit Werbung-Ämtli)',
  ],

  // --- Material / J&S Mat ---
  Material: [
    'Materialliste aus Vorjahr prüfen',
    'Material auf eCamp-Programm abstimmen',
    'Fehlende Materialien rechtzeitig organisieren',
    'J&S-Materialanfrage einreichen (falls nötig)',
    'Material sorgfältig einpacken und beschriften',
    'Nach Lager: Inventar prüfen, Schäden melden',
  ],

  // --- Lagerleitung ---
  Lagerleitung: [
    'Leiteranfragen bearbeiten (freischalten oder ablehnen)',
    'Ämtli an Leiter verteilen',
    'Gruppenverteilung vornehmen',
    'Jugendurlaub J&S beantragen',
    'Elterninfo erstellen und verschicken',
    'Coach und TJ/S informieren (Feinprogramm)',
    'Höck täglich leiten',
    'Learnings nach Lager dokumentieren',
  ],
}

export function initialTodosForAemtli(name: string): AemtliTodo[] {
  const texts = DEFAULT_TODOS[name] ?? [`Aufgaben für ${name} ergänzen`]
  return texts.map((text) => ({
    id: crypto.randomUUID(),
    text,
    done: false,
  }))
}
