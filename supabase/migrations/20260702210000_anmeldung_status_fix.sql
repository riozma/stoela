-- Anmeldung: Leiter auch während Planung/Laufend, TN nur bei anmeldung_offen

create or replace function public.get_lager_anmeldung_info(
  p_lager_id uuid,
  p_typ text default 'tn'
)
returns json
language sql
security definer
stable
set search_path = public
as $$
  select json_build_object(
    'id', l.id,
    'name', l.name,
    'ort', l.ort,
    'start_datum', l.start_datum,
    'end_datum', l.end_datum,
    'status', l.status
  )
  from lager l
  where l.id = p_lager_id
    and l.status <> 'archiviert'
    and (
      (p_typ = 'tn' and l.status = 'anmeldung_offen')
      or (p_typ = 'leiter' and l.status in ('planung', 'anmeldung_offen', 'laufend'))
    );
$$;

-- Für Fehlermeldung: Status anzeigen auch wenn Anmeldung geschlossen
create or replace function public.get_lager_anmeldung_peek(p_lager_id uuid)
returns json
language sql
security definer
stable
set search_path = public
as $$
  select json_build_object('name', l.name, 'status', l.status)
  from lager l
  where l.id = p_lager_id and l.status <> 'archiviert';
$$;

grant execute on function public.get_lager_anmeldung_info(uuid, text) to anon, authenticated;
grant execute on function public.get_lager_anmeldung_peek(uuid) to anon, authenticated;

-- Leiter-Anfrage auch während Planung/Laufend
drop policy if exists "anmeldungen_leiter: insert eigene Anfrage" on anmeldungen_leiter;

create policy "anmeldungen_leiter: insert eigene Anfrage" on anmeldungen_leiter
  for insert to authenticated
  with check (
    profile_id = auth.uid()
    and exists (
      select 1 from lager
      where id = lager_id
        and status in ('planung', 'anmeldung_offen', 'laufend')
    )
  );

-- Öffentliche Lager-Metadaten für Anmeldeformulare (Status-Hinweis)
drop policy if exists "lager: select anmeldung basis" on lager;

create policy "lager: select anmeldung basis" on lager
  for select to anon, authenticated
  using (status in ('planung', 'anmeldung_offen', 'laufend'));
