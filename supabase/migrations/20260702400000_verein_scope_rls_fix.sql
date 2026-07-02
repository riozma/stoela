-- org_aemtli_meta, verein und events waren noch mit "jeder eingeloggte
-- Account" abgesichert statt "bestätigtes Team-Mitglied irgendeines
-- Lagers" wie der Rest des Systems (z.B. aemtli). Ein neu registrierter,
-- noch nicht freigeschalteter Account konnte dadurch Vereinsdaten lesen
-- und sogar verändern.
create or replace function public.ist_bestaetigter_leiter()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from lager_leiter ll
    where ll.profile_id = auth.uid() and ll.status = 'bestaetigt'
  );
$$;

drop policy "org_aemtli_meta: team" on org_aemtli_meta;
create policy "org_aemtli_meta: bestätigte Leiter" on org_aemtli_meta
  for all to authenticated
  using (public.ist_bestaetigter_leiter())
  with check (public.ist_bestaetigter_leiter());

drop policy "verein: für eingeloggte" on verein;
create policy "verein: bestätigte Leiter" on verein
  for all to authenticated
  using (public.ist_bestaetigter_leiter())
  with check (public.ist_bestaetigter_leiter());

drop policy "events: für eingeloggte" on events;
create policy "events: bestätigte Leiter" on events
  for all to authenticated
  using (public.ist_bestaetigter_leiter())
  with check (public.ist_bestaetigter_leiter());
