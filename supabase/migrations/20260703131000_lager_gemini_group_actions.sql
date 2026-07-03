-- Gemini Assistant: Gruppen-Actions ergänzen
-- - create_gruppe
-- - assign_gruppenmitglied (zuweisen/übertragen)

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
    'update_lager_todo',
    'create_gruppe',
    'assign_gruppenmitglied'
  ));

do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'lager_ai_vorschlag_annehmen'
      and p.pronargs = 2
  )
  and not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'lager_ai_vorschlag_annehmen_base'
      and p.pronargs = 2
  ) then
    alter function public.lager_ai_vorschlag_annehmen(uuid, jsonb)
      rename to lager_ai_vorschlag_annehmen_base;
  end if;
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
  v_gruppe_id uuid;
  v_typ text;
  v_anmeldung_id uuid;
begin
  select * into v_row
  from lager_ai_vorschlaege
  where id = p_vorschlag_id;

  if v_row.id is null then
    raise exception 'Vorschlag nicht gefunden.';
  end if;

  if v_row.action_type not in ('create_gruppe', 'assign_gruppenmitglied') then
    return public.lager_ai_vorschlag_annehmen_base(p_vorschlag_id, p_payload_override);
  end if;

  select * into v_row
  from lager_ai_vorschlaege
  where id = p_vorschlag_id
  for update;

  if not public.is_lager_leitung(v_row.lager_id) then
    raise exception 'Nur Lagerleitung darf Vorschläge annehmen.';
  end if;
  if v_row.status <> 'offen' then
    raise exception 'Vorschlag wurde bereits bearbeitet.';
  end if;

  v_payload := coalesce(p_payload_override, v_row.payload, '{}'::jsonb);

  if v_row.action_type = 'create_gruppe' then
    insert into lagergruppen (lager_id, name)
    values (
      v_row.lager_id,
      coalesce(nullif(v_payload->>'name', ''), 'Neue Gruppe')
    )
    returning id into v_gruppe_id;

    v_result := jsonb_build_object(
      'action_type', v_row.action_type,
      'id', v_gruppe_id
    );

  elsif v_row.action_type = 'assign_gruppenmitglied' then
    v_gruppe_id := (nullif(v_payload->>'lagergruppe_id', ''))::uuid;
    v_typ := coalesce(v_payload->>'typ', '');
    v_anmeldung_id := (nullif(v_payload->>'anmeldung_id', ''))::uuid;

    if v_gruppe_id is null or v_anmeldung_id is null then
      raise exception 'assign_gruppenmitglied braucht lagergruppe_id und anmeldung_id.';
    end if;
    if v_typ not in ('tn', 'leiter') then
      raise exception 'assign_gruppenmitglied braucht typ=tn|leiter.';
    end if;
    if not exists (
      select 1 from lagergruppen lg where lg.id = v_gruppe_id and lg.lager_id = v_row.lager_id
    ) then
      raise exception 'Gruppe gehört nicht zu diesem Lager.';
    end if;

    if v_typ = 'tn' then
      if not exists (
        select 1 from anmeldungen_tn t where t.id = v_anmeldung_id and t.lager_id = v_row.lager_id
      ) then
        raise exception 'TN-Anmeldung gehört nicht zu diesem Lager.';
      end if;

      update gruppen_mitglieder
      set lagergruppe_id = v_gruppe_id
      where anmeldung_tn_id = v_anmeldung_id;

      if not found then
        insert into gruppen_mitglieder (lagergruppe_id, anmeldung_tn_id)
        values (v_gruppe_id, v_anmeldung_id);
      end if;
    else
      if not exists (
        select 1 from anmeldungen_leiter l where l.id = v_anmeldung_id and l.lager_id = v_row.lager_id
      ) then
        raise exception 'Leiter-Anmeldung gehört nicht zu diesem Lager.';
      end if;

      update gruppen_mitglieder
      set lagergruppe_id = v_gruppe_id
      where anmeldung_leiter_id = v_anmeldung_id;

      if not found then
        insert into gruppen_mitglieder (lagergruppe_id, anmeldung_leiter_id)
        values (v_gruppe_id, v_anmeldung_id);
      end if;
    end if;

    v_result := jsonb_build_object(
      'action_type', v_row.action_type,
      'lagergruppe_id', v_gruppe_id,
      'typ', v_typ,
      'anmeldung_id', v_anmeldung_id
    );
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
