-- Impfausweis/Krankenkassenkarten-Uploads sollen 1 Monat nach Lagerende
-- automatisch gelöscht werden (Datenschutz/Speicherplatz).
create extension if not exists pg_cron;

create or replace function public.loesche_alte_tn_dokumente()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from storage.objects o
  using tn_anmeldung_dokumente d
  join anmeldungen_tn t on t.id = d.anmeldung_tn_id
  join lager l on l.id = t.lager_id
  where o.bucket_id = 'tn-anmeldungen'
    and o.name = d.storage_path
    and l.end_datum is not null
    and l.end_datum < (current_date - interval '1 month');

  delete from tn_anmeldung_dokumente d
  using anmeldungen_tn t, lager l
  where d.anmeldung_tn_id = t.id
    and t.lager_id = l.id
    and l.end_datum is not null
    and l.end_datum < (current_date - interval '1 month');
end;
$$;

select cron.schedule(
  'loesche_alte_tn_dokumente_taeglich',
  '0 3 * * *',
  $$select public.loesche_alte_tn_dokumente();$$
);
