-- Neue optionale Mahlzeit "Dessert" zusätzlich zu fruehstueck/zmittag/
-- znacht/jause ("Jause" wird im Frontend neu als "Pause" beschriftet,
-- interner Wert bleibt aus Kompatibilitätsgründen "jause").
alter table einkaufsliste_items drop constraint einkaufsliste_items_mahlzeit_check;
alter table einkaufsliste_items add constraint einkaufsliste_items_mahlzeit_check
  check (mahlzeit is null or mahlzeit = any (array['fruehstueck','zmittag','znacht','jause','dessert']));

alter table mahlzeit_vorlagen drop constraint mahlzeit_vorlagen_mahlzeit_check;
alter table mahlzeit_vorlagen add constraint mahlzeit_vorlagen_mahlzeit_check
  check (mahlzeit = any (array['fruehstueck','zmittag','znacht','jause','dessert']));

alter table mahlzeiten drop constraint mahlzeiten_mahlzeit_check;
alter table mahlzeiten add constraint mahlzeiten_mahlzeit_check
  check (mahlzeit = any (array['fruehstueck','zmittag','znacht','jause','dessert']));
