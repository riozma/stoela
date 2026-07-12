-- Migration 20260710150000 wollte lager_leiter_aus_verein_hinzufuegen() um
-- p_vorname/p_nachname erweitern, hat mit "create or replace" aber wegen der
-- geänderten Signatur eine ZUSÄTZLICHE Overload-Variante erzeugt statt die
-- alte zu ersetzen. Dadurch war der Funktionsaufruf aus dem Frontend
-- (6 Parameter, passt auf beide Overloads) ambig -> "Lager erstellen" und
-- "Leiter aus Verein hinzufügen" schlugen fehl. Fix: alte 6-Parameter-
-- Variante entfernen, die 8-Parameter-Variante (mit Defaults) bleibt.
drop function if exists public.lager_leiter_aus_verein_hinzufuegen(uuid, uuid, uuid, boolean, date, date);
