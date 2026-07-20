-- Die UI verhindert das Bearbeiten einer eigenen Quittung nach Bestätigung
-- schon, aber die RLS selbst prüfte den Status nicht -- ein direkter API-
-- Aufruf hätte eine bereits bezahlte/abgelehnte Quittung noch ändern
-- können. Jetzt so, dass Einreicher nur "pending" bearbeiten können,
-- Finanzen aber weiterhin jederzeit (z.B. um Fehler zu korrigieren).
drop policy "quittungen: update einreicher oder finanzen" on quittungen;
create policy "quittungen: update einreicher oder finanzen" on quittungen
  for update to authenticated
  using ((einreicher_id = auth.uid() and status = 'pending') or hat_aemtli(lager_id, 'Finanzen'))
  with check ((einreicher_id = auth.uid() and status = 'pending') or hat_aemtli(lager_id, 'Finanzen'));
