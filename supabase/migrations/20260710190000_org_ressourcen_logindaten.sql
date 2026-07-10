-- Logindaten: URL zur Seite + E-Mail/Benutzername + Passwort

create or replace function public.list_org_ressourcen(p_organisation_id uuid)
returns table (
  id uuid,
  typ text,
  titel text,
  url text,
  benutzername text,
  passwort text,
  notiz text,
  sichtbarkeit text,
  sortierung int,
  zugewiesene_profile_ids uuid[]
)
language plpgsql
security definer
stable
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Nicht angemeldet';
  end if;

  if not public.is_org_mitglied(p_organisation_id) then
    raise exception 'Kein Zugriff auf diesen Verein';
  end if;

  return query
  select
    r.id,
    r.typ,
    r.titel,
    r.url,
    case when r.typ = 'zugang' then r.benutzername else null end as benutzername,
    case when r.typ = 'zugang' then r.passwort else null end as passwort,
    r.notiz,
    r.sichtbarkeit,
    r.sortierung,
    coalesce(
      (
        select array_agg(z.profile_id order by z.profile_id)
        from org_ressourcen_zugriff z
        where z.ressource_id = r.id
      ),
      '{}'::uuid[]
    ) as zugewiesene_profile_ids
  from org_ressourcen r
  where r.organisation_id = p_organisation_id
    and public.org_ressource_darf_sehen(r.organisation_id, r.sichtbarkeit, r.id)
  order by r.sortierung, r.titel;
end;
$$;

create or replace function public.org_ressource_speichern(
  p_organisation_id uuid,
  p_id uuid default null,
  p_typ text default 'link',
  p_titel text default null,
  p_url text default null,
  p_benutzername text default null,
  p_passwort text default null,
  p_notiz text default null,
  p_sichtbarkeit text default 'alle',
  p_sortierung int default 0,
  p_zugewiesene_profile_ids uuid[] default '{}'::uuid[]
)
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
  if not public.is_org_admin(p_organisation_id) then
    raise exception 'Nur Vereins-Admins dürfen Links und Zugänge verwalten.';
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
