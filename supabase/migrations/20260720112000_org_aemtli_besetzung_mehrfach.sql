-- org_aemtli_besetzung war bisher 1 Person pro Ämtli (unique
-- organisation_id+aemtli_id). Jetzt: mehrere Personen pro Ämtli UND
-- eine Person kann mehrere Ämtli haben -- echte n:m-Zuteilung.
delete from org_aemtli_besetzung where profile_id is null;

alter table org_aemtli_besetzung drop constraint if exists org_aemtli_besetzung_organisation_id_aemtli_id_key;
alter table org_aemtli_besetzung alter column profile_id set not null;
alter table org_aemtli_besetzung add constraint org_aemtli_besetzung_org_aemtli_profile_key unique (organisation_id, aemtli_id, profile_id);

-- Hinzufügen/Entfernen als klare RPCs statt Upsert auf einen Einzelwert.
create or replace function public.org_aemtli_besetzung_hinzufuegen(p_organisation_id uuid, p_aemtli_id uuid, p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from organisation_mitglieder om
    where om.organisation_id = p_organisation_id and om.profile_id = auth.uid() and om.status = 'mitglied'
  ) then
    raise exception 'Keine Berechtigung.';
  end if;

  insert into org_aemtli_besetzung (organisation_id, aemtli_id, profile_id, updated_by)
  values (p_organisation_id, p_aemtli_id, p_profile_id, auth.uid())
  on conflict (organisation_id, aemtli_id, profile_id) do nothing;
end;
$$;

create or replace function public.org_aemtli_besetzung_entfernen(p_organisation_id uuid, p_aemtli_id uuid, p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from organisation_mitglieder om
    where om.organisation_id = p_organisation_id and om.profile_id = auth.uid() and om.status = 'mitglied'
  ) then
    raise exception 'Keine Berechtigung.';
  end if;

  delete from org_aemtli_besetzung
  where organisation_id = p_organisation_id and aemtli_id = p_aemtli_id and profile_id = p_profile_id;
end;
$$;

grant execute on function public.org_aemtli_besetzung_hinzufuegen(uuid, uuid, uuid) to authenticated;
grant execute on function public.org_aemtli_besetzung_entfernen(uuid, uuid, uuid) to authenticated;

-- resolve_org_aemtli_besetzung liefert jetzt beliebig viele Zeilen pro
-- Ämtli (0 = niemand zugeteilt). Fallback (falls für ein Ämtli noch nie
-- jemand auf Org-Ebene gesetzt wurde) kommt neu aus leiter_rollen des
-- zuletzt vergangenen Lagers -- das unterstützt von Natur aus mehrere
-- Personen pro Ämtli, statt der alten Einzelwert-Spalte in aemtli_zuweisungen.
create or replace function public.resolve_org_aemtli_besetzung(p_organisation_id uuid)
returns table (
  aemtli_id uuid,
  aemtli_name text,
  profile_id uuid,
  vorname text,
  nachname text,
  email text,
  quelle text
)
language sql
security definer
stable
set search_path = public
as $$
  with letztes_lager as (
    select id from lager
    where organisation_id = p_organisation_id
      and end_datum is not null and end_datum < current_date
    order by end_datum desc
    limit 1
  ),
  org_zeilen as (
    select b.aemtli_id, b.profile_id
    from org_aemtli_besetzung b
    where b.organisation_id = p_organisation_id
  ),
  fallback_zeilen as (
    select distinct lr.aemtli_id, al.profile_id
    from letztes_lager ll
    join anmeldungen_leiter al on al.lager_id = ll.id and al.profile_id is not null
    join leiter_rollen lr on lr.anmeldung_leiter_id = al.id
  ),
  zeilen as (
    select aemtli_id, profile_id, 'organisation'::text as quelle from org_zeilen
    union all
    select f.aemtli_id, f.profile_id, 'letztes_lager'::text as quelle
    from fallback_zeilen f
    where not exists (select 1 from org_zeilen oz where oz.aemtli_id = f.aemtli_id)
  )
  select
    a.id as aemtli_id,
    a.name as aemtli_name,
    z.profile_id,
    p.vorname, p.nachname, p.email,
    coalesce(z.quelle, 'keine') as quelle
  from aemtli a
  left join zeilen z on z.aemtli_id = a.id
  left join profiles p on p.id = z.profile_id
  where a.aktiv
  order by a.name, p.nachname nulls last;
$$;

grant execute on function public.resolve_org_aemtli_besetzung(uuid) to authenticated;

-- Lager -> Organisation: on conflict jetzt gegen den 3er-Unique-Key.
create or replace function public.sync_leiter_rolle_zu_org()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager_id uuid;
  v_profile_id uuid;
  v_organisation_id uuid;
begin
  select al.lager_id, al.profile_id into v_lager_id, v_profile_id
  from anmeldungen_leiter al
  where al.id = new.anmeldung_leiter_id;

  if v_profile_id is null or v_lager_id is null then
    return new;
  end if;

  select l.organisation_id into v_organisation_id from lager l where l.id = v_lager_id;
  if v_organisation_id is null then
    return new;
  end if;

  insert into org_aemtli_besetzung (organisation_id, aemtli_id, profile_id, updated_by)
  values (v_organisation_id, new.aemtli_id, v_profile_id, auth.uid())
  on conflict (organisation_id, aemtli_id, profile_id) do nothing;

  return new;
end;
$$;

-- Organisation -> Lager: pro betroffener Org-Zeile (jetzt 1 Zeile = 1
-- Person) weiterhin in aemtli_zuweisungen (als Referenzwert) und
-- leiter_rollen (echte Mehrfachzuteilung) übernehmen.
create or replace function public.kaskadiere_aemtli_besetzung()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  l record;
  v_anmeldung_leiter_id uuid;
begin
  for l in
    select id from lager
    where organisation_id = new.organisation_id
      and (end_datum is null or end_datum >= current_date)
  loop
    insert into aemtli_zuweisungen (lager_id, aemtli_id, profile_id, status)
    values (l.id, new.aemtli_id, new.profile_id, 'offen')
    on conflict (lager_id, aemtli_id) do update set profile_id = excluded.profile_id
      where aemtli_zuweisungen.profile_id is distinct from excluded.profile_id;

    select al.id into v_anmeldung_leiter_id
    from anmeldungen_leiter al
    where al.lager_id = l.id and al.profile_id = new.profile_id and al.status = 'bestaetigt'
    limit 1;

    if v_anmeldung_leiter_id is not null then
      insert into leiter_rollen (anmeldung_leiter_id, aemtli_id)
      values (v_anmeldung_leiter_id, new.aemtli_id)
      on conflict (anmeldung_leiter_id, aemtli_id) do nothing;
    end if;
  end loop;
  return new;
end;
$$;
