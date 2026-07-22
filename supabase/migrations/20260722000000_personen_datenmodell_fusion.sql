-- Personen-Datenmodell fusionieren.
-- organisation_mitglieder, org_personen und lager_leiter speicherten denselben Menschen
-- bisher in bis zu 3 getrennten Zeilen. Neu: EINE physische Tabelle `personen` (Kontakt +
-- Vereinsrolle) und `personen_lager_rollen` (Lager-Team-Rolle), mit profiles verknüpft wenn
-- ein Login aktiv ist. Die alten Tabellennamen bleiben als Kompatibilitäts-Views bestehen,
-- damit die ~30 bestehenden RLS-Helper-Funktionen und Frontend-Aufrufe unverändert weiterlaufen.

-- ---------------------------------------------------------------------
-- 1. Neue physische Tabellen
-- ---------------------------------------------------------------------
create table public.personen (
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references public.organisation(id) on delete cascade,
  profile_id uuid references public.profiles(id) on delete set null,
  vorname text,
  nachname text,
  email text,
  telefon text,
  geburtsdatum date,
  geschlecht text check (geschlecht is null or geschlecht in ('m', 'w', 'd')),
  ahv_nr text,
  org_rolle text check (org_rolle is null or org_rolle in ('mitglied', 'leitung', 'admin')),
  org_status text check (org_status is null or org_status in ('angefragt', 'mitglied', 'abgelehnt')),
  rolle_hinweis text,
  notizen text,
  aktiv boolean not null default true,
  angefragt_am timestamptz,
  bestaetigt_am timestamptz,
  bestaetigt_von uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (organisation_id, profile_id)
);

comment on table public.personen is
  'Kanonische Personen-Tabelle je Verein: Kontaktdaten + Vereinsrolle. Ersetzt organisation_mitglieder + org_personen (beide bleiben als Kompatibilitäts-Views bestehen).';

create index personen_org_idx on public.personen (organisation_id);
create index personen_profile_idx on public.personen (profile_id) where profile_id is not null;

create table public.personen_lager_rollen (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.personen(id) on delete cascade,
  lager_id uuid not null references public.lager(id) on delete cascade,
  rolle text not null check (rolle in ('leiter', 'lagerleitung', 'kueche')),
  status text not null default 'bestaetigt' check (status in ('angemeldet', 'bestaetigt')),
  unique (person_id, lager_id)
);

comment on table public.personen_lager_rollen is
  'Lager-Team-Rolle je Person. Ersetzt lager_leiter (bleibt als Kompatibilitäts-View bestehen).';

create index personen_lager_rollen_lager_idx on public.personen_lager_rollen (lager_id);

alter table public.anmeldungen_leiter
  add column person_id uuid references public.personen(id) on delete set null;

comment on column public.anmeldungen_leiter.person_id is
  'Verweis auf die zentrale Personen-Zeile (Verein-Scope). Kontaktfelder auf dieser Tabelle bleiben ein Snapshot für Bestandskompatibilität.';

-- ---------------------------------------------------------------------
-- 2. Datenmigration
-- ---------------------------------------------------------------------

-- 2a. Eine personen-Zeile je organisation_mitglieder-Zeile (Kontaktdaten: profiles > org_personen).
insert into public.personen (
  organisation_id, profile_id, vorname, nachname, email, telefon, geburtsdatum, geschlecht, ahv_nr,
  org_rolle, org_status, angefragt_am, bestaetigt_am, bestaetigt_von, notizen, rolle_hinweis, aktiv, created_at
)
select
  om.organisation_id,
  om.profile_id,
  coalesce(nullif(trim(p.vorname), ''), nullif(trim(op.vorname), '')),
  coalesce(nullif(trim(p.nachname), ''), nullif(trim(op.nachname), '')),
  coalesce(nullif(trim(p.email), ''), nullif(trim(op.email), '')),
  coalesce(nullif(trim(p.telefon), ''), nullif(trim(op.telefon), '')),
  p.geburtsdatum,
  p.geschlecht,
  p.ahv_nr,
  om.rolle,
  om.status,
  om.angefragt_am,
  om.bestaetigt_am,
  om.bestaetigt_von,
  om.notiz,
  op.rolle_hinweis,
  true,
  coalesce(om.angefragt_am, now())
from public.organisation_mitglieder om
left join public.profiles p on p.id = om.profile_id
left join public.org_personen op
  on op.organisation_id = om.organisation_id and op.profile_id = om.profile_id and op.aktiv = true;

-- 2b. Übrige org_personen-Zeilen (manuelle Kontakte ohne Mitgliedschaft, oder Profile ohne
-- organisation_mitglieder-Zeile) als eigene personen-Zeilen übernehmen. Bei Duplikaten pro
-- (organisation_id, profile_id) den aktivsten/neuesten Datensatz nehmen.
insert into public.personen (organisation_id, profile_id, vorname, nachname, email, telefon, rolle_hinweis, notizen, aktiv, created_at)
select organisation_id, profile_id, vorname, nachname, email, telefon, rolle_hinweis, notizen, aktiv, created_at
from (
  select
    op.*,
    row_number() over (
      partition by op.organisation_id, op.profile_id
      order by op.aktiv desc, op.created_at desc
    ) as rn
  from public.org_personen op
  where op.profile_id is null
     or not exists (
       select 1 from public.personen p
       where p.organisation_id = op.organisation_id and p.profile_id = op.profile_id
     )
) x
where x.profile_id is null or x.rn = 1;

-- 2c. Lager-Team-Mitglieder ohne Vereinsmitgliedschaft (z. B. via Direktfreischaltung) fehlten
-- bisher überall: fehlende personen-Zeilen nachtragen.
insert into public.personen (organisation_id, profile_id, vorname, nachname, email, telefon, geburtsdatum, geschlecht, ahv_nr, aktiv, created_at)
select distinct
  l.organisation_id, ll.profile_id, p.vorname, p.nachname, p.email, p.telefon, p.geburtsdatum, p.geschlecht, p.ahv_nr, true, now()
from public.lager_leiter ll
join public.lager l on l.id = ll.lager_id
left join public.profiles p on p.id = ll.profile_id
where l.organisation_id is not null
  and not exists (
    select 1 from public.personen pe
    where pe.organisation_id = l.organisation_id and pe.profile_id = ll.profile_id
  );

-- 2d. personen_lager_rollen aus lager_leiter befüllen.
insert into public.personen_lager_rollen (person_id, lager_id, rolle, status)
select p.id, ll.lager_id, ll.rolle, ll.status
from public.lager_leiter ll
join public.lager l on l.id = ll.lager_id
join public.personen p on p.organisation_id = l.organisation_id and p.profile_id = ll.profile_id
on conflict (person_id, lager_id) do nothing;

-- 2e. anmeldungen_leiter.person_id befüllen: über profile_id verknüpfte Zeilen zuerst.
update public.anmeldungen_leiter al
set person_id = p.id
from public.lager l, public.personen p
where l.id = al.lager_id
  and p.organisation_id = l.organisation_id
  and p.profile_id = al.profile_id
  and al.profile_id is not null;

-- 2f. Manuelle (profil-lose) Leiter-Anmeldungen: je Zeile eine eigene personen-Zeile anlegen.
do $$
declare
  r record;
  v_person_id uuid;
begin
  for r in
    select al.id, al.vorname, al.nachname, al.email, al.telefon, al.geburtsdatum, al.geschlecht, al.ahv_nr, al.created_at, l.organisation_id
    from public.anmeldungen_leiter al
    join public.lager l on l.id = al.lager_id
    where al.profile_id is null and al.person_id is null and l.organisation_id is not null
  loop
    insert into public.personen (organisation_id, vorname, nachname, email, telefon, geburtsdatum, geschlecht, ahv_nr, aktiv, created_at)
    values (r.organisation_id, r.vorname, r.nachname, r.email, r.telefon, r.geburtsdatum, r.geschlecht, r.ahv_nr, true, r.created_at)
    returning id into v_person_id;

    update public.anmeldungen_leiter set person_id = v_person_id where id = r.id;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------
-- 3. Alte Tabellen umbenennen (Audit-Reserve, nicht mehr über die API erreichbar)
-- ---------------------------------------------------------------------
drop trigger if exists trg_ensure_leiter_teilnahme_fuer_team on public.lager_leiter;

alter table public.organisation_mitglieder rename to organisation_mitglieder_legacy;
alter table public.lager_leiter rename to lager_leiter_legacy;
alter table public.org_personen rename to org_personen_legacy;

revoke all on public.organisation_mitglieder_legacy from anon, authenticated;
revoke all on public.lager_leiter_legacy from anon, authenticated;
revoke all on public.org_personen_legacy from anon, authenticated;

-- ---------------------------------------------------------------------
-- 4. Kompatibilitäts-Views mit den alten Namen
-- ---------------------------------------------------------------------

-- org_personen: einfache 1:1-Projektion, automatisch aktualisierbar (kein Trigger nötig).
create view public.org_personen
with (security_invoker = true)
as
select id, organisation_id, profile_id, vorname, nachname, email, telefon, rolle_hinweis, aktiv, notizen, created_at
from public.personen;

-- organisation_mitglieder: gefilterte 1:1-Projektion, ebenfalls automatisch aktualisierbar
-- inkl. INSERT ... ON CONFLICT (organisation_id, profile_id), das mehrere Funktionen nutzen.
create view public.organisation_mitglieder
with (security_invoker = true)
as
select id, organisation_id, profile_id, org_rolle as rolle, org_status as status,
       angefragt_am, bestaetigt_am, bestaetigt_von, notizen as notiz
from public.personen
where org_rolle is not null;

-- lager_leiter: braucht einen Join (Rolle liegt in personen_lager_rollen, profile_id in
-- personen) -> nicht automatisch aktualisierbar, daher explizite INSTEAD OF Trigger.
create view public.lager_leiter
with (security_invoker = true)
as
select plr.id, plr.lager_id, p.profile_id, plr.rolle, plr.status
from public.personen_lager_rollen plr
join public.personen p on p.id = plr.person_id;

grant select, insert, update, delete on public.personen to anon, authenticated;
grant select, insert, update, delete on public.personen_lager_rollen to anon, authenticated;
grant select, insert, update, delete on public.org_personen to anon, authenticated;
grant select, insert, update, delete on public.organisation_mitglieder to anon, authenticated;
grant select, insert, update, delete on public.lager_leiter to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5. RLS auf den neuen physischen Tabellen (spiegelt die bisherige Zugriffslogik)
-- ---------------------------------------------------------------------
alter table public.personen enable row level security;

create policy "personen: select mitglieder oder selbst"
  on public.personen for select to authenticated
  using (public.is_org_mitglied(organisation_id) or profile_id = auth.uid());

create policy "personen: insert selbst-anfrage oder leitung"
  on public.personen for insert to authenticated
  with check (
    (profile_id = auth.uid() and org_status = 'angefragt' and org_rolle = 'mitglied')
    or public.is_org_leitung(organisation_id)
  );

create policy "personen: update leitung"
  on public.personen for update to authenticated
  using (public.is_org_leitung(organisation_id))
  with check (public.is_org_leitung(organisation_id));

create policy "personen: delete leitung oder selbst"
  on public.personen for delete to authenticated
  using (public.is_org_leitung(organisation_id) or profile_id = auth.uid());

alter table public.personen_lager_rollen enable row level security;

create policy "personen_lager_rollen: select berechtigte"
  on public.personen_lager_rollen for select to authenticated
  using (
    public.can_access_lager(lager_id)
    or exists (select 1 from public.personen p where p.id = person_id and p.profile_id = auth.uid())
  );

create policy "personen_lager_rollen: insert lagerleitung"
  on public.personen_lager_rollen for insert to authenticated
  with check (
    public.is_lager_leitung(lager_id)
    or exists (select 1 from public.lager l where l.id = lager_id and l.created_by = auth.uid())
  );

create policy "personen_lager_rollen: update lagerleitung oder selbst"
  on public.personen_lager_rollen for update to authenticated
  using (
    public.is_lager_leitung(lager_id)
    or exists (select 1 from public.personen p where p.id = person_id and p.profile_id = auth.uid())
  );

create policy "personen_lager_rollen: delete lagerleitung"
  on public.personen_lager_rollen for delete to authenticated
  using (public.is_lager_leitung(lager_id));

-- ---------------------------------------------------------------------
-- 6. Helper: personen-Zeile zu (Lager, Profil) finden oder anlegen.
-- Security definer, weil eine Lager-Team-Rolle historisch unabhängig von einer
-- Vereinsmitgliedschaft vergeben werden konnte (freischalten_teammitglied,
-- sync_lager_leiter_aus_bestaetigter_anmeldung) -- das bleibt so.
-- ---------------------------------------------------------------------
create or replace function public.personen_id_von_profile(p_lager_id uuid, p_profile_id uuid)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_org_id uuid;
  v_person_id uuid;
  v_vorname text;
  v_nachname text;
  v_email text;
  v_telefon text;
  v_geburtsdatum date;
  v_geschlecht text;
  v_ahv text;
begin
  select organisation_id into v_org_id from lager where id = p_lager_id;
  if v_org_id is null then
    raise exception 'Lager hat keine Organisation.';
  end if;

  select id into v_person_id from personen where organisation_id = v_org_id and profile_id = p_profile_id;
  if v_person_id is not null then
    return v_person_id;
  end if;

  select vorname, nachname, email, telefon, geburtsdatum, geschlecht, ahv_nr
  into v_vorname, v_nachname, v_email, v_telefon, v_geburtsdatum, v_geschlecht, v_ahv
  from profiles where id = p_profile_id;

  insert into personen (organisation_id, profile_id, vorname, nachname, email, telefon, geburtsdatum, geschlecht, ahv_nr, aktiv)
  values (v_org_id, p_profile_id, v_vorname, v_nachname, v_email, v_telefon, v_geburtsdatum, v_geschlecht, v_ahv, true)
  returning id into v_person_id;

  return v_person_id;
end;
$$;

grant execute on function public.personen_id_von_profile(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 7. INSTEAD OF Trigger für die lager_leiter-View
-- ---------------------------------------------------------------------
create or replace function public.lager_leiter_view_insert()
returns trigger
language plpgsql
set search_path to 'public'
as $$
declare
  v_person_id uuid;
  v_new_id uuid;
begin
  v_person_id := public.personen_id_von_profile(new.lager_id, new.profile_id);
  insert into personen_lager_rollen (person_id, lager_id, rolle, status)
  values (v_person_id, new.lager_id, new.rolle, coalesce(new.status, 'bestaetigt'))
  returning id into v_new_id;
  new.id := v_new_id;
  return new;
end;
$$;

create trigger trg_lager_leiter_view_insert
instead of insert on public.lager_leiter
for each row execute function public.lager_leiter_view_insert();

create or replace function public.lager_leiter_view_update()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  update personen_lager_rollen
  set rolle = new.rolle, status = new.status
  where id = old.id;
  return new;
end;
$$;

create trigger trg_lager_leiter_view_update
instead of update on public.lager_leiter
for each row execute function public.lager_leiter_view_update();

create or replace function public.lager_leiter_view_delete()
returns trigger
language plpgsql
set search_path to 'public'
as $$
begin
  delete from personen_lager_rollen where id = old.id;
  return old;
end;
$$;

create trigger trg_lager_leiter_view_delete
instead of delete on public.lager_leiter
for each row execute function public.lager_leiter_view_delete();

-- ---------------------------------------------------------------------
-- 8. ensure_leiter_teilnahme_fuer_team: von lager_leiter (jetzt View, kein AFTER-Trigger
-- möglich) auf personen_lager_rollen umziehen.
-- ---------------------------------------------------------------------
create or replace function public.ensure_leiter_teilnahme_fuer_team()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_p profiles%rowtype;
  v_l lager%rowtype;
begin
  select profile_id into v_profile_id from personen where id = new.person_id;
  if v_profile_id is null then
    return new;
  end if;

  if exists (
    select 1 from anmeldungen_leiter al
    where al.lager_id = new.lager_id
      and al.profile_id = v_profile_id
      and al.status not in ('abgesagt', 'abgelehnt')
  ) then
    return new;
  end if;

  select * into v_p from profiles where id = v_profile_id;
  select * into v_l from lager where id = new.lager_id;
  if v_p.id is null or v_l.id is null then return new; end if;

  insert into anmeldungen_leiter (
    lager_id, profile_id, person_id, vorname, nachname, email, telefon,
    geburtsdatum, geschlecht, ahv_nr, anwesend_von, anwesend_bis,
    status, anmeldung_art
  )
  values (
    new.lager_id,
    v_profile_id,
    new.person_id,
    coalesce(nullif(trim(v_p.vorname), ''), split_part(v_p.email, '@', 1), 'Leiter'),
    coalesce(nullif(trim(v_p.nachname), ''), ''),
    v_p.email,
    v_p.telefon,
    v_p.geburtsdatum,
    v_p.geschlecht,
    v_p.ahv_nr,
    v_l.start_datum,
    v_l.end_datum,
    case when new.status = 'bestaetigt' then 'bestaetigt' else 'angemeldet' end,
    'fix'
  )
  on conflict do nothing;

  return new;
end;
$$;

create trigger trg_ensure_leiter_teilnahme_fuer_team
after insert or update of status on public.personen_lager_rollen
for each row execute function public.ensure_leiter_teilnahme_fuer_team();

-- ---------------------------------------------------------------------
-- 9. Funktionen mit "insert into lager_leiter ... on conflict (lager_id, profile_id)":
-- ON CONFLICT funktioniert nicht durch eine View mit INSTEAD OF Triggern, deshalb hier
-- explizit auf personen_lager_rollen umgestellt (einzige inhaltliche Änderung je Funktion).
-- ---------------------------------------------------------------------
create or replace function public.freischalten_teammitglied(p_lager_id uuid, p_email text, p_rolle text default 'leiter'::text)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_profile_id uuid;
  v_person_id uuid;
  v_leiter_id uuid;
begin
  if not public.is_lager_leitung(p_lager_id) then
    raise exception 'Nur die Lagerleitung darf Teammitglieder freischalten.';
  end if;

  select id into v_profile_id from profiles where lower(email) = lower(trim(p_email));
  if v_profile_id is null then
    raise exception 'Kein Profil mit dieser E-Mail gefunden. Die Person muss sich zuerst einloggen.';
  end if;

  v_person_id := public.personen_id_von_profile(p_lager_id, v_profile_id);

  insert into personen_lager_rollen (person_id, lager_id, rolle, status)
  values (v_person_id, p_lager_id, p_rolle, 'bestaetigt')
  on conflict (person_id, lager_id) do update
    set rolle = excluded.rolle, status = 'bestaetigt'
  returning id into v_leiter_id;

  return v_leiter_id;
end;
$$;

create or replace function public.sync_lager_leiter_aus_bestaetigter_anmeldung()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_person_id uuid;
begin
  if new.profile_id is null then
    return new;
  end if;

  if new.status = 'bestaetigt' then
    v_person_id := public.personen_id_von_profile(new.lager_id, new.profile_id);
    insert into personen_lager_rollen (person_id, lager_id, rolle, status)
    values (v_person_id, new.lager_id, 'leiter', 'bestaetigt')
    on conflict (person_id, lager_id)
    do update set status = 'bestaetigt';
  end if;

  return new;
end;
$$;

create or replace function public.leiter_anfrage_bearbeiten(p_anmeldung_id uuid, p_entscheidung text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_lager_id uuid;
  v_profile_id uuid;
  v_person_id uuid;
begin
  select lager_id, profile_id into v_lager_id, v_profile_id
  from anmeldungen_leiter
  where id = p_anmeldung_id and status = 'angefragt';

  if v_lager_id is null then
    raise exception 'Anfrage nicht gefunden oder bereits bearbeitet.';
  end if;

  if not public.is_lager_leitung(v_lager_id) then
    raise exception 'Nur die Lagerleitung darf Leiter-Anfragen bearbeiten.';
  end if;

  if p_entscheidung = 'genehmigen' then
    if v_profile_id is null then
      raise exception 'Anfrage hat kein verknüpftes Profil.';
    end if;
    update anmeldungen_leiter set status = 'bestaetigt' where id = p_anmeldung_id;
    v_person_id := public.personen_id_von_profile(v_lager_id, v_profile_id);
    insert into personen_lager_rollen (person_id, lager_id, rolle, status)
    values (v_person_id, v_lager_id, 'leiter', 'bestaetigt')
    on conflict (person_id, lager_id) do update set status = 'bestaetigt';
  elsif p_entscheidung = 'ablehnen' then
    update anmeldungen_leiter set status = 'abgelehnt' where id = p_anmeldung_id;
  else
    raise exception 'Ungültige Entscheidung.';
  end if;
end;
$$;

create or replace function public.leiter_anfrage_bearbeiten(p_anmeldung_id uuid, p_entscheidung text, p_verknuepf_mit uuid default null::uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_lager_id uuid;
  v_profile_id uuid;
  v_person_id uuid;
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

    v_person_id := public.personen_id_von_profile(v_lager_id, v_profile_id);
    insert into personen_lager_rollen (person_id, lager_id, rolle, status)
    values (v_person_id, v_lager_id, 'leiter', 'bestaetigt')
    on conflict (person_id, lager_id) do update set status = 'bestaetigt';
  elsif p_entscheidung = 'ablehnen' then
    update anmeldungen_leiter set status = 'abgelehnt' where id = p_anmeldung_id;
  else
    raise exception 'Ungültige Entscheidung.';
  end if;
end;
$$;

-- lager_leiter_aus_verein_hinzufuegen: nur der abschliessende Insert-Block ändert sich,
-- Rest (Suche über organisation_mitglieder/org_personen-Views) bleibt unverändert gültig.
create or replace function public.lager_leiter_aus_verein_hinzufuegen(
  p_lager_id uuid,
  p_profile_id uuid default null,
  p_org_person_id uuid default null,
  p_als_lalei boolean default false,
  p_anwesend_von date default null,
  p_anwesend_bis date default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_org_id uuid;
  v_profile_id uuid;
  v_vorname text;
  v_nachname text;
  v_email text;
  v_telefon text;
  v_person org_personen%rowtype;
  v_anmeldung_id uuid;
  v_start date;
  v_ende date;
  v_person_id uuid;
begin
  if not public.can_access_lager(p_lager_id) then
    raise exception 'Kein Zugriff auf dieses Lager.';
  end if;

  select organisation_id, start_datum, end_datum
  into v_org_id, v_start, v_ende
  from lager where id = p_lager_id;

  if v_org_id is null then
    raise exception 'Lager hat keine Organisation.';
  end if;

  if p_profile_id is not null then
    v_profile_id := p_profile_id;
    if not exists (
      select 1 from organisation_mitglieder om
      where om.organisation_id = v_org_id
        and om.profile_id = v_profile_id
        and om.status = 'mitglied'
    ) then
      raise exception 'Person ist kein bestätigtes Vereinsmitglied.';
    end if;

    select
      coalesce(nullif(trim(p.vorname), ''), nullif(trim(u.raw_user_meta_data->>'given_name'), '')),
      coalesce(nullif(trim(p.nachname), ''), nullif(trim(u.raw_user_meta_data->>'family_name'), '')),
      coalesce(nullif(trim(p.email), ''), u.email::text),
      p.telefon
    into v_vorname, v_nachname, v_email, v_telefon
    from auth.users u
    left join profiles p on p.id = u.id
    where u.id = v_profile_id;

    select coalesce(v_vorname, op.vorname), coalesce(v_nachname, op.nachname), coalesce(v_email, op.email), coalesce(v_telefon, op.telefon)
    into v_vorname, v_nachname, v_email, v_telefon
    from org_personen op
    where op.organisation_id = v_org_id
      and op.profile_id = v_profile_id
      and op.aktiv = true
    limit 1;

  elsif p_org_person_id is not null then
    select * into v_person
    from org_personen
    where id = p_org_person_id
      and organisation_id = v_org_id
      and aktiv = true;

    if not found then
      raise exception 'Manueller Vereinseintrag nicht gefunden.';
    end if;

    v_profile_id := v_person.profile_id;
    v_vorname := v_person.vorname;
    v_nachname := v_person.nachname;
    v_email := v_person.email;
    v_telefon := v_person.telefon;
  else
    raise exception 'profile_id oder org_person_id erforderlich.';
  end if;

  if coalesce(trim(v_vorname), '') = '' or coalesce(trim(v_nachname), '') = '' then
    raise exception 'Vor- und Nachname fehlen. Bitte im Verein Profil ergänzen.';
  end if;

  if exists (
    select 1 from anmeldungen_leiter al
    where al.lager_id = p_lager_id
      and (
        (v_profile_id is not null and al.profile_id = v_profile_id)
        or (lower(al.vorname) = lower(v_vorname) and lower(al.nachname) = lower(v_nachname))
      )
  ) then
    raise exception 'Person ist bereits als Leiter in diesem Lager erfasst.';
  end if;

  if v_profile_id is not null then
    perform public.profil_leiter_daten_sync(v_profile_id, v_vorname, v_nachname, null, null, null, v_telefon);
  end if;

  insert into anmeldungen_leiter (
    lager_id, profile_id, vorname, nachname, email, telefon,
    anwesend_von, anwesend_bis, status, anmeldung_art, bestaetigen_bis
  ) values (
    p_lager_id,
    v_profile_id,
    v_vorname,
    v_nachname,
    v_email,
    v_telefon,
    coalesce(p_anwesend_von, v_start),
    coalesce(p_anwesend_bis, v_ende),
    'bestaetigt',
    'fix',
    case when v_start is not null then (v_start - interval '3 months')::date else null end
  )
  returning id into v_anmeldung_id;

  if v_profile_id is not null then
    v_person_id := public.personen_id_von_profile(p_lager_id, v_profile_id);
    insert into personen_lager_rollen (person_id, lager_id, rolle, status)
    values (
      v_person_id,
      p_lager_id,
      case when p_als_lalei then 'lagerleitung' else 'leiter' end,
      'bestaetigt'
    )
    on conflict (person_id, lager_id) do update set
      rolle = case
        when p_als_lalei then 'lagerleitung'
        when personen_lager_rollen.rolle = 'lagerleitung' then 'lagerleitung'
        else excluded.rolle
      end,
      status = 'bestaetigt';
  end if;

  return v_anmeldung_id;
end;
$$;

-- ---------------------------------------------------------------------
-- 10. verein_leiter_entfernen: "DELETE FROM organisation_mitglieder" würde über die neue
-- View jetzt die komplette personen-Zeile löschen (inkl. Kontaktdaten + allen Lager-Rollen
-- in JEDEM Lager, kaskadierend) statt nur die Mitgliedschaft dieses Vereins zu beenden.
-- Deshalb hier explizit auf ein Soft-Unset (org_rolle/org_status = null) umgestellt.
-- ---------------------------------------------------------------------
create or replace function public.verein_leiter_entfernen(p_organisation_id uuid, p_profile_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_admin_count integer;
  v_person_id uuid;
begin
  if not public.is_org_admin(p_organisation_id) then
    raise exception 'Nur Vereins-Admins dürfen Leiter entfernen.';
  end if;

  select id into v_person_id from personen
  where organisation_id = p_organisation_id and profile_id = p_profile_id and org_status = 'mitglied';

  if v_person_id is null then
    raise exception 'Leiter ist kein aktives Vereinsmitglied.';
  end if;

  if exists (select 1 from personen where id = v_person_id and org_rolle = 'admin') then
    select count(*) into v_admin_count
    from personen
    where organisation_id = p_organisation_id and org_status = 'mitglied' and org_rolle = 'admin';

    if v_admin_count <= 1 then
      raise exception 'Der letzte Vereins-Admin kann nicht entfernt werden.';
    end if;
  end if;

  update personen
  set org_rolle = null, org_status = null, aktiv = false
  where id = v_person_id;

  delete from personen_lager_rollen
  where person_id = v_person_id
    and lager_id in (select id from lager where organisation_id = p_organisation_id);
end;
$$;
