-- Bugfix: "om.profile_id = profile_id" resolvte auf om.profile_id (Tautologie) statt auf die neue Zeile;
-- damit konnte jedes Lagerteam-Mitglied eine anmeldungen_leiter-Zeile für eine beliebige profile_id anlegen.
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
        where l.id = anmeldungen_leiter.lager_id
          and om.profile_id = anmeldungen_leiter.profile_id
          and om.status = 'mitglied'
      )
    )
  );
