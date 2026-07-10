-- Öffentliche TN-Anmeldung atomar speichern.
-- Direkte INSERT ... RETURNING-Abfragen scheitern für anon an den SELECT-RLS-Policies.

create or replace function public.tn_anmeldung_absenden(
  p_lager_id uuid,
  p_eltern jsonb,
  p_kinder jsonb
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_kontakt_id uuid;
  v_kind jsonb;
  v_tn_id uuid;
  v_ids jsonb := '[]'::jsonb;
  v_nr int := 0;
begin
  if not public.lager_erlaubt_tn_anmeldung(p_lager_id) then
    raise exception 'Die TN-Anmeldung ist für dieses Lager nicht geöffnet.';
  end if;

  if jsonb_typeof(p_kinder) <> 'array' or jsonb_array_length(p_kinder) = 0 then
    raise exception 'Mindestens ein Kind ist erforderlich.';
  end if;

  if nullif(trim(p_eltern->>'eltern_email'), '') is null
    or nullif(trim(p_eltern->>'eltern_vorname'), '') is null
    or nullif(trim(p_eltern->>'eltern_nachname'), '') is null
    or nullif(trim(p_eltern->>'telefon'), '') is null
    or nullif(trim(p_eltern->>'adresse'), '') is null
    or nullif(trim(p_eltern->>'plz'), '') is null
    or nullif(trim(p_eltern->>'ort'), '') is null then
    raise exception 'Elternkontakt ist unvollständig.';
  end if;

  insert into tn_eltern_kontakte (
    lager_id,
    eltern_email,
    eltern_vorname,
    eltern_nachname,
    telefon,
    adresse,
    plz,
    ort,
    aufenthaltsort,
    aufenthaltsort_unbekannt
  )
  values (
    p_lager_id,
    trim(p_eltern->>'eltern_email'),
    trim(p_eltern->>'eltern_vorname'),
    trim(p_eltern->>'eltern_nachname'),
    trim(p_eltern->>'telefon'),
    trim(p_eltern->>'adresse'),
    trim(p_eltern->>'plz'),
    trim(p_eltern->>'ort'),
    nullif(trim(p_eltern->>'aufenthaltsort'), ''),
    coalesce((p_eltern->>'aufenthaltsort_unbekannt')::boolean, false)
  )
  returning id into v_kontakt_id;

  for v_kind in select value from jsonb_array_elements(p_kinder)
  loop
    v_nr := v_nr + 1;

    if nullif(trim(v_kind->>'vorname'), '') is null
      or nullif(trim(v_kind->>'nachname'), '') is null
      or nullif(v_kind->>'geburtsdatum', '') is null
      or nullif(v_kind->>'geschlecht', '') is null
      or nullif(trim(v_kind->>'ahv_nr'), '') is null then
      raise exception 'Angaben für Kind % sind unvollständig.', v_nr;
    end if;

    insert into anmeldungen_tn (
      lager_id,
      vorname,
      nachname,
      geburtsdatum,
      geschlecht,
      ahv_nr,
      allergien,
      essensgewohnheiten,
      essensgewohnheiten_sonstiges,
      medikamente,
      gesundheit_bemerkungen,
      sonstige_info,
      eltern_email,
      eltern_aufenthaltsort,
      notfallkontakt,
      eltern_kontakt_id,
      kind_nr
    )
    values (
      p_lager_id,
      trim(v_kind->>'vorname'),
      trim(v_kind->>'nachname'),
      (v_kind->>'geburtsdatum')::date,
      v_kind->>'geschlecht',
      trim(v_kind->>'ahv_nr'),
      nullif(trim(v_kind->>'allergien'), ''),
      nullif(trim(v_kind->>'essensgewohnheiten'), ''),
      nullif(trim(v_kind->>'essensgewohnheiten_sonstiges'), ''),
      nullif(trim(v_kind->>'medikamente'), ''),
      nullif(trim(v_kind->>'gesundheit_bemerkungen'), ''),
      nullif(trim(v_kind->>'sonstige_info'), ''),
      trim(p_eltern->>'eltern_email'),
      case
        when coalesce((p_eltern->>'aufenthaltsort_unbekannt')::boolean, false)
          then 'Wird später mitgeteilt'
        else nullif(trim(p_eltern->>'aufenthaltsort'), '')
      end,
      trim(p_eltern->>'eltern_vorname') || ' ' || trim(p_eltern->>'eltern_nachname')
        || ' · ' || trim(p_eltern->>'telefon'),
      v_kontakt_id,
      v_nr
    )
    returning id into v_tn_id;

    v_ids := v_ids || jsonb_build_array(jsonb_build_object('index', v_nr - 1, 'id', v_tn_id));
  end loop;

  return json_build_object(
    'eltern_kontakt_id', v_kontakt_id,
    'anmeldungen', v_ids
  );
end;
$$;

revoke all on function public.tn_anmeldung_absenden(uuid, jsonb, jsonb) from public;
grant execute on function public.tn_anmeldung_absenden(uuid, jsonb, jsonb) to anon, authenticated;
