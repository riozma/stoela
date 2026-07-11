-- Küche wird eine App-Rolle im Team (neben Leiter/Lalei) statt eines
-- zuweisbaren Ämtlis. Bestehende Küche-Ämtli-Zuweisungen bleiben als
-- Fallback funktionsfähig (is_kueche prüft beides).

alter table lager_leiter drop constraint if exists lager_leiter_rolle_check;
alter table lager_leiter add constraint lager_leiter_rolle_check
  check (rolle in ('lagerleitung', 'leiter', 'aemtli_verantwortlich', 'kueche'));

create or replace function public.is_kueche(p_lager_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from lager_leiter ll
    where ll.lager_id = p_lager_id
      and ll.profile_id = auth.uid()
      and ll.rolle = 'kueche'
      and ll.status = 'bestaetigt'
  )
  or exists (
    select 1
    from aemtli_zuweisungen az
    join aemtli a on a.id = az.aemtli_id
    where az.lager_id = p_lager_id
      and az.profile_id = auth.uid()
      and a.name = 'Küche'
  )
  or exists (
    select 1
    from leiter_rollen lr
    join anmeldungen_leiter al on al.id = lr.anmeldung_leiter_id
    join aemtli a on a.id = lr.aemtli_id
    join profiles p on p.id = auth.uid()
    where al.lager_id = p_lager_id
      and lower(al.email) = lower(p.email)
      and a.name = 'Küche'
      and al.status = 'bestaetigt'
  )
  or public.is_lager_leitung(p_lager_id);
$$;
