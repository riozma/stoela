-- Vereinspersonen für Lager-Leiterauswahl: Login-Mitglieder + manuelle Einträge.

create or replace function public.list_verein_personen_fuer_lager(p_organisation_id uuid)
returns table (
  id text,
  profile_id uuid,
  vorname text,
  nachname text,
  email text,
  quelle text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet';
  end if;

  if not public.is_org_mitglied(p_organisation_id)
    and not public.is_org_leitung(p_organisation_id)
    and not exists (
      select 1
      from lager l
      where l.organisation_id = p_organisation_id
        and public.can_access_lager(l.id)
    ) then
    raise exception 'Kein Zugriff auf diese Organisation';
  end if;

  return query
  with login_mitglieder as (
    select
      ('login-' || om.profile_id::text) as rid,
      om.profile_id as rprofile_id,
      coalesce(
        nullif(trim(p.vorname), ''),
        nullif(trim(u.raw_user_meta_data->>'given_name'), '')
      ) as rvorname,
      coalesce(
        nullif(trim(p.nachname), ''),
        nullif(trim(u.raw_user_meta_data->>'family_name'), '')
      ) as rnachname,
      coalesce(nullif(trim(p.email), ''), u.email::text) as remail
    from organisation_mitglieder om
    join auth.users u on u.id = om.profile_id
    left join profiles p on p.id = om.profile_id
    where om.organisation_id = p_organisation_id
      and om.status = 'mitglied'
  )
  select
    lm.rid,
    lm.rprofile_id,
    coalesce(lm.rvorname, ''),
    coalesce(lm.rnachname, ''),
    lm.remail,
    'login'::text
  from login_mitglieder lm
  union all
  select
    ('person-' || op.id::text),
    op.profile_id,
    op.vorname,
    op.nachname,
    op.email,
    case when op.profile_id is null then 'manuell' else 'login_verknuepft' end
  from org_personen op
  where op.organisation_id = p_organisation_id
    and op.aktiv = true
    and (
      op.profile_id is null
      or not exists (
        select 1 from login_mitglieder lm where lm.rprofile_id = op.profile_id
      )
    )
  order by 4, 3;
end;
$$;

grant execute on function public.list_verein_personen_fuer_lager(uuid) to authenticated;
