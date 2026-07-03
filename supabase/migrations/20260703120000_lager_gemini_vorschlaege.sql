-- Gemini-Vorschläge pro Lager:
-- - Nur Lagerleitung kann Vorschläge sehen/bearbeiten
-- - Gemini selbst schreibt NICHT direkt in operative Tabellen
-- - Änderungen werden erst per "Annehmen" (RPC) angewendet

create table if not exists lager_ai_vorschlaege (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  organisation_id uuid references organisation (id) on delete set null,
  erstellt_von uuid not null references profiles (id) on delete cascade,
  quelle_prompt text not null default '',
  quelle_dokumente jsonb not null default '[]',
  titel text not null,
  beschreibung text,
  action_type text not null check (action_type in (
    'update_lager',
    'insert_programmblock',
    'insert_tn',
    'insert_leiter'
  )),
  payload jsonb not null default '{}',
  status text not null default 'offen' check (status in ('offen', 'angenommen', 'abgelehnt')),
  entscheidungs_notiz text,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  bearbeitet_at timestamptz,
  bearbeitet_von uuid references profiles (id) on delete set null
);

create index if not exists idx_lager_ai_vorschlaege_lager_created
  on lager_ai_vorschlaege (lager_id, created_at desc);

alter table lager_ai_vorschlaege enable row level security;

drop policy if exists "lager_ai_vorschlaege: lagerleitung lesen" on lager_ai_vorschlaege;
drop policy if exists "lager_ai_vorschlaege: lagerleitung erstellen" on lager_ai_vorschlaege;
drop policy if exists "lager_ai_vorschlaege: lagerleitung update" on lager_ai_vorschlaege;
drop policy if exists "lager_ai_vorschlaege: lagerleitung delete" on lager_ai_vorschlaege;

create policy "lager_ai_vorschlaege: lagerleitung lesen" on lager_ai_vorschlaege
  for select to authenticated
  using (public.is_lager_leitung(lager_id));

create policy "lager_ai_vorschlaege: lagerleitung erstellen" on lager_ai_vorschlaege
  for insert to authenticated
  with check (public.is_lager_leitung(lager_id) and erstellt_von = auth.uid());

create policy "lager_ai_vorschlaege: lagerleitung update" on lager_ai_vorschlaege
  for update to authenticated
  using (public.is_lager_leitung(lager_id))
  with check (public.is_lager_leitung(lager_id));

create policy "lager_ai_vorschlaege: lagerleitung delete" on lager_ai_vorschlaege
  for delete to authenticated
  using (public.is_lager_leitung(lager_id));

create or replace function public.lager_ai_vorschlag_ablehnen(
  p_vorschlag_id uuid,
  p_notiz text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager_id uuid;
begin
  select lager_id into v_lager_id
  from lager_ai_vorschlaege
  where id = p_vorschlag_id;

  if v_lager_id is null then
    raise exception 'Vorschlag nicht gefunden.';
  end if;
  if not public.is_lager_leitung(v_lager_id) then
    raise exception 'Nur Lagerleitung darf Vorschläge bearbeiten.';
  end if;

  update lager_ai_vorschlaege
  set status = 'abgelehnt',
      entscheidungs_notiz = coalesce(p_notiz, entscheidungs_notiz),
      bearbeitet_at = now(),
      bearbeitet_von = auth.uid(),
      updated_at = now(),
      last_error = null
  where id = p_vorschlag_id
    and status = 'offen';
end;
$$;

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
grant execute on function public.lager_ai_vorschlag_ablehnen(uuid, text) to authenticated;
