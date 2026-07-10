-- Duplikate: ältesten Termin behalten; Lager-Termin = Verknüpfung zu Einstellungen

create or replace function public.lager_termine_dedupe(p_lager_id uuid default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from lager_termine lt
  where lt.typ in ('lager', 'elternabend', 'kennenlernabend', 'diashow', 'vorweekend', 'skiweekend', 'hoeck')
    and (p_lager_id is null or lt.lager_id = p_lager_id)
    and lt.id not in (
      select distinct on (lager_id, typ) id
      from lager_termine
      where typ in ('lager', 'elternabend', 'kennenlernabend', 'diashow', 'vorweekend', 'skiweekend', 'hoeck')
        and (p_lager_id is null or lager_id = p_lager_id)
      order by lager_id, typ, created_at asc, id asc
    );
end;
$$;

-- Bereinigung jetzt (ältester Eintrag pro Lager+Typ)
select public.lager_termine_dedupe(null);

create or replace function public.lager_termin_upsert_cfg(
  p_lager_id uuid,
  p_typ text,
  p_titel text,
  p_start_datum date,
  p_end_datum date default null,
  p_ort text default null,
  p_oeffentlich boolean default false,
  p_sortierung int default 0
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_start_datum is null then return; end if;

  select id into v_id
  from lager_termine
  where lager_id = p_lager_id and typ = p_typ
  order by created_at asc, id asc
  limit 1;

  if v_id is not null then
    update lager_termine
    set titel = p_titel,
        start_datum = p_start_datum,
        end_datum = p_end_datum,
        ort = coalesce(p_ort, ort),
        oeffentlich = p_oeffentlich,
        sortierung = p_sortierung,
        updated_at = now()
    where id = v_id;

    delete from lager_termine
    where lager_id = p_lager_id and typ = p_typ and id <> v_id;
  else
    insert into lager_termine (
      lager_id, typ, titel, start_datum, end_datum, ort, oeffentlich, sortierung
    )
    values (
      p_lager_id, p_typ, p_titel, p_start_datum, p_end_datum, p_ort, p_oeffentlich, p_sortierung
    );
  end if;
end;
$$;

create or replace function public.lager_termine_sync(p_lager_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager lager%rowtype;
  v_cfg jsonb;
begin
  select * into v_lager from lager where id = p_lager_id;
  if not found then return; end if;

  perform public.lager_termine_dedupe(p_lager_id);

  v_cfg := coalesce(v_lager.elterninfo_config, '{}'::jsonb);

  -- Lager = ein Eintrag, Daten aus Einstellungen (lager.start_datum/end_datum/ort)
  if v_lager.start_datum is not null then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'lager', coalesce(v_lager.name, 'Lager'),
      v_lager.start_datum, v_lager.end_datum,
      v_lager.ort, true, 0
    );
  else
    delete from lager_termine where lager_id = p_lager_id and typ = 'lager';
  end if;

  if v_lager.vorweekend_start is not null then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'vorweekend', 'Vorweekend',
      v_lager.vorweekend_start, v_lager.vorweekend_ende,
      null, false, 10
    );
  else
    delete from lager_termine where lager_id = p_lager_id and typ = 'vorweekend';
  end if;

  if (v_cfg->>'elternabend_datum') ~ '^\d{4}-\d{2}-\d{2}$' then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'elternabend', 'Elternabend',
      (v_cfg->>'elternabend_datum')::date,
      null, nullif(v_cfg->>'elternabend_ort', ''), true, 20
    );
  else
    delete from lager_termine where lager_id = p_lager_id and typ = 'elternabend';
  end if;

  if (v_cfg->>'kennenlernabend_datum') ~ '^\d{4}-\d{2}-\d{2}$' then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'kennenlernabend', 'Kennenlernabend',
      (v_cfg->>'kennenlernabend_datum')::date,
      null, nullif(v_cfg->>'kennenlernabend_ort', ''), true, 30
    );
  else
    delete from lager_termine where lager_id = p_lager_id and typ = 'kennenlernabend';
  end if;

  if (v_cfg->>'diashow_datum') ~ '^\d{4}-\d{2}-\d{2}$' then
    perform public.lager_termin_upsert_cfg(
      p_lager_id, 'diashow', 'Diashow / Lagerrückblick',
      (v_cfg->>'diashow_datum')::date,
      null, nullif(v_cfg->>'diashow_ort', ''), true, 40
    );
  else
    delete from lager_termine where lager_id = p_lager_id and typ = 'diashow';
  end if;

  perform public.lager_termine_dedupe(p_lager_id);
end;
$$;

grant execute on function public.lager_termine_dedupe(uuid) to authenticated;
