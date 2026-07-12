-- Bug: can_view_lager()/can_access_lager() fragen intern erneut "from lager"
-- ab, um die per id übergebene Zeile zu pruefen. Bei INSERT ... RETURNING
-- (wie es PostgREST/supabase-js .select().single() nach insert() macht) ist
-- die soeben eingefuegte Zeile innerhalb desselben Befehls fuer eine
-- Sub-Query auf dieselbe Tabelle noch nicht sichtbar -> RLS-Fehler beim
-- Lager-Erstellen. Fix: SELECT-Policy direkt auf den Zeilenspalten
-- auswerten statt die Tabelle selbst erneut abzufragen.

drop policy if exists "lager: select für berechtigte" on lager;
create policy "lager: select für berechtigte" on lager
for select
using (
  created_by = auth.uid()
  or exists (
    select 1 from lager_leiter ll
    where ll.lager_id = lager.id
      and ll.profile_id = auth.uid()
      and ll.status = 'bestaetigt'
  )
  or exists (
    select 1 from organisation_mitglieder om
    where om.organisation_id = lager.organisation_id
      and om.profile_id = auth.uid()
      and om.status = 'mitglied'
  )
);
