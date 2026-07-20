-- Der Org-weite Quittungen-Tab erlaubt die Auswahl jedes Lagers des
-- eigenen Vereins, nicht nur der Lager, in denen man bereits im
-- Lagerteam bestätigt ist. can_access_lager() allein reichte daher
-- für viele legitime Einreicher nicht aus -- ergänzt um allgemeine
-- Vereinsmitgliedschaft.
create or replace function public.is_org_mitglied_von_lager(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from lager l
    join organisation_mitglieder om on om.organisation_id = l.organisation_id
    where l.id = p_lager_id and om.profile_id = auth.uid() and om.status = 'mitglied'
  );
$$;

drop policy "quittungen: insert eigenes" on quittungen;
create policy "quittungen: insert eigenes" on quittungen
  for insert to authenticated
  with check (
    (can_access_lager(lager_id) or is_org_mitglied_von_lager(lager_id))
    and einreicher_id = auth.uid()
  );
