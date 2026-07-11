-- Höck: Personenbedarf + Uhrzeit pro Rolle (optional, per Stift-Icon editierbar),
-- Feedback-Höck (andere Struktur, für nach dem Lager).

alter table hoeck_rollen add column if not exists bedarf_anzahl int;
alter table hoeck_rollen add column if not exists uhrzeit time;

-- Rückgabetyp ändert sich (neue Spalten) -> Funktion muss neu erstellt werden
drop function if exists public.get_hoeck_rollen_fuer_tag(uuid, date);

create function public.get_hoeck_rollen_fuer_tag(p_lager_id uuid, p_tag date)
returns table (
  id uuid,
  rolle text,
  ist_eigene boolean,
  sortierung int,
  bedarf_anzahl int,
  uhrzeit time,
  leute jsonb
) language plpgsql security definer set search_path = public as $$
begin
  if not public.can_access_lager(p_lager_id) then
    raise exception 'Kein Zugriff.';
  end if;
  return query
  select
    hr.id,
    hr.rolle,
    hr.ist_eigene,
    hr.sortierung,
    hr.bedarf_anzahl,
    hr.uhrzeit,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', hz.id,
          'leiter_id', hz.leiter_id,
          'vorname', al.vorname,
          'nachname', al.nachname
        )
      ) filter (where hz.id is not null),
      '[]'::jsonb
    ) as leute
  from hoeck_rollen hr
  left join hoeck_zuweisungen hz on hz.hoeck_rolle_id = hr.id
  left join anmeldungen_leiter al on al.id = hz.leiter_id
  where hr.lager_id = p_lager_id and hr.tag = p_tag
  group by hr.id, hr.rolle, hr.ist_eigene, hr.sortierung, hr.bedarf_anzahl, hr.uhrzeit
  order by hr.sortierung, hr.rolle;
end;
$$;

grant execute on function public.get_hoeck_rollen_fuer_tag(uuid, date) to authenticated;

-- ---------------------------------------------------------------------
-- Feedback-Höck (nach dem Lager) – einfache, chronologische Liste
-- ---------------------------------------------------------------------
create table if not exists hoeck_feedback (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  profile_id uuid references profiles (id) on delete set null,
  autor_name text not null,
  text text not null,
  created_at timestamptz not null default now()
);

alter table hoeck_feedback enable row level security;

create policy "hoeck_feedback: team" on hoeck_feedback for all to authenticated
  using (can_access_lager(lager_id)) with check (can_access_lager(lager_id));
