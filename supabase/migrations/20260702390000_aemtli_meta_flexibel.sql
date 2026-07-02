-- Ämtli-Seiten sollen ohne Programmieren gestaltbar sein: Links zu
-- Vorlagen-Ordnern, eine Erklärung zur eingebauten Funktion, und wo diese
-- Funktion relativ zu Hinweisen/ToDos platziert wird. Lebt an
-- org_aemtli_meta, bleibt also über Lagerjahre hinweg erhalten.
alter table org_aemtli_meta add column links jsonb not null default '[]';
alter table org_aemtli_meta add column funktion_hinweis text;
alter table org_aemtli_meta add column funktion_position text not null default 'mitte'
  check (funktion_position in ('oben', 'mitte', 'unten'));
