-- Bug: hat_aemtli() (anders als is_kueche()) hatte keinen Fallback für
-- die Lagerleitung. Wer ein Ämtli (z.B. "Geländespielwiese") nicht
-- explizit zugewiesen hatte - auch die Lalei selbst nicht - konnte
-- dadurch RLS-blockiert scheitern, z.B. beim Erfassen einer neuen Wiese.
-- Das Frontend wertete den Insert-Fehler nicht aus, wodurch es aussah,
-- als würde nichts gespeichert. Fix: Lagerleitung darf immer.
create or replace function public.hat_aemtli(p_lager_id uuid, p_name text)
returns boolean
language sql
stable security definer
set search_path to 'public'
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
    )
    or public.is_lager_leitung(p_lager_id);
$$;
