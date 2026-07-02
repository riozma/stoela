-- Öffentliche Anmeldeformulare (TN/Leiter) müssen den Lagernamen und Status
-- ohne Login lesen können, aber nur solange die Anmeldung offen ist.
create policy "lager: select öffentlich bei offener Anmeldung" on lager
  for select to anon
  using (status = 'anmeldung_offen');
