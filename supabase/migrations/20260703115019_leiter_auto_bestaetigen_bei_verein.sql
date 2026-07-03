-- Vereinsmitglieder sollen bei Leiter-Anmeldung nicht auf manuelle Freigabe warten müssen.
-- Die Anmeldung wird automatisch auf "bestaetigt" gesetzt und ins Lager-Team synchronisiert.

create or replace function public.auto_bestaetige_vereinsmitglied_leiteranmeldung()
returns trigger
language plpgsql
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

drop trigger if exists trg_auto_bestaetige_vereinsmitglied_leiteranmeldung on anmeldungen_leiter;
create trigger trg_auto_bestaetige_vereinsmitglied_leiteranmeldung
before insert or update of profile_id, lager_id, status
on anmeldungen_leiter
for each row
execute function public.auto_bestaetige_vereinsmitglied_leiteranmeldung();

create or replace function public.sync_lager_leiter_aus_bestaetigter_anmeldung()
returns trigger
language plpgsql
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

drop trigger if exists trg_sync_lager_leiter_aus_bestaetigter_anmeldung on anmeldungen_leiter;
create trigger trg_sync_lager_leiter_aus_bestaetigter_anmeldung
after insert or update of status, profile_id, lager_id
on anmeldungen_leiter
for each row
execute function public.sync_lager_leiter_aus_bestaetigter_anmeldung();
