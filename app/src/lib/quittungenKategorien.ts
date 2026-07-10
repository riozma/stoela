/** Quittungs-Kategorien (Einnahmen / Ausgaben) */

export type QuittungRichtung = 'einnahme' | 'ausgabe'

export interface QuittungKategorie {
  id: string
  label: string
  richtung: QuittungRichtung
}

export const QUITTUNG_KATEGORIEN: QuittungKategorie[] = [
  { id: 'elternbeitraege', label: 'Elternbeiträge', richtung: 'einnahme' },
  { id: 'js_beitraege', label: 'J&S-Beiträge', richtung: 'einnahme' },
  { id: 'vw_sk_einnahme', label: 'Vorweekend/Skiweekend (Einnahme)', richtung: 'einnahme' },
  { id: 'ghk_beitraege', label: 'GHK-Beiträge', richtung: 'einnahme' },
  { id: 'dessertaktien', label: 'Dessertaktien', richtung: 'einnahme' },
  { id: 'gewinn_kiosk', label: 'Gewinn Kiosk', richtung: 'einnahme' },
  { id: 'sponsoring', label: 'Sponsoring', richtung: 'einnahme' },
  { id: 'kleiderboerse_einnahme', label: 'Kleiderbörse Einnahmen', richtung: 'einnahme' },
  { id: 'kuchenstand_einnahme', label: 'Kuchenstand/Spaghetti (Einnahme)', richtung: 'einnahme' },

  { id: 'carreise', label: 'Carreise', richtung: 'ausgabe' },
  { id: 'lagerhaus_grundtaxe', label: 'Lagerhaus Grundtaxe', richtung: 'ausgabe' },
  { id: 'nebenkosten', label: 'Nebenkosten', richtung: 'ausgabe' },
  { id: 'vw_sk_ausgabe', label: 'Vorweekend/Skiweekend (Ausgabe)', richtung: 'ausgabe' },
  { id: 'kurtaxe', label: 'Kurtaxe', richtung: 'ausgabe' },
  { id: 'essen', label: 'Essen', richtung: 'ausgabe' },
  { id: 'verkleidungen', label: 'Verkleidungen/Material', richtung: 'ausgabe' },
  { id: 'material_spesen', label: 'Material/Spesen', richtung: 'ausgabe' },
  { id: 'jubla_vers', label: 'Jubla-Beiträge und Versicherungen', richtung: 'ausgabe' },
  { id: 'js_ghk_leiter', label: 'J+S, GHK – Leiterentschädigung', richtung: 'ausgabe' },
  { id: 'lager_tshirt', label: 'Lager T-Shirt und Merchandise', richtung: 'ausgabe' },
  { id: 'kleiderboerse_ausgabe', label: 'Kleiderbörse/Spaghetti Ausgaben', richtung: 'ausgabe' },
  { id: 'gebuehren_abos', label: 'Gebühren und Abos', richtung: 'ausgabe' },
]

export function kategorieLabel(id: string | null) {
  if (!id) return '–'
  return QUITTUNG_KATEGORIEN.find((k) => k.id === id)?.label ?? id
}

export function kategorienFuerRichtung(richtung: QuittungRichtung) {
  return QUITTUNG_KATEGORIEN.filter((k) => k.richtung === richtung)
}
