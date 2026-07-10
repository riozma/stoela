-- Diagnose: Albion Kabashi / Vereinsmitglied vs. Lager-Leiter
-- Im Supabase SQL Editor ausführen.

select
  p.id as profile_id,
  p.email,
  p.vorname,
  p.nachname,
  p.geburtsdatum,
  om.status as verein_status,
  om.rolle as verein_rolle,
  o.name as verein
from profiles p
left join organisation_mitglieder om on om.profile_id = p.id
left join organisation o on o.id = om.organisation_id
where lower(coalesce(p.vorname, '')) like '%albion%'
   or lower(coalesce(p.nachname, '')) like '%kabashi%'
   or lower(coalesce(p.email, '')) like '%albion%'
   or lower(coalesce(p.email, '')) like '%kabashi%';

select op.*
from org_personen op
where lower(op.vorname) like '%albion%'
   or lower(op.nachname) like '%kabashi%';

select al.*, l.name as lager
from anmeldungen_leiter al
join lager l on l.id = al.lager_id
where lower(al.vorname) like '%albion%'
   or lower(al.nachname) like '%kabashi%';

select ll.*, l.name as lager, p.email
from lager_leiter ll
join lager l on l.id = ll.lager_id
join profiles p on p.id = ll.profile_id
where lower(coalesce(p.vorname, '')) like '%albion%'
   or lower(coalesce(p.nachname, '')) like '%kabashi%';
