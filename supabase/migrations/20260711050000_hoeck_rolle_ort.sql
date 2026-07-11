-- Höck-Rollen: Ort auswählen (Lagerhaus drinnen/draussen, Sonstiges mit
-- eigenem Text, oder eine der erfassten Geländespielwiesen). Default:
-- Lagerhaus draussen.

alter table hoeck_rollen add column if not exists ort_typ text not null default 'lagerhaus_draussen'
  check (ort_typ in ('lagerhaus_drinnen', 'lagerhaus_draussen', 'sonstiges', 'wiese'));
alter table hoeck_rollen add column if not exists ort_text text;
alter table hoeck_rollen add column if not exists wiese_id uuid references gelaendespielwiesen (id) on delete set null;

drop function if exists public.get_hoeck_rollen_fuer_tag(uuid, date);

create function public.get_hoeck_rollen_fuer_tag(p_lager_id uuid, p_tag date)
returns table (
  id uuid,
  rolle text,
  ist_eigene boolean,
  sortierung int,
  bedarf_anzahl int,
  uhrzeit time,
  programm_block_id uuid,
  ort_typ text,
  ort_text text,
  wiese_id uuid,
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
    hr.programm_block_id,
    hr.ort_typ,
    hr.ort_text,
    hr.wiese_id,
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
  group by hr.id, hr.rolle, hr.ist_eigene, hr.sortierung, hr.bedarf_anzahl, hr.uhrzeit,
    hr.programm_block_id, hr.ort_typ, hr.ort_text, hr.wiese_id
  order by hr.sortierung, hr.rolle;
end;
$$;

grant execute on function public.get_hoeck_rollen_fuer_tag(uuid, date) to authenticated;
