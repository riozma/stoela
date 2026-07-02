-- hat_aemtli: Lagerleitung allein darf nicht automatisch jedes Ämtli (z. B. Finanzen) haben.
-- Quittungen-Update nur noch für Einreicher oder echtes Finanzen-Ämtli.

create or replace function public.hat_aemtli(p_lager_id uuid, p_name text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select
    (p_name = 'Küche' and public.is_kueche(p_lager_id))
    or exists (
      select 1 from aemtli_zuweisungen az
      join aemtli a on a.id = az.aemtli_id
      where az.lager_id = p_lager_id and az.profile_id = auth.uid() and a.name = p_name
    )
    or exists (
      select 1 from leiter_rollen lr
      join anmeldungen_leiter al on al.id = lr.anmeldung_leiter_id
      join aemtli a on a.id = lr.aemtli_id
      join profiles p on p.id = auth.uid()
      where al.lager_id = p_lager_id and lower(al.email) = lower(p.email)
        and a.name = p_name and al.status = 'bestaetigt'
    );
$$;

drop policy if exists "quittungen: update einreicher oder finanzen" on quittungen;

create policy "quittungen: update einreicher oder finanzen" on quittungen
  for update to authenticated
  using (
    einreicher_id = auth.uid()
    or public.hat_aemtli(lager_id, 'Finanzen')
  );
