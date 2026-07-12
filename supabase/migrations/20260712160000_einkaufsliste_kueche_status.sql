-- Küche kann Einkaufswünsche ablehnen oder auf den nächsten Termin
-- verschieben; die Person, die den Artikel erfasst hat, sieht das dann.
alter table einkaufsliste_items add column if not exists kueche_status text
  check (kueche_status is null or kueche_status in ('abgelehnt', 'verschoben'));
