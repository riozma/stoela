-- Lalei (lager-level Lagerleitung) sieht "+ Traktandum" / Höck-Typ erstellen in der UI, RLS erlaubte bisher nur org-weite Leitung/Admin
create or replace function public.is_lagerleitung_von_org(p_organisation_id uuid)
returns boolean
language sql
stable security definer
set search_path to 'public'
as $$
  select exists (
    select 1
    from lager l
    join lager_leiter ll on ll.lager_id = l.id
    where l.organisation_id = p_organisation_id
      and ll.profile_id = auth.uid()
      and ll.status = 'bestaetigt'
      and ll.rolle = 'lagerleitung'
  );
$$;

drop policy if exists "hoeck_typen: verwalten org-leitung" on hoeck_typen;
create policy "hoeck_typen: verwalten org-leitung" on hoeck_typen
  for all
  using (is_org_leitung(organisation_id) or is_lagerleitung_von_org(organisation_id))
  with check (is_org_leitung(organisation_id) or is_lagerleitung_von_org(organisation_id));

drop policy if exists "hoeck_traktanden: verwalten via typ" on hoeck_traktanden;
create policy "hoeck_traktanden: verwalten via typ" on hoeck_traktanden
  for all
  using (exists (
    select 1 from hoeck_typen t
    where t.id = hoeck_traktanden.hoeck_typ_id
      and (is_org_leitung(t.organisation_id) or is_lagerleitung_von_org(t.organisation_id))
  ))
  with check (exists (
    select 1 from hoeck_typen t
    where t.id = hoeck_traktanden.hoeck_typ_id
      and (is_org_leitung(t.organisation_id) or is_lagerleitung_von_org(t.organisation_id))
  ));
