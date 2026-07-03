-- Trigger-Funktionen laufen mit SECURITY DEFINER, damit die
-- automatische Lager-Team-Synchronisierung nicht an RLS scheitert.

create or replace function public.auto_bestaetige_vereinsmitglied_leiteranmeldung()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
begin
  if new.profile_id is null then
    return new;
  end if;

  select l.organisation_id into v_org_id
  from lager l
  where l.id = new.lager_id;

  if v_org_id is null then
    return new;
  end if;

  if exists (
    select 1
    from organisation_mitglieder om
    where om.organisation_id = v_org_id
      and om.profile_id = new.profile_id
      and om.status = 'mitglied'
  ) and new.status in ('angefragt', 'angemeldet') then
    new.status := 'bestaetigt';
  end if;

  return new;
end;
$$;

create or replace function public.sync_lager_leiter_aus_bestaetigter_anmeldung()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.profile_id is null then
    return new;
  end if;

  if new.status = 'bestaetigt' then
    insert into lager_leiter (lager_id, profile_id, rolle, status)
    values (new.lager_id, new.profile_id, 'leiter', 'bestaetigt')
    on conflict (lager_id, profile_id)
    do update set status = 'bestaetigt';
  end if;

  return new;
end;
$$;
