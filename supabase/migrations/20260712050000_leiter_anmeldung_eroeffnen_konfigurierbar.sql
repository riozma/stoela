-- Leiterbewerbung war bisher praktisch immer offen (sobald Lager-Status
-- planung/anmeldung_offen/laufend war) und hatte keine eigene Ein/Aus-
-- Schaltung. Neu: eigener Status + konfigurierbare Pflichtfelder, analog
-- zur TN-Anmeldung. Vorname/Nachname/E-Mail/Telefon bleiben immer Pflicht,
-- Geburtsdatum/Geschlecht/AHV/Essensgewohnheiten sind ab jetzt einzeln
-- abschaltbar.
alter table lager add column if not exists leiter_anmeldung_status text not null default 'geschlossen'
  check (leiter_anmeldung_status in ('geschlossen', 'offen'));
alter table lager add column if not exists leiter_anmeldung_config jsonb not null default
  '{"geburtsdatum": true, "geschlecht": true, "ahv_nr": true, "essensgewohnheiten": true}'::jsonb;

create or replace function public.get_lager_anmeldung_info(p_lager_id uuid, p_typ text default 'tn')
returns json
language sql
stable security definer
set search_path to 'public'
as $$
  select json_build_object(
    'id', l.id,
    'name', l.name,
    'ort', l.ort,
    'start_datum', l.start_datum,
    'end_datum', l.end_datum,
    'status', l.status,
    'leiter_anmeldung_config', l.leiter_anmeldung_config
  )
  from lager l
  where l.id = p_lager_id
    and l.status <> 'archiviert'
    and (
      (p_typ = 'tn' and l.status = 'anmeldung_offen')
      or (p_typ = 'leiter' and l.leiter_anmeldung_status = 'offen')
    );
$$;
