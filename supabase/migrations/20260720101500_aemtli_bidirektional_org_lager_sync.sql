-- Bisher waren org_aemtli_besetzung/aemtli_zuweisungen (Org-Team-Tab,
-- Kaskade auf kommende Lager) und leiter_rollen (die tatsächlich im
-- Lager-Team-Tab genutzte, sichtbarkeitsrelevante Ämtli-Zuweisung pro
-- Lager) zwei getrennte Systeme. Ab jetzt: eine Zuweisung -- egal ob im
-- Organisation-Tab oder direkt im Lager vorgenommen -- gilt als DIE
-- aktuelle Ämtli-Besetzung des Vereins und wird in beide Richtungen
-- synchronisiert.

-- 1) Lager -> Organisation: wird im Lager (leiter_rollen) ein Ämtli
--    zugeteilt und die/der Leiter ist mit einem Profil verknüpft, wird
--    dieselbe Zuteilung als aktuelle Org-Besetzung übernommen (und
--    kaskadiert von dort automatisch weiter auf alle kommenden Lager).
create or replace function public.sync_leiter_rolle_zu_org()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lager_id uuid;
  v_profile_id uuid;
  v_organisation_id uuid;
begin
  select al.lager_id, al.profile_id into v_lager_id, v_profile_id
  from anmeldungen_leiter al
  where al.id = new.anmeldung_leiter_id;

  if v_profile_id is null or v_lager_id is null then
    return new;
  end if;

  select l.organisation_id into v_organisation_id from lager l where l.id = v_lager_id;
  if v_organisation_id is null then
    return new;
  end if;

  insert into org_aemtli_besetzung (organisation_id, aemtli_id, profile_id, updated_by)
  values (v_organisation_id, new.aemtli_id, v_profile_id, auth.uid())
  on conflict (organisation_id, aemtli_id) do update
    set profile_id = excluded.profile_id, updated_by = excluded.updated_by, updated_at = now()
    where org_aemtli_besetzung.profile_id is distinct from excluded.profile_id;

  return new;
end;
$$;

drop trigger if exists trg_sync_leiter_rolle_zu_org on leiter_rollen;
create trigger trg_sync_leiter_rolle_zu_org
  after insert on leiter_rollen
  for each row execute function public.sync_leiter_rolle_zu_org();

-- 2) Organisation -> Lager: kaskadiere_aemtli_besetzung schrieb bisher
--    nur in aemtli_zuweisungen. Jetzt zusätzlich: falls die Person im
--    Ziel-Lager bereits ein bestätigtes Leiter-Konto hat, auch
--    leiter_rollen nachziehen, damit der Lager-Team-Tab und die
--    freigeschalteten Ämtli-Tabs konsistent sind. Guards (WHERE
--    distinct-from / ON CONFLICT DO NOTHING) verhindern eine
--    Endlosschleife mit obigem Trigger.
create or replace function public.kaskadiere_aemtli_besetzung()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  l record;
  v_anmeldung_leiter_id uuid;
begin
  if new.profile_id is not null then
    for l in
      select id from lager
      where organisation_id = new.organisation_id
        and (end_datum is null or end_datum >= current_date)
    loop
      insert into aemtli_zuweisungen (lager_id, aemtli_id, profile_id, status)
      values (l.id, new.aemtli_id, new.profile_id, 'offen')
      on conflict (lager_id, aemtli_id) do update set profile_id = excluded.profile_id
        where aemtli_zuweisungen.profile_id is distinct from excluded.profile_id;

      select al.id into v_anmeldung_leiter_id
      from anmeldungen_leiter al
      where al.lager_id = l.id and al.profile_id = new.profile_id and al.status = 'bestaetigt'
      limit 1;

      if v_anmeldung_leiter_id is not null then
        insert into leiter_rollen (anmeldung_leiter_id, aemtli_id)
        values (v_anmeldung_leiter_id, new.aemtli_id)
        on conflict (anmeldung_leiter_id, aemtli_id) do nothing;
      end if;
    end loop;
  end if;
  return new;
end;
$$;
