-- Wer auf Org-Ebene das Ämtli "Finanzen" hat, soll alle Quittungen
-- seines Vereins sehen und bearbeiten können -- auch für Lager, in
-- denen er/sie nicht im Lagerteam ist (z.B. vergangene Lager oder
-- Lager, wo die Person nie einzeln registriert wurde). hat_aemtli()
-- ist rein lagerbezogen und reicht dafür nicht.
create or replace function public.is_org_finanzen_von_lager(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from lager l
    join org_aemtli_besetzung b on b.organisation_id = l.organisation_id
    join aemtli a on a.id = b.aemtli_id
    where l.id = p_lager_id
      and lower(a.name) = 'finanzen'
      and b.profile_id = auth.uid()
  );
$$;

grant execute on function public.is_org_finanzen_von_lager(uuid) to authenticated;

drop policy "quittungen: select lagerteam" on quittungen;
create policy "quittungen: select lagerteam" on quittungen
  for select to authenticated
  using (can_access_lager(lager_id) or einreicher_id = auth.uid() or is_org_finanzen_von_lager(lager_id));

drop policy "quittungen: update einreicher oder finanzen" on quittungen;
create policy "quittungen: update einreicher oder finanzen" on quittungen
  for update to authenticated
  using (
    (einreicher_id = auth.uid() and status = 'pending')
    or hat_aemtli(lager_id, 'Finanzen')
    or is_org_finanzen_von_lager(lager_id)
  )
  with check (
    (einreicher_id = auth.uid() and status = 'pending')
    or hat_aemtli(lager_id, 'Finanzen')
    or is_org_finanzen_von_lager(lager_id)
  );

-- is_org_finanzen_von_lager prüfte zunächst nur explizite Einträge in
-- org_aemtli_besetzung. Die Ämtli-Besetzung im Organisation-Tab zeigt
-- aber auch eine "letztes Lager"-Fallback-Zuteilung an, solange niemand
-- explizit gesetzt wurde -- resolve_org_aemtli_besetzung() kennt diese
-- Fallback-Logik bereits, also nutzen wir sie hier ebenfalls, damit
-- RLS-Zugriff und angezeigte Besetzung konsistent sind.
create or replace function public.is_org_finanzen_von_lager(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from lager l
    join public.resolve_org_aemtli_besetzung(l.organisation_id) r on lower(r.aemtli_name) = 'finanzen'
    where l.id = p_lager_id and r.profile_id = auth.uid()
  );
$$;
