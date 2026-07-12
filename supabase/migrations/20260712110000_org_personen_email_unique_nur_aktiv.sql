-- Bug: UNIQUE(organisation_id, email) galt auch für inaktive (gelöschte)
-- org_personen-Einträge. Beim "Leiter verknüpfen" wurde die E-Mail des
-- manuellen Eintrags mit der Profil-E-Mail befüllt, was mit einer
-- bereits vorhandenen, aber inaktiven Karteileiche kollidierte ->
-- "duplicate key value violates unique constraint" beim Verknüpfen.
-- Fix: Unique-Constraint nur für aktive Einträge.
alter table org_personen drop constraint if exists org_personen_organisation_id_email_key;
create unique index org_personen_organisation_id_email_aktiv_key
  on org_personen (organisation_id, email)
  where aktiv = true;
