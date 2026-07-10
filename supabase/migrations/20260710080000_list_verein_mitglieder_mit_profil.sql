-- Vereins-Leiterliste: Namen/E-Mails zuverlässig für alle Vereinsmitglieder lesbar
-- (auch wenn profiles-RLS oder leere Profilfelder die direkte Abfrage blockieren).

create or replace function public.list_verein_mitglieder_mit_profil(p_organisation_id uuid)
returns table (
  profile_id uuid,
  rolle text,
  status text,
  angefragt_am timestamptz,
  vorname text,
  nachname text,
  email text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet';
  end if;

  if not public.is_org_mitglied(p_organisation_id) then
    raise exception 'Kein Zugriff auf diese Organisation';
  end if;

  return query
  select
    om.profile_id,
    om.rolle::text,
    om.status::text,
    om.angefragt_am,
    coalesce(
      nullif(trim(p.vorname), ''),
      (
        select al.vorname
        from anmeldungen_leiter al
        join lager l on l.id = al.lager_id
        where l.organisation_id = p_organisation_id
          and al.profile_id = om.profile_id
          and nullif(trim(al.vorname), '') is not null
        order by al.created_at desc
        limit 1
      )
    ) as vorname,
    coalesce(
      nullif(trim(p.nachname), ''),
      (
        select al.nachname
        from anmeldungen_leiter al
        join lager l on l.id = al.lager_id
        where l.organisation_id = p_organisation_id
          and al.profile_id = om.profile_id
          and nullif(trim(al.nachname), '') is not null
        order by al.created_at desc
        limit 1
      )
    ) as nachname,
    coalesce(
      nullif(trim(p.email), ''),
      nullif(trim(u.email::text), ''),
      (
        select al.email
        from anmeldungen_leiter al
        join lager l on l.id = al.lager_id
        where l.organisation_id = p_organisation_id
          and al.profile_id = om.profile_id
          and nullif(trim(al.email), '') is not null
        order by al.created_at desc
        limit 1
      )
    ) as email
  from organisation_mitglieder om
  join auth.users u on u.id = om.profile_id
  left join profiles p on p.id = om.profile_id
  where om.organisation_id = p_organisation_id
  order by om.angefragt_am desc;
end;
$$;

grant execute on function public.list_verein_mitglieder_mit_profil(uuid) to authenticated;
