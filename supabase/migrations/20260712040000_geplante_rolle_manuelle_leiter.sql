-- Manuell hinzugefügte Leiter (ohne Login/profile_id) können keine echte
-- App-Rolle in lager_leiter erhalten (profile_id dort ist NOT NULL, da die
-- Rolle über auth.uid() für RLS geprüft wird). Damit die Lalei trotzdem
-- schon vorab festlegen kann, welche Rolle die Person haben soll, gibt es
-- ein Planfeld auf der Anmeldung selbst. Sobald die Person später ein
-- Login erhält und verknüpft wird, kann diese geplante Rolle übernommen
-- werden.
alter table anmeldungen_leiter add column if not exists geplante_rolle text
  check (geplante_rolle in ('leiter', 'lagerleitung', 'kueche'));

create or replace view leiter_teilnahmen as
 SELECT al.id,
    al.lager_id,
    al.profile_id,
    COALESCE(p.vorname, al.vorname) AS vorname,
    COALESCE(p.nachname, al.nachname) AS nachname,
    COALESCE(p.email, al.email) AS email,
    COALESCE(p.telefon, al.telefon) AS telefon,
    COALESCE(p.geburtsdatum, al.geburtsdatum) AS geburtsdatum,
    COALESCE(p.geschlecht, al.geschlecht) AS geschlecht,
    COALESCE(p.ahv_nr, al.ahv_nr) AS ahv_nr,
    al.anwesend_von,
    al.anwesend_bis,
    al.essensgewohnheiten,
    al.status,
    al.anmeldung_art,
    al.bestaetigen_bis,
    al.von_vorjahr,
    al.von_lager_id,
    al.created_at,
    al.geplante_rolle
   FROM anmeldungen_leiter al
     LEFT JOIN profiles p ON p.id = al.profile_id;
