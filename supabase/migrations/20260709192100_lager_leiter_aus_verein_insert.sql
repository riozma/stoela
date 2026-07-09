-- Lagerleitung darf Leiter aus dem Verein ins Lager aufnehmen (mit oder ohne Login).

drop policy if exists "anmeldungen_leiter: insert für Lagerteam" on anmeldungen_leiter;

create policy "anmeldungen_leiter: insert für Lagerteam" on anmeldungen_leiter
  for insert to authenticated
  with check (
    public.can_access_lager(lager_id)
    and (
      profile_id is null
      or profile_id = auth.uid()
      or exists (
        select 1
        from lager l
        join organisation_mitglieder om on om.organisation_id = l.organisation_id
        where l.id = lager_id
          and om.profile_id = profile_id
          and om.status = 'mitglied'
      )
    )
  );
