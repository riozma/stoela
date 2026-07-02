-- Kochplan, TN-Finanzen, Quittungen, IBANs, Storage

insert into aemtli (name, beschreibung)
values ('Finanzen', 'Kasse, Quittungen, TN-Zahlungen')
on conflict (name) do nothing;

-- ---------------------------------------------------------------------
-- Kochplan (Küche)
-- ---------------------------------------------------------------------
create table mahlzeit_vorlagen (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  name text not null,
  mahlzeit text not null check (mahlzeit in ('fruehstueck', 'zmittag', 'znacht', 'jause')),
  wochentag int check (wochentag between 0 and 6),
  beschreibung text,
  material jsonb not null default '[]',
  created_at timestamptz not null default now()
);

create table mahlzeiten (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  tag date not null,
  mahlzeit text not null check (mahlzeit in ('fruehstueck', 'zmittag', 'znacht', 'jause')),
  titel text not null,
  beschreibung text,
  material jsonb not null default '[]',
  vorlage_id uuid references mahlzeit_vorlagen (id) on delete set null,
  created_at timestamptz not null default now(),
  unique (lager_id, tag, mahlzeit)
);

create table mahlzeit_ausnahmen (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  tag date not null,
  vorlage_id uuid not null references mahlzeit_vorlagen (id) on delete cascade,
  unique (lager_id, tag, vorlage_id)
);

-- ---------------------------------------------------------------------
-- TN Finanzen
-- ---------------------------------------------------------------------
create table tn_finanzen (
  id uuid primary key default gen_random_uuid(),
  anmeldung_tn_id uuid not null references anmeldungen_tn (id) on delete cascade unique,
  bezahlt boolean not null default false,
  bemerkung text,
  reduktion text,
  updated_by uuid references profiles (id),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Quittungen
-- ---------------------------------------------------------------------
create table profile_ibans (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,
  iban text not null,
  bezeichnung text,
  created_at timestamptz not null default now()
);

create table quittungen (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  einreicher_id uuid not null references profiles (id),
  iban_id uuid not null references profile_ibans (id),
  betrag numeric(10, 2) not null,
  zweck text not null,
  status text not null default 'pending'
    check (status in ('pending', 'bezahlt', 'abgelehnt')),
  ablehnungsgrund text,
  bearbeitet_von uuid references profiles (id),
  bearbeitet_am timestamptz,
  created_at timestamptz not null default now()
);

create table quittung_dateien (
  id uuid primary key default gen_random_uuid(),
  quittung_id uuid not null references quittungen (id) on delete cascade,
  storage_path text not null,
  dateiname text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------
create or replace function public.hat_aemtli(p_lager_id uuid, p_name text)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select public.is_kueche(p_lager_id) and p_name = 'Küche'
    or public.is_lager_leitung(p_lager_id)
    or exists (
      select 1 from aemtli_zuweisungen az
      join aemtli a on a.id = az.aemtli_id
      where az.lager_id = p_lager_id and az.profile_id = auth.uid() and a.name = p_name
    )
    or exists (
      select 1 from leiter_rollen lr
      join anmeldungen_leiter al on al.id = lr.anmeldung_leiter_id
      join aemtli a on a.id = lr.aemtli_id
      join profiles p on p.id = auth.uid()
      where al.lager_id = p_lager_id and lower(al.email) = lower(p.email)
        and a.name = p_name and al.status = 'bestaetigt'
    );
$$;

grant execute on function public.hat_aemtli(uuid, text) to authenticated;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table mahlzeit_vorlagen enable row level security;
alter table mahlzeiten enable row level security;
alter table mahlzeit_ausnahmen enable row level security;
alter table tn_finanzen enable row level security;
alter table profile_ibans enable row level security;
alter table quittungen enable row level security;
alter table quittung_dateien enable row level security;

create policy "mahlzeit_vorlagen: lagerteam" on mahlzeit_vorlagen
  for all to authenticated using (public.can_access_lager(lager_id)) with check (public.can_access_lager(lager_id));

create policy "mahlzeiten: lagerteam" on mahlzeiten
  for all to authenticated using (public.can_access_lager(lager_id)) with check (public.can_access_lager(lager_id));

create policy "mahlzeit_ausnahmen: lagerteam" on mahlzeit_ausnahmen
  for all to authenticated using (public.can_access_lager(lager_id)) with check (public.can_access_lager(lager_id));

create policy "tn_finanzen: lagerteam" on tn_finanzen
  for all to authenticated
  using (exists (select 1 from anmeldungen_tn t where t.id = anmeldung_tn_id and public.can_access_lager(t.lager_id)))
  with check (exists (select 1 from anmeldungen_tn t where t.id = anmeldung_tn_id and public.can_access_lager(t.lager_id)));

create policy "profile_ibans: eigenes profil" on profile_ibans
  for all to authenticated using (profile_id = auth.uid()) with check (profile_id = auth.uid());

create policy "quittungen: select lagerteam" on quittungen
  for select to authenticated using (public.can_access_lager(lager_id));

create policy "quittungen: insert eigenes" on quittungen
  for insert to authenticated
  with check (public.can_access_lager(lager_id) and einreicher_id = auth.uid());

create policy "quittungen: update einreicher oder finanzen" on quittungen
  for update to authenticated
  using (
    einreicher_id = auth.uid()
    or public.hat_aemtli(lager_id, 'Finanzen')
    or public.is_lager_leitung(lager_id)
  );

create policy "quittung_dateien: lagerteam" on quittung_dateien
  for all to authenticated
  using (exists (select 1 from quittungen q where q.id = quittung_id and public.can_access_lager(q.lager_id)))
  with check (exists (select 1 from quittungen q where q.id = quittung_id and q.einreicher_id = auth.uid()));

-- Storage bucket für Quittungsbilder
insert into storage.buckets (id, name, public)
values ('quittungen', 'quittungen', false)
on conflict (id) do nothing;

create policy "quittungen storage: upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'quittungen' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "quittungen storage: read lagerteam" on storage.objects
  for select to authenticated
  using (bucket_id = 'quittungen');

create policy "quittungen storage: delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'quittungen' and (storage.foldername(name))[1] = auth.uid()::text);

-- Höck: updated_by für Nachvollziehbarkeit
alter table hoeck_notizen add column if not exists autor_name text;

create policy "hoeck_notizen: lagerteam" on hoeck_notizen
  for all to authenticated
  using (public.can_access_lager(lager_id))
  with check (public.can_access_lager(lager_id));

create policy "quittungen: delete eigenes pending" on quittungen
  for delete to authenticated
  using (einreicher_id = auth.uid() and status = 'pending');
