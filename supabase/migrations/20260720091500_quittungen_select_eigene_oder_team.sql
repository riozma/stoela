-- Wer eine Quittung org-weit einreicht (siehe
-- is_org_mitglied_von_lager in quittungen_insert_org_mitglied), muss
-- sie danach auch selbst wieder sehen können, auch ohne vollen
-- Lagerteam-Zugriff.
drop policy "quittungen: select lagerteam" on quittungen;
create policy "quittungen: select lagerteam" on quittungen
  for select to authenticated
  using (can_access_lager(lager_id) or einreicher_id = auth.uid());
