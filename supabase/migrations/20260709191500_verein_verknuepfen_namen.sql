-- Beim Verknüpfen einer Beitrittsanfrage mit manuellem Leiter:
-- Name/Kontakt aus org_personen ins Login-Profil übernehmen.

create or replace function public.verein_beitrittsanfrage_entscheiden(
  p_organisation_id uuid,
  p_profile_id uuid,
  p_entscheidung text,
  p_org_person_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_person org_personen%rowtype;
begin
  if not public.is_org_leitung(p_organisation_id) then
    raise exception 'Nur Vereinsleitung darf Beitritte entscheiden.';
  end if;

  if p_entscheidung = 'genehmigen' then
    insert into organisation_mitglieder (
      organisation_id, profile_id, rolle, status, angefragt_am, bestaetigt_am, bestaetigt_von
    ) values (
      p_organisation_id, p_profile_id, 'mitglied', 'mitglied', now(), now(), auth.uid()
    )
    on conflict (organisation_id, profile_id) do update set
      status = 'mitglied',
      bestaetigt_am = now(),
      bestaetigt_von = auth.uid();

    if p_org_person_id is not null then
      select * into v_person
      from org_personen
      where id = p_org_person_id
        and organisation_id = p_organisation_id
        and aktiv = true;

      if v_person.id is null then
        raise exception 'Manueller Leiter nicht gefunden.';
      end if;

      update profiles
      set
        vorname = coalesce(nullif(trim(v_person.vorname), ''), vorname),
        nachname = coalesce(nullif(trim(v_person.nachname), ''), nachname),
        telefon = coalesce(nullif(trim(v_person.telefon), ''), telefon)
      where id = p_profile_id;

      update org_personen
      set
        profile_id = p_profile_id,
        email = coalesce(
          nullif(trim(v_person.email), ''),
          (select email from profiles where id = p_profile_id)
        )
      where id = p_org_person_id
        and organisation_id = p_organisation_id;
    else
      select email into v_email from profiles where id = p_profile_id;
      if v_email is not null then
        select * into v_person
        from org_personen
        where organisation_id = p_organisation_id
          and profile_id is null
          and email is not null
          and lower(email) = lower(v_email)
          and aktiv = true
        limit 1;

        if v_person.id is not null then
          update profiles
          set
            vorname = coalesce(nullif(trim(v_person.vorname), ''), vorname),
            nachname = coalesce(nullif(trim(v_person.nachname), ''), nachname),
            telefon = coalesce(nullif(trim(v_person.telefon), ''), telefon)
          where id = p_profile_id;

          update org_personen
          set profile_id = p_profile_id
          where id = v_person.id;
        end if;
      end if;
    end if;
  elsif p_entscheidung = 'ablehnen' then
    insert into organisation_mitglieder (
      organisation_id, profile_id, rolle, status, angefragt_am, bestaetigt_von
    ) values (
      p_organisation_id, p_profile_id, 'mitglied', 'abgelehnt', now(), auth.uid()
    )
    on conflict (organisation_id, profile_id) do update set
      status = 'abgelehnt',
      bestaetigt_von = auth.uid();
  else
    raise exception 'Ungültige Entscheidung.';
  end if;
end;
$$;

-- Bestehende Verknüpfungen reparieren: manuelle Namen ins Profil übernehmen.
update profiles p
set
  vorname = coalesce(nullif(trim(op.vorname), ''), p.vorname),
  nachname = coalesce(nullif(trim(op.nachname), ''), p.nachname),
  telefon = coalesce(nullif(trim(op.telefon), ''), p.telefon)
from org_personen op
where op.profile_id = p.id
  and op.aktiv = true
  and (
    nullif(trim(op.vorname), '') is not null
    or nullif(trim(op.nachname), '') is not null
    or nullif(trim(op.telefon), '') is not null
  );
