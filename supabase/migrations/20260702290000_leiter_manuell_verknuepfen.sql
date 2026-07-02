-- Manuell erfasste Leiter: nur Name nötig, E-Mail optional.
-- Anfragen können mit manuellem Eintrag verknüpft werden.

alter table anmeldungen_leiter alter column email drop not null;

drop policy if exists "anmeldungen_leiter: insert für Lagerteam" on anmeldungen_leiter;

create policy "anmeldungen_leiter: insert für Lagerteam" on anmeldungen_leiter
  for insert to authenticated
  with check (
    public.can_access_lager(lager_id)
    and (profile_id is null or profile_id = auth.uid())
  );

create or replace function public.leiter_anfrage_bearbeiten(
  p_anmeldung_id uuid,
  p_entscheidung text,
  p_verknuepf_mit uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager_id uuid;
  v_profile_id uuid;
  v_anfrage anmeldungen_leiter%rowtype;
  v_manuell anmeldungen_leiter%rowtype;
begin
  select * into v_anfrage
  from anmeldungen_leiter
  where id = p_anmeldung_id and status = 'angefragt';

  if v_anfrage.id is null then
    raise exception 'Anfrage nicht gefunden oder bereits bearbeitet.';
  end if;

  v_lager_id := v_anfrage.lager_id;
  v_profile_id := v_anfrage.profile_id;

  if not public.is_lager_leitung(v_lager_id) then
    raise exception 'Nur die Lagerleitung darf Leiter-Anfragen bearbeiten.';
  end if;

  if p_entscheidung = 'genehmigen' then
    if v_profile_id is null then
      raise exception 'Anfrage hat kein verknüpftes Profil.';
    end if;

    if p_verknuepf_mit is not null then
      select * into v_manuell
      from anmeldungen_leiter
      where id = p_verknuepf_mit
        and lager_id = v_lager_id
        and profile_id is null
        and status in ('bestaetigt', 'angemeldet');

      if v_manuell.id is null then
        raise exception 'Manueller Eintrag nicht gefunden oder bereits verknüpft.';
      end if;

      update leiter_rollen
      set anmeldung_leiter_id = v_manuell.id
      where anmeldung_leiter_id = v_anfrage.id;

      update gruppen_mitglieder
      set anmeldung_leiter_id = v_manuell.id
      where anmeldung_leiter_id = v_anfrage.id;

      update anmeldungen_leiter set
        profile_id = v_profile_id,
        email = coalesce(v_anfrage.email, email),
        geburtsdatum = coalesce(v_anfrage.geburtsdatum, geburtsdatum),
        geschlecht = coalesce(v_anfrage.geschlecht, geschlecht),
        ahv_nr = coalesce(v_anfrage.ahv_nr, ahv_nr),
        telefon = coalesce(v_anfrage.telefon, telefon),
        anwesend_von = coalesce(v_anfrage.anwesend_von, anwesend_von),
        anwesend_bis = coalesce(v_anfrage.anwesend_bis, anwesend_bis),
        status = 'bestaetigt'
      where id = v_manuell.id;

      delete from anmeldungen_leiter where id = v_anfrage.id;
    else
      update anmeldungen_leiter set status = 'bestaetigt' where id = p_anmeldung_id;
    end if;

    insert into lager_leiter (lager_id, profile_id, rolle, status)
    values (v_lager_id, v_profile_id, 'leiter', 'bestaetigt')
    on conflict (lager_id, profile_id) do update set status = 'bestaetigt';
  elsif p_entscheidung = 'ablehnen' then
    update anmeldungen_leiter set status = 'abgelehnt' where id = p_anmeldung_id;
  else
    raise exception 'Ungültige Entscheidung.';
  end if;
end;
$$;
