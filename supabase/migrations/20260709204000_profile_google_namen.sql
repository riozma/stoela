-- Beim Google-Login Vor-/Nachname aus OAuth-Metadaten ins Profil übernehmen.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vorname text;
  v_nachname text;
  v_full text;
begin
  v_vorname := nullif(trim(coalesce(
    new.raw_user_meta_data->>'given_name',
    new.raw_user_meta_data->>'vorname',
    ''
  )), '');

  v_nachname := nullif(trim(coalesce(
    new.raw_user_meta_data->>'family_name',
    new.raw_user_meta_data->>'nachname',
    ''
  )), '');

  if v_vorname is null and v_nachname is null then
    v_full := nullif(trim(coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      ''
    )), '');

    if v_full is not null then
      v_vorname := nullif(split_part(v_full, ' ', 1), '');
      v_nachname := nullif(trim(regexp_replace(v_full, '^\S+\s*', '')), '');
    end if;
  end if;

  insert into public.profiles (id, email, vorname, nachname)
  values (new.id, new.email, v_vorname, v_nachname);

  return new;
end;
$$;

-- Bestehende Profile ohne Namen aus auth.users-Metadaten füllen.
update profiles p
set
  vorname = coalesce(nullif(trim(p.vorname), ''), nullif(trim(u.given_name), '')),
  nachname = coalesce(nullif(trim(p.nachname), ''), nullif(trim(u.family_name), ''))
from auth.users u
where u.id = p.id
  and (
    nullif(trim(p.vorname), '') is null
    or nullif(trim(p.nachname), '') is null
  )
  and (
    nullif(trim(u.raw_user_meta_data->>'given_name'), '') is not null
    or nullif(trim(u.raw_user_meta_data->>'family_name'), '') is not null
  );

update profiles p
set
  vorname = coalesce(nullif(trim(p.vorname), ''), nullif(split_part(v_full, ' ', 1), '')),
  nachname = coalesce(
    nullif(trim(p.nachname), ''),
    nullif(trim(regexp_replace(v_full, '^\S+\s*', '')), '')
  )
from (
  select
    u.id as user_id,
    nullif(trim(coalesce(u.raw_user_meta_data->>'full_name', u.raw_user_meta_data->>'name', '')), '') as v_full
  from auth.users u
) meta
where meta.user_id = p.id
  and meta.v_full is not null
  and (nullif(trim(p.vorname), '') is null or nullif(trim(p.nachname), '') is null);
