-- Bug: Höck-Rollen/Zuweisungen prüften ausschliesslich die lager_leiter-
-- Tabelle (App-Team-Rolle: Leiter/Lalei/Küche), nicht can_access_lager()
-- wie überall sonst im Lagerteam-Kontext. Leiter, die nur regulär über
-- anmeldungen_leiter bestätigt sind (ohne separate lager_leiter-Zeile),
-- konnten dadurch beim Höck weder Rollen sehen noch sich/andere
-- zuteilen - unabhängig vom Tag/Zeitpunkt.
drop policy if exists "hoeck_rollen_select" on hoeck_rollen;
create policy "hoeck_rollen_select" on hoeck_rollen
for select using (can_access_lager(lager_id));

drop policy if exists "hoeck_rollen_insert" on hoeck_rollen;
create policy "hoeck_rollen_insert" on hoeck_rollen
for insert with check (can_access_lager(lager_id));

drop policy if exists "hoeck_rollen_update" on hoeck_rollen;
create policy "hoeck_rollen_update" on hoeck_rollen
for update using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));

drop policy if exists "hoeck_zuweisungen_select" on hoeck_zuweisungen;
create policy "hoeck_zuweisungen_select" on hoeck_zuweisungen
for select using (can_access_lager((select hr.lager_id from hoeck_rollen hr where hr.id = hoeck_zuweisungen.hoeck_rolle_id)));

drop policy if exists "hoeck_zuweisungen_insert" on hoeck_zuweisungen;
create policy "hoeck_zuweisungen_insert" on hoeck_zuweisungen
for insert with check (can_access_lager((select hr.lager_id from hoeck_rollen hr where hr.id = hoeck_zuweisungen.hoeck_rolle_id)));

drop policy if exists "hoeck_zuweisungen_update" on hoeck_zuweisungen;
create policy "hoeck_zuweisungen_update" on hoeck_zuweisungen
for update using (can_access_lager((select hr.lager_id from hoeck_rollen hr where hr.id = hoeck_zuweisungen.hoeck_rolle_id)));

drop policy if exists "hoeck_zuweisungen_delete" on hoeck_zuweisungen;
create policy "hoeck_zuweisungen_delete" on hoeck_zuweisungen
for delete using (can_access_lager((select hr.lager_id from hoeck_rollen hr where hr.id = hoeck_zuweisungen.hoeck_rolle_id)));
