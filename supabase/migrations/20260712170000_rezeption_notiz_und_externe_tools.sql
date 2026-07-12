-- Rezeption: pro Kind eine Notiz (z.B. was Eltern am Anreisetag noch
-- mitgeteilt haben) und ein Ankunft-Häkchen.
alter table anmeldungen_tn add column if not exists rezeption_notiz text;
alter table anmeldungen_tn add column if not exists angekommen boolean not null default false;

-- Externe-Tools-Block auf dem Dashboard soll von Admin UND Lalei
-- bearbeitbar sein, nicht nur von Vereins-Admins.
create or replace function public.ist_org_admin_oder_lalei(p_organisation_id uuid)
returns boolean
language sql
stable security definer
set search_path = public
as $$
  select
    public.is_org_admin(p_organisation_id)
    or exists (
      select 1 from lager_leiter ll
      join lager l on l.id = ll.lager_id
      where l.organisation_id = p_organisation_id
        and ll.profile_id = auth.uid()
        and ll.rolle = 'lagerleitung'
        and ll.status = 'bestaetigt'
    );
$$;

create or replace function public.org_ressource_speichern(p_organisation_id uuid, p_id uuid DEFAULT NULL::uuid, p_typ text DEFAULT 'link'::text, p_titel text DEFAULT NULL::text, p_url text DEFAULT NULL::text, p_benutzername text DEFAULT NULL::text, p_passwort text DEFAULT NULL::text, p_notiz text DEFAULT NULL::text, p_sichtbarkeit text DEFAULT 'alle'::text, p_sortierung integer DEFAULT 0, p_zugewiesene_profile_ids uuid[] DEFAULT '{}'::uuid[])
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_titel text := nullif(trim(p_titel), '');
  v_pid uuid;
begin
  if not public.ist_org_admin_oder_lalei(p_organisation_id) then
    raise exception 'Nur Vereins-Admins oder Lalei dürfen Links und Zugänge verwalten.';
  end if;

  if v_titel is null then
    raise exception 'Titel ist Pflicht.';
  end if;

  if p_typ not in ('link', 'zugang') then
    raise exception 'Ungültiger Typ.';
  end if;

  if p_sichtbarkeit not in ('alle', 'leitung', 'admin', 'ausgewaehlt') then
    raise exception 'Ungültige Sichtbarkeit.';
  end if;

  if nullif(trim(p_url), '') is null then
    raise exception 'URL / Seiten-Link ist Pflicht.';
  end if;

  if p_typ = 'zugang' and nullif(trim(p_benutzername), '') is null then
    raise exception 'E-Mail oder Benutzername ist für Logindaten Pflicht.';
  end if;

  if p_typ = 'zugang' and p_id is null and nullif(trim(p_passwort), '') is null then
    raise exception 'Passwort ist beim Anlegen von Logindaten Pflicht.';
  end if;

  if p_id is null then
    insert into org_ressourcen (
      organisation_id, typ, titel, url, benutzername, passwort, notiz,
      sichtbarkeit, sortierung, created_by
    )
    values (
      p_organisation_id,
      p_typ,
      v_titel,
      nullif(trim(p_url), ''),
      case when p_typ = 'zugang' then nullif(trim(p_benutzername), '') else null end,
      case when p_typ = 'zugang' then nullif(trim(p_passwort), '') else null end,
      nullif(trim(p_notiz), ''),
      p_sichtbarkeit,
      coalesce(p_sortierung, 0),
      auth.uid()
    )
    returning id into v_id;
  else
    update org_ressourcen
    set
      typ = p_typ,
      titel = v_titel,
      url = nullif(trim(p_url), ''),
      benutzername = case
        when p_typ = 'zugang' then coalesce(nullif(trim(p_benutzername), ''), benutzername)
        else null
      end,
      passwort = case
        when p_typ = 'zugang' then coalesce(nullif(trim(p_passwort), ''), passwort)
        else null
      end,
      notiz = nullif(trim(p_notiz), ''),
      sichtbarkeit = p_sichtbarkeit,
      sortierung = coalesce(p_sortierung, sortierung),
      updated_at = now()
    where id = p_id
      and organisation_id = p_organisation_id
    returning id into v_id;

    if v_id is null then
      raise exception 'Eintrag nicht gefunden.';
    end if;
  end if;

  delete from org_ressourcen_zugriff where ressource_id = v_id;

  if p_sichtbarkeit = 'ausgewaehlt' then
    foreach v_pid in array coalesce(p_zugewiesene_profile_ids, '{}'::uuid[])
    loop
      if v_pid is null then continue; end if;
      if not exists (
        select 1 from organisation_mitglieder om
        where om.organisation_id = p_organisation_id
          and om.profile_id = v_pid
          and om.status = 'mitglied'
      ) then
        continue;
      end if;
      insert into org_ressourcen_zugriff (ressource_id, profile_id)
      values (v_id, v_pid)
      on conflict do nothing;
    end loop;
  end if;

  return v_id;
end;
$$;

create or replace function public.org_ressource_loeschen(p_organisation_id uuid, p_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.ist_org_admin_oder_lalei(p_organisation_id) then
    raise exception 'Nur Vereins-Admins oder Lalei dürfen Links und Zugänge verwalten.';
  end if;
  delete from org_ressourcen where id = p_id and organisation_id = p_organisation_id;
end;
$$;
