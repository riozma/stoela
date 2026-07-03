-- Gemini Vorschläge: zusätzliche Actions für Alltagsszenarien
-- (Programm aktualisieren/löschen, TN/Leiter aktualisieren, Ämtli zuweisen, Todos erstellen/ändern)

alter table lager_ai_vorschlaege
  drop constraint if exists lager_ai_vorschlaege_action_type_check;

alter table lager_ai_vorschlaege
  add constraint lager_ai_vorschlaege_action_type_check
  check (action_type in (
    'update_lager',
    'insert_programmblock',
    'update_programmblock',
    'delete_programmblock',
    'insert_tn',
    'update_tn',
    'insert_leiter',
    'update_leiter',
    'assign_leiter_aemtli',
    'create_lager_todo',
    'update_lager_todo'
  ));

create or replace function public.lager_ai_vorschlag_annehmen(
  p_vorschlag_id uuid,
  p_payload_override jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row lager_ai_vorschlaege%rowtype;
  v_payload jsonb;
  v_result jsonb := '{}'::jsonb;
  v_code text;
  v_vorname text;
  v_nachname text;
  v_geburtsdatum date;
  v_notfallkontakt text;
  v_eltern_email text;
  v_id uuid;
  v_titel text;
  v_aemtli_id uuid;
  v_aemtli_name text;
  v_anmeldung_id uuid;
begin
  select * into v_row
  from lager_ai_vorschlaege
  where id = p_vorschlag_id
  for update;

  if v_row.id is null then
    raise exception 'Vorschlag nicht gefunden.';
  end if;
  if not public.is_lager_leitung(v_row.lager_id) then
    raise exception 'Nur Lagerleitung darf Vorschläge annehmen.';
  end if;
  if v_row.status <> 'offen' then
    raise exception 'Vorschlag wurde bereits bearbeitet.';
  end if;

  v_payload := coalesce(p_payload_override, v_row.payload, '{}'::jsonb);

  if v_row.action_type = 'update_lager' then
    update lager
    set
      name = coalesce(nullif(v_payload->>'name', ''), name),
      ort = coalesce(v_payload->>'ort', ort),
      start_datum = coalesce((nullif(v_payload->>'start_datum', ''))::date, start_datum),
      end_datum = coalesce((nullif(v_payload->>'end_datum', ''))::date, end_datum),
      status = case
        when coalesce(v_payload->>'status', '') in ('planung', 'anmeldung_offen', 'laufend', 'abgeschlossen', 'archiviert')
          then v_payload->>'status'
        else status
      end
    where id = v_row.lager_id;

    v_result := jsonb_build_object(
      'action_type', v_row.action_type,
      'lager_id', v_row.lager_id
    );

  elsif v_row.action_type = 'insert_programmblock' then
    v_code := upper(coalesce(v_payload->>'code', 'LP'));
    if v_code not in ('LP', 'LS', 'LA', 'ES') then
      raise exception 'Ungültiger code für Programmbock: %', v_code;
    end if;

    insert into programmbloecke (
      lager_id, code, nummer, titel, tag, start_zeit, end_zeit, ort,
      verantwortlich, geschichte, sicherheitsueberlegungen, programmabschnitt, material, notizen, quelle
    ) values (
      v_row.lager_id,
      v_code,
      nullif(v_payload->>'nummer', ''),
      coalesce(nullif(v_payload->>'titel', ''), 'Neuer Programmpunkt'),
      (nullif(v_payload->>'tag', ''))::date,
      (nullif(v_payload->>'start_zeit', ''))::timestamptz,
      (nullif(v_payload->>'end_zeit', ''))::timestamptz,
      nullif(v_payload->>'ort', ''),
      nullif(v_payload->>'verantwortlich', ''),
      nullif(v_payload->>'geschichte', ''),
      nullif(v_payload->>'sicherheitsueberlegungen', ''),
      coalesce(v_payload->'programmabschnitt', '[]'::jsonb),
      coalesce(v_payload->'material', '[]'::jsonb),
      nullif(v_payload->>'notizen', ''),
      'manuell'
    )
    returning jsonb_build_object(
      'action_type', v_row.action_type,
      'id', id,
      'titel', titel,
      'tag', tag
    ) into v_result;

  elsif v_row.action_type = 'update_programmblock' then
    v_id := (nullif(v_payload->>'id', ''))::uuid;
    if v_id is null then
      raise exception 'update_programmblock braucht payload.id';
    end if;

    update programmbloecke
    set
      code = case
        when upper(coalesce(v_payload->>'code', '')) in ('LP', 'LS', 'LA', 'ES') then upper(v_payload->>'code')
        else code
      end,
      nummer = coalesce(v_payload->>'nummer', nummer),
      titel = coalesce(nullif(v_payload->>'titel', ''), titel),
      tag = coalesce((nullif(v_payload->>'tag', ''))::date, tag),
      start_zeit = coalesce((nullif(v_payload->>'start_zeit', ''))::timestamptz, start_zeit),
      end_zeit = coalesce((nullif(v_payload->>'end_zeit', ''))::timestamptz, end_zeit),
      ort = coalesce(v_payload->>'ort', ort),
      verantwortlich = coalesce(v_payload->>'verantwortlich', verantwortlich),
      geschichte = coalesce(v_payload->>'geschichte', geschichte),
      sicherheitsueberlegungen = coalesce(v_payload->>'sicherheitsueberlegungen', sicherheitsueberlegungen),
      programmabschnitt = coalesce(v_payload->'programmabschnitt', programmabschnitt),
      material = coalesce(v_payload->'material', material),
      notizen = coalesce(v_payload->>'notizen', notizen)
    where id = v_id
      and lager_id = v_row.lager_id
    returning titel into v_titel;

    if v_titel is null then
      raise exception 'Programmblock nicht gefunden oder kein Zugriff.';
    end if;

    v_result := jsonb_build_object(
      'action_type', v_row.action_type,
      'id', v_id,
      'titel', v_titel
    );

  elsif v_row.action_type = 'delete_programmblock' then
    v_id := (nullif(v_payload->>'id', ''))::uuid;
    if v_id is null then
      raise exception 'delete_programmblock braucht payload.id';
    end if;

    delete from programmbloecke
    where id = v_id
      and lager_id = v_row.lager_id
    returning titel into v_titel;

    if v_titel is null then
      raise exception 'Programmblock nicht gefunden oder bereits gelöscht.';
    end if;

    v_result := jsonb_build_object(
      'action_type', v_row.action_type,
      'id', v_id,
      'titel', v_titel
    );

  elsif v_row.action_type = 'insert_tn' then
    v_vorname := nullif(v_payload->>'vorname', '');
    v_nachname := nullif(v_payload->>'nachname', '');
    v_geburtsdatum := (nullif(v_payload->>'geburtsdatum', ''))::date;
    v_notfallkontakt := nullif(v_payload->>'notfallkontakt', '');
    v_eltern_email := nullif(v_payload->>'eltern_email', '');

    if v_vorname is null or v_nachname is null or v_geburtsdatum is null or v_notfallkontakt is null or v_eltern_email is null then
      raise exception 'Für TN sind vorname, nachname, geburtsdatum, notfallkontakt und eltern_email erforderlich.';
    end if;

    insert into anmeldungen_tn (
      lager_id, vorname, nachname, geburtsdatum, geschlecht, ahv_nr,
      notfallkontakt, eltern_email, rolle, status
    ) values (
      v_row.lager_id,
      v_vorname,
      v_nachname,
      v_geburtsdatum,
      nullif(v_payload->>'geschlecht', ''),
      nullif(v_payload->>'ahv_nr', ''),
      v_notfallkontakt,
      v_eltern_email,
      case when coalesce(v_payload->>'rolle', '') in ('TN', 'HL') then v_payload->>'rolle' else 'TN' end,
      case when coalesce(v_payload->>'status', '') in ('angemeldet', 'bestaetigt', 'abgesagt', 'warteliste') then v_payload->>'status' else 'angemeldet' end
    )
    returning jsonb_build_object(
      'action_type', v_row.action_type,
      'id', id,
      'name', vorname || ' ' || nachname
    ) into v_result;

  elsif v_row.action_type = 'update_tn' then
    v_id := (nullif(v_payload->>'id', ''))::uuid;
    if v_id is null then
      raise exception 'update_tn braucht payload.id';
    end if;

    update anmeldungen_tn
    set
      vorname = coalesce(nullif(v_payload->>'vorname', ''), vorname),
      nachname = coalesce(nullif(v_payload->>'nachname', ''), nachname),
      geburtsdatum = coalesce((nullif(v_payload->>'geburtsdatum', ''))::date, geburtsdatum),
      geschlecht = case when coalesce(v_payload->>'geschlecht', '') in ('m', 'w', 'd') then v_payload->>'geschlecht' else geschlecht end,
      ahv_nr = coalesce(v_payload->>'ahv_nr', ahv_nr),
      notfallkontakt = coalesce(v_payload->>'notfallkontakt', notfallkontakt),
      eltern_email = coalesce(v_payload->>'eltern_email', eltern_email),
      rolle = case when coalesce(v_payload->>'rolle', '') in ('TN', 'HL') then v_payload->>'rolle' else rolle end,
      status = case when coalesce(v_payload->>'status', '') in ('angemeldet', 'bestaetigt', 'abgesagt', 'warteliste') then v_payload->>'status' else status end
    where id = v_id
      and lager_id = v_row.lager_id
    returning vorname || ' ' || nachname into v_titel;

    if v_titel is null then
      raise exception 'TN nicht gefunden.';
    end if;

    v_result := jsonb_build_object('action_type', v_row.action_type, 'id', v_id, 'name', v_titel);

  elsif v_row.action_type = 'insert_leiter' then
    v_vorname := nullif(v_payload->>'vorname', '');
    v_nachname := nullif(v_payload->>'nachname', '');

    if v_vorname is null or v_nachname is null then
      raise exception 'Für Leiter sind vorname und nachname erforderlich.';
    end if;

    insert into anmeldungen_leiter (
      lager_id, profile_id, vorname, nachname, email, telefon, geburtsdatum, geschlecht,
      ahv_nr, anwesend_von, anwesend_bis, status, anmeldung_art, bestaetigen_bis, von_vorjahr, von_lager_id
    ) values (
      v_row.lager_id,
      nullif(v_payload->>'profile_id', '')::uuid,
      v_vorname,
      v_nachname,
      nullif(v_payload->>'email', ''),
      nullif(v_payload->>'telefon', ''),
      (nullif(v_payload->>'geburtsdatum', ''))::date,
      nullif(v_payload->>'geschlecht', ''),
      nullif(v_payload->>'ahv_nr', ''),
      (nullif(v_payload->>'anwesend_von', ''))::date,
      (nullif(v_payload->>'anwesend_bis', ''))::date,
      case when coalesce(v_payload->>'status', '') in ('angefragt', 'angemeldet', 'bestaetigt', 'abgelehnt', 'abgesagt')
        then v_payload->>'status'
        else 'angemeldet'
      end,
      case when coalesce(v_payload->>'anmeldung_art', '') in ('provisorisch', 'fix')
        then v_payload->>'anmeldung_art'
        else 'provisorisch'
      end,
      (nullif(v_payload->>'bestaetigen_bis', ''))::date,
      coalesce((v_payload->>'von_vorjahr')::boolean, false),
      nullif(v_payload->>'von_lager_id', '')::uuid
    )
    returning jsonb_build_object(
      'action_type', v_row.action_type,
      'id', id,
      'name', vorname || ' ' || nachname
    ) into v_result;

  elsif v_row.action_type = 'update_leiter' then
    v_id := (nullif(v_payload->>'id', ''))::uuid;
    if v_id is null then
      raise exception 'update_leiter braucht payload.id';
    end if;

    update anmeldungen_leiter
    set
      profile_id = coalesce((nullif(v_payload->>'profile_id', ''))::uuid, profile_id),
      vorname = coalesce(nullif(v_payload->>'vorname', ''), vorname),
      nachname = coalesce(nullif(v_payload->>'nachname', ''), nachname),
      email = coalesce(v_payload->>'email', email),
      telefon = coalesce(v_payload->>'telefon', telefon),
      geburtsdatum = coalesce((nullif(v_payload->>'geburtsdatum', ''))::date, geburtsdatum),
      geschlecht = case when coalesce(v_payload->>'geschlecht', '') in ('m', 'w', 'd') then v_payload->>'geschlecht' else geschlecht end,
      ahv_nr = coalesce(v_payload->>'ahv_nr', ahv_nr),
      anwesend_von = coalesce((nullif(v_payload->>'anwesend_von', ''))::date, anwesend_von),
      anwesend_bis = coalesce((nullif(v_payload->>'anwesend_bis', ''))::date, anwesend_bis),
      status = case when coalesce(v_payload->>'status', '') in ('angefragt', 'angemeldet', 'bestaetigt', 'abgelehnt', 'abgesagt') then v_payload->>'status' else status end,
      anmeldung_art = case when coalesce(v_payload->>'anmeldung_art', '') in ('provisorisch', 'fix') then v_payload->>'anmeldung_art' else anmeldung_art end,
      bestaetigen_bis = coalesce((nullif(v_payload->>'bestaetigen_bis', ''))::date, bestaetigen_bis)
    where id = v_id
      and lager_id = v_row.lager_id
    returning vorname || ' ' || nachname into v_titel;

    if v_titel is null then
      raise exception 'Leiter-Anmeldung nicht gefunden.';
    end if;

    v_result := jsonb_build_object('action_type', v_row.action_type, 'id', v_id, 'name', v_titel);

  elsif v_row.action_type = 'assign_leiter_aemtli' then
    v_anmeldung_id := (nullif(v_payload->>'anmeldung_leiter_id', ''))::uuid;
    if v_anmeldung_id is null then
      raise exception 'assign_leiter_aemtli braucht payload.anmeldung_leiter_id';
    end if;
    if not exists (
      select 1 from anmeldungen_leiter al
      where al.id = v_anmeldung_id and al.lager_id = v_row.lager_id
    ) then
      raise exception 'Leiter-Anmeldung gehört nicht zu diesem Lager.';
    end if;

    v_aemtli_id := (nullif(v_payload->>'aemtli_id', ''))::uuid;
    v_aemtli_name := nullif(v_payload->>'aemtli_name', '');

    if v_aemtli_id is null and v_aemtli_name is not null then
      select id into v_aemtli_id
      from aemtli
      where lower(name) = lower(v_aemtli_name)
      limit 1;

      if v_aemtli_id is null then
        insert into aemtli (name)
        values (v_aemtli_name)
        on conflict (name) do update set name = excluded.name
        returning id into v_aemtli_id;
      end if;
    end if;

    if v_aemtli_id is null then
      raise exception 'Kein gültiges Ämtli angegeben (aemtli_id oder aemtli_name).';
    end if;

    insert into leiter_rollen (anmeldung_leiter_id, aemtli_id)
    values (v_anmeldung_id, v_aemtli_id)
    on conflict (anmeldung_leiter_id, aemtli_id) do nothing;

    v_result := jsonb_build_object(
      'action_type', v_row.action_type,
      'anmeldung_leiter_id', v_anmeldung_id,
      'aemtli_id', v_aemtli_id
    );

  elsif v_row.action_type = 'create_lager_todo' then
    insert into lager_todos (
      lager_id, titel, beschreibung, kategorie, zustaendig, aemtli_name, faellig_am, erledigt, sortierung
    ) values (
      v_row.lager_id,
      coalesce(nullif(v_payload->>'titel', ''), 'Neue Aufgabe'),
      nullif(v_payload->>'beschreibung', ''),
      coalesce(nullif(v_payload->>'kategorie', ''), 'vorbereitung'),
      coalesce(nullif(v_payload->>'zustaendig', ''), 'lalei'),
      nullif(v_payload->>'aemtli_name', ''),
      (nullif(v_payload->>'faellig_am', ''))::date,
      coalesce((v_payload->>'erledigt')::boolean, false),
      coalesce((v_payload->>'sortierung')::int, 0)
    )
    returning jsonb_build_object(
      'action_type', v_row.action_type,
      'id', id,
      'titel', titel
    ) into v_result;

  elsif v_row.action_type = 'update_lager_todo' then
    v_id := (nullif(v_payload->>'id', ''))::uuid;
    if v_id is null then
      raise exception 'update_lager_todo braucht payload.id';
    end if;

    update lager_todos
    set
      titel = coalesce(nullif(v_payload->>'titel', ''), titel),
      beschreibung = coalesce(v_payload->>'beschreibung', beschreibung),
      kategorie = coalesce(nullif(v_payload->>'kategorie', ''), kategorie),
      zustaendig = coalesce(nullif(v_payload->>'zustaendig', ''), zustaendig),
      aemtli_name = coalesce(v_payload->>'aemtli_name', aemtli_name),
      faellig_am = coalesce((nullif(v_payload->>'faellig_am', ''))::date, faellig_am),
      erledigt = coalesce((v_payload->>'erledigt')::boolean, erledigt),
      erledigt_am = case
        when coalesce((v_payload->>'erledigt')::boolean, erledigt) = true then coalesce(erledigt_am, now())
        when coalesce((v_payload->>'erledigt')::boolean, erledigt) = false then null
        else erledigt_am
      end,
      sortierung = coalesce((v_payload->>'sortierung')::int, sortierung)
    where id = v_id
      and lager_id = v_row.lager_id
    returning titel into v_titel;

    if v_titel is null then
      raise exception 'Todo nicht gefunden.';
    end if;

    v_result := jsonb_build_object('action_type', v_row.action_type, 'id', v_id, 'titel', v_titel);

  else
    raise exception 'Unbekannter action_type: %', v_row.action_type;
  end if;

  update lager_ai_vorschlaege
  set
    status = 'angenommen',
    payload = v_payload,
    last_error = null,
    bearbeitet_at = now(),
    bearbeitet_von = auth.uid(),
    updated_at = now()
  where id = v_row.id;

  return v_result;
exception
  when others then
    update lager_ai_vorschlaege
    set last_error = sqlerrm,
        updated_at = now()
    where id = p_vorschlag_id;
    raise;
end;
$$;

grant execute on function public.lager_ai_vorschlag_annehmen(uuid, jsonb) to authenticated;
