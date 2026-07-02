-- Geo-Felder für den Lagerort (Google Places Autocomplete)
alter table lager add column ort_lat numeric;
alter table lager add column ort_lng numeric;
alter table lager add column ort_place_id text;

-- Programmblöcke (LP/LS/LA/ES) eines Lagers, z.B. aus eCamp-PDF-Import
create table programmbloecke (
  id uuid primary key default gen_random_uuid(),
  lager_id uuid not null references lager (id) on delete cascade,
  code text not null check (code in ('LP', 'LS', 'LA', 'ES')),
  nummer text,
  titel text not null,
  tag date,
  start_zeit timestamptz,
  end_zeit timestamptz,
  ort text,
  ort_lat numeric,
  ort_lng numeric,
  ort_place_id text,
  verantwortlich text,
  geschichte text,
  sicherheitsueberlegungen text,
  programmabschnitt jsonb not null default '[]',
  material jsonb not null default '[]',
  notizen text,
  quelle text not null default 'manuell' check (quelle in ('manuell', 'ecamp_pdf')),
  created_at timestamptz not null default now()
);

alter table programmbloecke enable row level security;

create policy "programmbloecke: für Lagerteam" on programmbloecke
  for all to authenticated
  using (public.is_lager_team(lager_id))
  with check (public.is_lager_team(lager_id));
