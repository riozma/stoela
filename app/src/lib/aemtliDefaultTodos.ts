export interface AemtliTodo {
  id: string
  text: string
  done: boolean
}

export const DEFAULT_TODOS: Record<string, string[]> = {
  Küche: [
    'Einkaufstermin für Woche 1 setzen',
    'Allergien/Unverträglichkeiten TN prüfen',
    'Kochplan für erste Woche finalisieren',
  ],
  Finanzen: [
    'TN-Beiträge bis Anmeldeschluss prüfen',
    'Quittungen wöchentlich abarbeiten',
    'Kassenstand dokumentieren',
  ],
  Sport: [
    'Material Sportprogramm inventarisieren',
    'Sicherheitsbriefing Sport vorbereiten',
  ],
  Sanität: [
    'Erste-Hilfe-Koffer prüfen',
    'Notfallnummern aushängen',
    'Medikamentenliste TN sichten',
  ],
  Material: [
    'Programmmaterial LP 1.1 packen',
    'Feuerholz/Material Lagerfeuer organisieren',
  ],
  Programm: [
    'Höck-Notizen täglich pflegen',
    'Verantwortliche je Block kontrollieren',
  ],
  Lagerleitung: [
    'Leiteranfragen bearbeiten',
    'Gruppenverteilung prüfen',
    'Team-Meeting planen',
  ],
}

export function initialTodosForAemtli(name: string): AemtliTodo[] {
  const texts = DEFAULT_TODOS[name] ?? [`Aufgaben für ${name} ergänzen`]
  return texts.map((text) => ({
    id: crypto.randomUUID(),
    text,
    done: false,
  }))
}
