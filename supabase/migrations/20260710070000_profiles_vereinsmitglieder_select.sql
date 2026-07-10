-- Vereinsmitglieder dürfen Profile anderer Mitglieder derselben Organisation lesen
-- (für Leiterliste in /organisation mit Namen und E-Mail).

create policy "profiles: select vereinsmitglieder gleiche org" on profiles
  for select to authenticated
  using (
    exists (
      select 1
      from organisation_mitglieder om_self
      join organisation_mitglieder om_other
        on om_other.organisation_id = om_self.organisation_id
      where om_self.profile_id = auth.uid()
        and om_self.status = 'mitglied'
        and om_other.profile_id = profiles.id
        and om_other.status in ('mitglied', 'angefragt')
    )
  );
