-- ============================================================
-- Phase 1: Datenbank-Änderungen für Programm-Vereinfachung,
--          Höck-Bereich, Küchen-Mahlzeiten & App Admin
-- ============================================================

-- 1. Mahlzeiten-Raster für Küchen-Ämtli
CREATE TABLE IF NOT EXISTS mahlzeiten (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lager_id    uuid NOT NULL REFERENCES lager(id) ON DELETE CASCADE,
  tag         date NOT NULL,
  mahlzeit    text NOT NULL CHECK (mahlzeit IN ('fruehstueck','mittag','znueni_zvieri','abend','sonstiges')),
  gericht     text NOT NULL DEFAULT '',
  notizen     text DEFAULT '',
  created_at  timestamptz DEFAULT now(),
  updated_at  timestamptz DEFAULT now(),
  UNIQUE (lager_id, tag, mahlzeit)
);

ALTER TABLE mahlzeiten ENABLE ROW LEVEL SECURITY;

CREATE POLICY mahlzeiten_select ON mahlzeiten FOR SELECT USING (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = mahlzeiten.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY mahlzeiten_insert ON mahlzeiten FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = mahlzeiten.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY mahlzeiten_update ON mahlzeiten FOR UPDATE USING (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = mahlzeiten.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY mahlzeiten_delete ON mahlzeiten FOR DELETE USING (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = mahlzeiten.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

-- 2. Höck-Rollen Tabelle
CREATE TABLE IF NOT EXISTS hoeck_rollen (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lager_id    uuid NOT NULL REFERENCES lager(id) ON DELETE CASCADE,
  tag         date NOT NULL,
  rolle       text NOT NULL, -- 'tagwach', 'zmorge', 'nachtruhe' oder eigener Name
  ist_eigene  boolean DEFAULT false, -- true wenn selbst definiert
  sortierung  int DEFAULT 0,
  created_at  timestamptz DEFAULT now(),
  UNIQUE (lager_id, tag, rolle)
);

ALTER TABLE hoeck_rollen ENABLE ROW LEVEL SECURITY;

CREATE POLICY hoeck_rollen_select ON hoeck_rollen FOR SELECT USING (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = hoeck_rollen.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY hoeck_rollen_insert ON hoeck_rollen FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = hoeck_rollen.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY hoeck_rollen_update ON hoeck_rollen FOR UPDATE USING (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = hoeck_rollen.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY hoeck_rollen_delete ON hoeck_rollen FOR DELETE USING (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = hoeck_rollen.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

-- 3. Höck-Rollen-Zuweisungen (Leute pro Rolle)
CREATE TABLE IF NOT EXISTS hoeck_zuweisungen (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  hoeck_rolle_id uuid NOT NULL REFERENCES hoeck_rollen(id) ON DELETE CASCADE,
  leiter_id     uuid NOT NULL REFERENCES anmeldungen_leiter(id) ON DELETE CASCADE,
  created_at    timestamptz DEFAULT now(),
  UNIQUE (hoeck_rolle_id, leiter_id)
);

ALTER TABLE hoeck_zuweisungen ENABLE ROW LEVEL SECURITY;

CREATE POLICY hoeck_zuweisungen_select ON hoeck_zuweisungen FOR SELECT USING (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = hoeck_zuweisungen.hoeck_rolle_id::text::uuid IS NOT NULL)
);

CREATE POLICY hoeck_zuweisungen_insert ON hoeck_zuweisungen FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = hoeck_zuweisungen.hoeck_rolle_id::text::uuid IS NOT NULL)
);

CREATE POLICY hoeck_zuweisungen_update ON hoeck_zuweisungen FOR UPDATE USING (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = hoeck_zuweisungen.hoeck_rolle_id::text::uuid IS NOT NULL)
);

CREATE POLICY hoeck_zuweisungen_delete ON hoeck_zuweisungen FOR DELETE USING (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = hoeck_zuweisungen.hoeck_rolle_id::text::uuid IS NOT NULL)
);

-- 4. Kiosk & Telefon Gruppen-Zuteilung pro Tag
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
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = hoeck_gruppen_dienste.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY hoeck_gruppen_dienste_insert ON hoeck_gruppen_dienste FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = hoeck_gruppen_dienste.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY hoeck_gruppen_dienste_update ON hoeck_gruppen_dienste FOR UPDATE USING (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = hoeck_gruppen_dienste.lager_id AND t.profile_id = auth.uid() AND t.status = 'bestaetigt')
);

CREATE POLICY hoeck_gruppen_dienste_delete ON hoeck_gruppen_dienste FOR DELETE USING (
  EXISTS (SELECT 1 FROM team t WHERE t.lager_id = hoeck_gruppen_dienste.lager_id AND t.profile_id = auth.uid() && t.status = 'bestaetigt')
);

-- 5. App Admin Berechtigung
-- Ein neues Ämtli "App Admin" das Zugriff auf ALLES hat
-- Wird in der App-Logik behandelt, nicht in RLS

-- 6. Programm-Blöcke: ist_essen Flag für Essens-Markierung
ALTER TABLE programm_bloecke ADD COLUMN IF NOT EXISTS ist_essen boolean DEFAULT false;

-- 7. Hilfsfunktion: Höck-Rollen für einen Tag abrufen
CREATE OR REPLACE FUNCTION get_hoeck_rollen_fuer_tag(p_lager_id uuid, p_tag date)
RETURNS TABLE (
  id uuid,
  rolle text,
  ist_eigene boolean,
  sortierung int,
  leute jsonb
) LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
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