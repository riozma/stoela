-- Nutzer-Feedback zur App: Text, welche Seite/Route, welcher Commit-Stand
-- (Projektstand) der Website beim Absenden. Später als Text exportierbar
-- für Claude Code.
create table app_feedback (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references profiles(id),
  email text,
  text text not null,
  seite_pfad text,
  seite_titel text,
  app_commit text,
  created_at timestamptz not null default now()
);

alter table app_feedback enable row level security;

create policy "app_feedback: insert eigene" on app_feedback
for insert with check (profile_id = auth.uid());

-- Nur der eigene Eintrag oder der App-Owner (einzige feste Admin-E-Mail)
-- dürfen Feedback lesen - es gibt aktuell keine generische App-Admin-Rolle.
create policy "app_feedback: select eigene oder owner" on app_feedback
for select using (
  profile_id = auth.uid()
  or exists (select 1 from profiles p where p.id = auth.uid() and lower(p.email) = 'manuelzeltner@gmail.com')
);
