-- Die Policy «lager: select anmeldung basis» erlaubte jedem (auch ohne Team-Zugang)
-- alle Lager mit Status planung/anmeldung_offen/laufend zu lesen.
-- Anmelde- und Willkommensseiten nutzen bereits RPCs (get_lager_anmeldung_*,
-- get_lager_willkommen) – direkter Tabellenzugriff ist nicht nötig.

drop policy if exists "lager: select anmeldung basis" on lager;
