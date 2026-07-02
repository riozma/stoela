-- Jede Person (TN oder Leiter) höchstens in einer Gruppe

delete from gruppen_mitglieder a
using gruppen_mitglieder b
where a.anmeldung_tn_id is not null
  and a.anmeldung_tn_id = b.anmeldung_tn_id
  and a.id > b.id;

delete from gruppen_mitglieder a
using gruppen_mitglieder b
where a.anmeldung_leiter_id is not null
  and a.anmeldung_leiter_id = b.anmeldung_leiter_id
  and a.id > b.id;

create unique index if not exists gruppen_mitglieder_ein_tn
  on gruppen_mitglieder (anmeldung_tn_id)
  where anmeldung_tn_id is not null;

create unique index if not exists gruppen_mitglieder_ein_leiter
  on gruppen_mitglieder (anmeldung_leiter_id)
  where anmeldung_leiter_id is not null;
