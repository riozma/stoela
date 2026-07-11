-- ============================================================
-- Höck-Bereich (Rollen, Zuweisungen, Gruppen-Dienste) &
-- Programm ist_essen-Flag.
--
-- Korrigierte Fassung: die ursprüngliche Migration referenzierte
-- die Tabelle als "programm_bloecke" (heisst "programmbloecke") und
-- übersah, dass "hoeck_rollen" bereits mit anderem Schema existierte
-- (leer, aus 20260702340000) – darum lief sie nie durch.
-- "mahlzeiten" bleibt beim bestehenden Schema (titel/beschreibung/
-- material), das der Menüplaner in AemtliKueche verwendet.
-- ============================================================

-- 1. Höck-Rollen: altes, ungenutztes Schema ersetzen (Tabelle ist leer)
DROP TABLE IF EXISTS hoeck_rollen CASCADE;

CREATE TABLE hoeck_rollen (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lager_id    uuid NOT NULL REFERENCES lager(id) ON DELETE CASCADE,
  tag         date NOT NULL,
  rolle       text NOT NULL, -- 'tagwach', 'zmorge', 'nachtruhe' oder eigener Name
  ist_eigene  boolean DEFAULT false,
  sortierung  int DEFAULT 0,
  created_at  timestamptz DEFAULT now(),
  UNIQUE (lager_id, tag, rolle)
);

ALTER TABLE hoeck_rollen ENABLE ROW LEVEL SECURITY;

CREATE POLICY hoeck_rollen_select ON hoeck_rollen FOR SELECT USING (
  EXISTS (SELECT 1 FROM lager_leiter t WHERE t.lager_id = hoeck_rollen.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY hoeck_rollen_insert ON hoeck_rollen FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM lager_leiter t WHERE t.lager_id = hoeck_rollen.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY hoeck_rollen_update ON hoeck_rollen FOR UPDATE USING (
  EXISTS (SELECT 1 FROM lager_leiter t WHERE t.lager_id = hoeck_rollen.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY hoeck_rollen_delete ON hoeck_rollen FOR DELETE USING (
  EXISTS (SELECT 1 FROM lager_leiter t WHERE t.lager_id = hoeck_rollen.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

-- 2. Höck-Rollen-Zuweisungen (Leute pro Rolle)
CREATE TABLE IF NOT EXISTS hoeck_zuweisungen (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hoeck_rolle_id uuid NOT NULL REFERENCES hoeck_rollen(id) ON DELETE CASCADE,
  leiter_id     uuid NOT NULL REFERENCES anmeldungen_leiter(id) ON DELETE CASCADE,
  created_at    timestamptz DEFAULT now(),
  UNIQUE (hoeck_rolle_id, leiter_id)
);

ALTER TABLE hoeck_zuweisungen ENABLE ROW LEVEL SECURITY;

CREATE POLICY hoeck_zuweisungen_select ON hoeck_zuweisungen FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM lager_leiter t
    WHERE t.lager_id = (SELECT hr.lager_id FROM hoeck_rollen hr WHERE hr.id = hoeck_zuweisungen.hoeck_rolle_id)
    AND t.profile_id = auth.uid()
    AND t.status = 'bestaetigt'
  )
);

CREATE POLICY hoeck_zuweisungen_insert ON hoeck_zuweisungen FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM lager_leiter t
    WHERE t.lager_id = (SELECT hr.lager_id FROM hoeck_rollen hr WHERE hr.id = hoeck_zuweisungen.hoeck_rolle_id)
    AND t.profile_id = auth.uid()
    AND t.status = 'bestaetigt'
  )
);

CREATE POLICY hoeck_zuweisungen_update ON hoeck_zuweisungen FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM lager_leiter t
    WHERE t.lager_id = (SELECT hr.lager_id FROM hoeck_rollen hr WHERE hr.id = hoeck_zuweisungen.hoeck_rolle_id)
    AND t.profile_id = auth.uid()
    AND t.status = 'bestaetigt'
  )
);

CREATE POLICY hoeck_zuweisungen_delete ON hoeck_zuweisungen FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM lager_leiter t
    WHERE t.lager_id = (SELECT hr.lager_id FROM hoeck_rollen hr WHERE hr.id = hoeck_zuweisungen.hoeck_rolle_id)
    AND t.profile_id = auth.uid()
    AND t.status = 'bestaetigt'
  )
);

-- 3. Kiosk & Telefon Gruppen-Zuteilung pro Tag
CREATE TABLE IF NOT EXISTS hoeck_gruppen_dienste (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lager_id    uuid NOT NULL REFERENCES lager(id) ON DELETE CASCADE,
  tag         date NOT NULL,
  dienst      text NOT NULL CHECK (dienst IN ('kiosk', 'telefon')),
  gruppen_name text NOT NULL,
  created_at  timestamptz DEFAULT now(),
  UNIQUE (lager_id, tag, dienst)
);

ALTER TABLE hoeck_gruppen_dienste ENABLE ROW LEVEL SECURITY;

CREATE POLICY hoeck_gruppen_dienste_select ON hoeck_gruppen_dienste FOR SELECT USING (
  EXISTS (SELECT 1 FROM lager_leiter t WHERE t.lager_id = hoeck_gruppen_dienste.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY hoeck_gruppen_dienste_insert ON hoeck_gruppen_dienste FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM lager_leiter t WHERE t.lager_id = hoeck_gruppen_dienste.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY hoeck_gruppen_dienste_update ON hoeck_gruppen_dienste FOR UPDATE USING (
  EXISTS (SELECT 1 FROM lager_leiter t WHERE t.lager_id = hoeck_gruppen_dienste.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY hoeck_gruppen_dienste_delete ON hoeck_gruppen_dienste FOR DELETE USING (
  EXISTS (SELECT 1 FROM lager_leiter t WHERE t.lager_id = hoeck_gruppen_dienste.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

-- 4. Programm-Blöcke: ist_essen Flag für Essens-Markierung
ALTER TABLE programmbloecke ADD COLUMN IF NOT EXISTS ist_essen boolean DEFAULT false;

-- 5. Hilfsfunktion: Höck-Rollen für einen Tag abrufen
CREATE OR REPLACE FUNCTION get_hoeck_rollen_fuer_tag(p_lager_id uuid, p_tag date)
RETURNS TABLE (
  id uuid,
  rolle text,
  ist_eigene boolean,
  sortierung int,
  leute jsonb
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.can_access_lager(p_lager_id) THEN
    RAISE EXCEPTION 'Kein Zugriff.';
  END IF;
  RETURN QUERY
  SELECT
    hr.id,
    hr.rolle,
    hr.ist_eigene,
    hr.sortierung,
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'id', hz.id,
          'leiter_id', hz.leiter_id,
          'vorname', al.vorname,
          'nachname', al.nachname
        )
      ) FILTER (WHERE hz.id IS NOT NULL),
      '[]'::jsonb
    ) as leute
  FROM hoeck_rollen hr
  LEFT JOIN hoeck_zuweisungen hz ON hz.hoeck_rolle_id = hr.id
  LEFT JOIN anmeldungen_leiter al ON al.id = hz.leiter_id
  WHERE hr.lager_id = p_lager_id AND hr.tag = p_tag
  GROUP BY hr.id, hr.rolle, hr.ist_eigene, hr.sortierung
  ORDER BY hr.sortierung, hr.rolle;
END;
$$;

GRANT EXECUTE ON FUNCTION get_hoeck_rollen_fuer_tag(uuid, date) TO authenticated;
