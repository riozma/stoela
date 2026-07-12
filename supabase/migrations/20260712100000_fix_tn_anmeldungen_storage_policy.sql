-- Bug: Policy verglich storage.foldername(l.name) (Lager-NAME, z.B.
-- "Stöla 27" - enthält keine "/", also immer leeres Array) statt
-- storage.foldername(objects.name) (tatsächlicher Datei-Pfad
-- "<lager_id>/<anmeldung_id>/..."). Dadurch war der SELECT-Zugriff auf
-- hochgeladene TN-Dokumente (Impfausweis, Krankenkassenkarte) für das
-- Lagerteam faktisch nie möglich.
drop policy if exists "tn-anmeldungen: lesen lagerteam" on storage.objects;
create policy "tn-anmeldungen: lesen lagerteam" on storage.objects
for select using (
  bucket_id = 'tn-anmeldungen'
  and exists (
    select 1 from lager l
    where l.id::text = (storage.foldername(objects.name))[1]
      and can_access_lager(l.id)
  )
);
