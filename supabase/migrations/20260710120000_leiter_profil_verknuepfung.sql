-- Profile als Stammdaten für Leiter; robuste Verein→Lager-Verknüpfung; Lalei-Schutz.

alter table profiles
  add column if not exists geburtsdatum date,
  add column if not exists geschlecht text check (geschlecht is null or geschlecht in ('m', 'w', 'd')),
  add column if not exists ahv_nr text;

create or replace function public.profil_leiter_daten_sync(
  p_profile_id uuid,
  p_vorname text default null,
  p_nachname text default null,
  p_geburtsdatum date default null,
  p_geschlecht text default null,
  p_ahv_nr text default null,
  p_telefon text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_profile_id is null then
    return;
  end if;

  update profiles
  set
    vorname = coalesce(nullif(trim(p_vorname), ''), vorname),
    nachname = coalesce(nullif(trim(p_nachname), ''), nachname),
    geburtsdatum = coalesce(p_geburtsdatum, geburtsdatum),
    geschlecht = coalesce(nullif(trim(p_geschlecht), ''), geschlecht),
    ahv_nr = coalesce(nullif(trim(p_ahv_nr), ''), ahv_nr),
    telefon = coalesce(nullif(trim(p_telefon), ''), telefon)
  where id = p_profile_id;
end;
$$;

create or replace function public.lager_lalei_anzahl(p_lager_id uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from lager_leiter
  where lager_id = p_lager_id
    and rolle = 'lagerleitung'
    and status = 'bestaetigt';
$$;

create or replace function public.lager_leiter_aus_verein_hinzufuegen(
  p_lager_id uuid,
  p_profile_id uuid default null,
  p_org_person_id uuid default null,
  p_als_lalei boolean default false,
  p_anwesend_von date default null,
  p_anwesend_bis date default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org_id uuid;
  v_profile_id uuid;
  v_vorname text;
  v_nachname text;
  v_email text;
  v_telefon text;
  v_person org_personen%rowtype;
  v_anmeldung_id uuid;
  v_start date;
  v_ende date;
begin
  if not public.can_access_lager(p_lager_id) then
    raise exception 'Kein Zugriff auf dieses Lager.';
  end if;

  select organisation_id, start_datum, end_datum
  into v_org_id, v_start, v_ende
  from lager where id = p_lager_id;

  if v_org_id is null then
    raise exception 'Lager hat keine Organisation.';
  end if;

  if p_profile_id is not null then
    v_profile_id := p_profile_id;
    if not exists (
      select 1 from organisation_mitglieder om
      where om.organisation_id = v_org_id
        and om.profile_id = v_profile_id
        and om.status = 'mitglied'
    ) then
      raise exception 'Person ist kein bestätigtes Vereinsmitglied.';
    end if;

    select
      coalesce(nullif(trim(p.vorname), ''), nullif(trim(u.raw_user_meta_data->>'given_name'), '')),
      coalesce(nullif(trim(p.nachname), ''), nullif(trim(u.raw_user_meta_data->>'family_name'), '')),
      coalesce(nullif(trim(p.email), ''), u.email::text),
      p.telefon
    into v_vorname, v_nachname, v_email, v_telefon
    from auth.users u
    left join profiles p on p.id = u.id
    where u.id = v_profile_id;

    select coalesce(v_vorname, op.vorname), coalesce(v_nachname, op.nachname), coalesce(v_email, op.email), coalesce(v_telefon, op.telefon)
    into v_vorname, v_nachname, v_email, v_telefon
    from org_personen op
    where op.organisation_id = v_org_id
      and op.profile_id = v_profile_id
      and op.aktiv = true
    limit 1;

  elsif p_org_person_id is not null then
    select * into v_person
    from org_personen
    where id = p_org_person_id
      and organisation_id = v_org_id
      and aktiv = true;

    if not found then
      raise exception 'Manueller Vereinseintrag nicht gefunden.';
    end if;

    v_profile_id := v_person.profile_id;
    v_vorname := v_person.vorname;
    v_nachname := v_person.nachname;
    v_email := v_person.email;
    v_telefon := v_person.telefon;
  else
    raise exception 'profile_id oder org_person_id erforderlich.';
  end if;

  if coalesce(trim(v_vorname), '') = '' or coalesce(trim(v_nachname), '') = '' then
    raise exception 'Vor- und Nachname fehlen. Bitte im Verein Profil ergänzen.';
  end if;

  if exists (
    select 1 from anmeldungen_leiter al
    where al.lager_id = p_lager_id
      and (
        (v_profile_id is not null and al.profile_id = v_profile_id)
        or (lower(al.vorname) = lower(v_vorname) and lower(al.nachname) = lower(v_nachname))
      )
  ) then
    raise exception 'Person ist bereits als Leiter in diesem Lager erfasst.';
  end if;

  if v_profile_id is not null then
    perform public.profil_leiter_daten_sync(v_profile_id, v_vorname, v_nachname, null, null, null, v_telefon);
  end if;

  insert into anmeldungen_leiter (
    lager_id, profile_id, vorname, nachname, email, telefon,
    anwesend_von, anwesend_bis, status, anmeldung_art, bestaetigen_bis
  ) values (
    p_lager_id,
    v_profile_id,
    v_vorname,
    v_nachname,
    v_email,
    v_telefon,
    coalesce(p_anwesend_von, v_start),
    coalesce(p_anwesend_bis, v_ende),
    'bestaetigt',
    'fix',
    case when v_start is not null then (v_start - interval '3 months')::date else null end
  )
  returning id into v_anmeldung_id;

  if v_profile_id is not null then
    insert into lager_leiter (lager_id, profile_id, rolle, status)
    values (
      p_lager_id,
      v_profile_id,
      case when p_als_lalei then 'lagerleitung' else 'leiter' end,
      'bestaetigt'
    )
    on conflict (lager_id, profile_id) do update set
      rolle = case
        when p_als_lalei then 'lagerleitung'
        when lager_leiter.rolle = 'lagerleitung' then 'lagerleitung'
        else excluded.rolle
      end,
      status = 'bestaetigt';
  end if;

  return v_anmeldung_id;
end;
$$;

create or replace function public.leiter_anmeldung_speichern(
  p_anmeldung_id uuid,
  p_vorname text,
  p_nachname text,
  p_geburtsdatum date default null,
  p_geschlecht text default null,
  p_ahv_nr text default null,
  p_telefon text default null,
  p_anwesend_von date default null,
  p_anwesend_bis date default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row anmeldungen_leiter%rowtype;
  v_darf boolean := false;
begin
  select * into v_row from anmeldungen_leiter where id = p_anmeldung_id;
  if not found then
    raise exception 'Leiter-Anmeldung nicht gefunden.';
  end if;

  if not public.can_access_lager(v_row.lager_id) then
    raise exception 'Kein Zugriff.';
  end if;

  v_darf := public.is_lager_leitung(v_row.lager_id)
    or (v_row.profile_id is not null and v_row.profile_id = auth.uid());

  if not v_darf then
    raise exception 'Keine Berechtigung zum Bearbeiten.';
  end if;

  if coalesce(trim(p_vorname), '') = '' or coalesce(trim(p_nachname), '') = '' then
    raise exception 'Vorname und Nachname sind Pflicht.';
  end if;

  if v_row.profile_id is not null then
    perform public.profil_leiter_daten_sync(
      v_row.profile_id, p_vorname, p_nachname, p_geburtsdatum, p_geschlecht, p_ahv_nr, p_telefon
    );
  end if;

  update anmeldungen_leiter
  set
    vorname = trim(p_vorname),
    nachname = trim(p_nachname),
    geburtsdatum = coalesce(p_geburtsdatum, geburtsdatum),
    geschlecht = coalesce(nullif(trim(p_geschlecht), ''), geschlecht),
    ahv_nr = coalesce(nullif(trim(p_ahv_nr), ''), ahv_nr),
    telefon = coalesce(nullif(trim(p_telefon), ''), telefon),
    anwesend_von = coalesce(p_anwesend_von, anwesend_von),
    anwesend_bis = coalesce(p_anwesend_bis, anwesend_bis)
  where id = p_anmeldung_id;
end;
$$;

create or replace function public.lager_leiter_rolle_setzen(
  p_lager_leiter_id uuid,
  p_rolle text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row lager_leiter%rowtype;
  v_lalei int;
begin
  if p_rolle not in ('leiter', 'lagerleitung') then
    raise exception 'Ungültige Rolle.';
  end if;

  select * into v_row from lager_leiter where id = p_lager_leiter_id;
  if not found then
    raise exception 'Team-Eintrag nicht gefunden.';
  end if;

  if not public.is_lager_leitung(v_row.lager_id) then
    raise exception 'Nur Lagerleitung darf Rollen ändern.';
  end if;

  v_lalei := public.lager_lalei_anzahl(v_row.lager_id);

  if v_row.rolle = 'lagerleitung' and p_rolle <> 'lagerleitung' and v_lalei <= 1 then
    raise exception 'Es muss mindestens eine Person die Rolle Lagerleitung (Lalei) behalten.';
  end if;

  update lager_leiter set rolle = p_rolle where id = p_lager_leiter_id;
end;
$$;

create or replace function public.lager_leiter_sicher_entfernen(p_lager_leiter_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row lager_leiter%rowtype;
  v_lalei int;
begin
  select * into v_row from lager_leiter where id = p_lager_leiter_id;
  if not found then
    raise exception 'Team-Eintrag nicht gefunden.';
  end if;

  if not public.is_lager_leitung(v_row.lager_id) then
    raise exception 'Nur Lagerleitung darf entfernen.';
  end if;

  v_lalei := public.lager_lalei_anzahl(v_row.lager_id);
  if v_row.rolle = 'lagerleitung' and v_lalei <= 1 then
    raise exception 'Die letzte Lagerleitung (Lalei) kann nicht entfernt werden.';
  end if;

  delete from lager_leiter where id = p_lager_leiter_id;
end;
$$;

create or replace function public.leiter_anmeldung_sicher_loeschen(p_anmeldung_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row anmeldungen_leiter%rowtype;
  v_lalei int;
begin
  select * into v_row from anmeldungen_leiter where id = p_anmeldung_id;
  if not found then
    raise exception 'Leiter nicht gefunden.';
  end if;

  if not public.is_lager_leitung(v_row.lager_id) then
    raise exception 'Nur Lagerleitung darf entfernen.';
  end if;

  if v_row.profile_id is not null then
    select count(*)::int into v_lalei
    from lager_leiter ll
    where ll.lager_id = v_row.lager_id
      and ll.profile_id = v_row.profile_id
      and ll.rolle = 'lagerleitung'
      and ll.status = 'bestaetigt';

    if v_lalei > 0 and public.lager_lalei_anzahl(v_row.lager_id) <= 1 then
      raise exception 'Die letzte Lagerleitung (Lalei) kann nicht entfernt werden.';
    end if;

    delete from lager_leiter
    where lager_id = v_row.lager_id and profile_id = v_row.profile_id;
  end if;

  delete from anmeldungen_leiter where id = p_anmeldung_id;
end;
$$;

grant execute on function public.lager_leiter_aus_verein_hinzufuegen(uuid, uuid, uuid, boolean, date, date) to authenticated;
grant execute on function public.leiter_anmeldung_speichern(uuid, text, text, date, text, text, text, date, date) to authenticated;
grant execute on function public.lager_leiter_rolle_setzen(uuid, text) to authenticated;
grant execute on function public.lager_leiter_sicher_entfernen(uuid) to authenticated;
grant execute on function public.leiter_anmeldung_sicher_loeschen(uuid) to authenticated;

-- Bestehende Leiter-Anmeldungen mit Profil verknüpfen (Namen aus Profil nachziehen).
update anmeldungen_leiter al
set
  vorname = coalesce(nullif(trim(p.vorname), ''), al.vorname),
  nachname = coalesce(nullif(trim(p.nachname), ''), al.nachname),
  geburtsdatum = coalesce(p.geburtsdatum, al.geburtsdatum),
  geschlecht = coalesce(p.geschlecht, al.geschlecht),
  ahv_nr = coalesce(p.ahv_nr, al.ahv_nr),
  telefon = coalesce(p.telefon, al.telefon),
  email = coalesce(nullif(trim(p.email), ''), al.email)
from profiles p
where p.id = al.profile_id
  and al.profile_id is not null;
