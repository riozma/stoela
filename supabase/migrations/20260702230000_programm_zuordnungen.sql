-- Zuordnungen von Verantwortlichen-Namen zu Leitern/Ämtli (PDF-Import)
alter table programmbloecke
  add column if not exists verantwortlich_zuordnungen jsonb not null default '[]';

comment on column programmbloecke.verantwortlich_zuordnungen is
  'Array von { name, leiter_id?, aemtli_id? } – leer wenn nicht zuordenbar';
