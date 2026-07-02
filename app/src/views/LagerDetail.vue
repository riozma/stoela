<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabaseClient'

interface Programmabschnitt {
  zeit: string | null
  programm: string
  verantwortlich: string | null
}
interface MaterialItem {
  name: string
  wer: string | null
}
interface Block {
  id: string
  code: 'LP' | 'LS' | 'LA' | 'ES'
  nummer: string | null
  titel: string
  tag: string | null
  start_zeit: string | null
  end_zeit: string | null
  ort: string | null
  verantwortlich: string | null
  geschichte: string | null
  sicherheitsueberlegungen: string | null
  programmabschnitt: Programmabschnitt[]
  material: MaterialItem[]
  notizen: string | null
}
interface Lager {
  id: string
  name: string
  jahr: number
  ort: string | null
}
interface TN {
  id: string
  vorname: string
  nachname: string
  geburtsdatum: string | null
  geschlecht: string | null
  ahv_nr: string | null
  rolle: 'TN' | 'HL'
  status: string
}
interface LeiterAnmeldung {
  id: string
  vorname: string
  nachname: string
  geburtsdatum: string | null
  geschlecht: string | null
  ahv_nr: string | null
  anwesend_von: string | null
  anwesend_bis: string | null
  status: string
}
interface Aemtli {
  id: string
  name: string
}
interface GruppenMitglied {
  id: string
  name: string
  typ: 'tn' | 'leiter'
  geschlecht: string | null
}
interface Gruppe {
  id: string
  name: string
  mitglieder: GruppenMitglied[]
}

const route = useRoute()
const lagerId = route.params.id as string

const activeTab = ref<'programm' | 'teilnehmer' | 'leiter' | 'gruppen'>('programm')

const lager = ref<Lager | null>(null)
const bloecke = ref<Block[]>([])
const loading = ref(true)
const error = ref('')

// --- Programm ---
const ausgewaehlterTag = ref<string | null>(null)
const offenerBlock = ref<string | null>(null)

const tage = computed(() => {
  const einzigartig = new Set(bloecke.value.map((b) => b.tag).filter((t): t is string => !!t))
  return [...einzigartig].sort()
})

const blocksFuerTag = computed(() =>
  bloecke.value
    .filter((b) => b.tag === ausgewaehlterTag.value)
    .sort((a, b) => (a.start_zeit ?? '').localeCompare(b.start_zeit ?? '')),
)

const codeLabel: Record<Block['code'], string> = {
  LP: 'Lagerprogramm',
  LS: 'Lagersport',
  LA: 'Lageraktivität',
  ES: 'Essen',
}

function formatTag(tag: string) {
  const datum = new Date(tag + 'T00:00:00')
  return new Intl.DateTimeFormat('de-CH', { weekday: 'short', day: 'numeric', month: 'numeric' }).format(datum)
}

function formatZeit(zeit: string | null) {
  if (!zeit) return '–'
  const datum = new Date(zeit)
  if (Number.isNaN(datum.getTime())) return zeit
  return new Intl.DateTimeFormat('de-CH', { hour: '2-digit', minute: '2-digit' }).format(datum)
}

function toggleBlock(id: string) {
  offenerBlock.value = offenerBlock.value === id ? null : id
}

function berechneAlter(geburtsdatum: string | null): number | null {
  if (!geburtsdatum) return null
  const geburt = new Date(geburtsdatum)
  const heute = new Date()
  let alter = heute.getFullYear() - geburt.getFullYear()
  const monatDiff = heute.getMonth() - geburt.getMonth()
  if (monatDiff < 0 || (monatDiff === 0 && heute.getDate() < geburt.getDate())) alter--
  return alter
}

// --- Teilnehmer (TN) ---
const tnListe = ref<TN[]>([])
const tnForm = ref({ vorname: '', nachname: '', geburtsdatum: '', geschlecht: '', notfallkontakt: '', eltern_email: '' })
const tnSpeichern = ref(false)
const tnFehler = ref('')

async function ladeTeilnehmer() {
  const { data, error: err } = await supabase
    .from('anmeldungen_tn')
    .select('id, vorname, nachname, geburtsdatum, geschlecht, ahv_nr, rolle, status')
    .eq('lager_id', lagerId)
    .order('nachname')
  if (!err) tnListe.value = data ?? []
}

async function tnHinzufuegen() {
  tnFehler.value = ''
  tnSpeichern.value = true
  const { error: err } = await supabase.from('anmeldungen_tn').insert({
    lager_id: lagerId,
    vorname: tnForm.value.vorname,
    nachname: tnForm.value.nachname,
    geburtsdatum: tnForm.value.geburtsdatum,
    geschlecht: tnForm.value.geschlecht || null,
    notfallkontakt: tnForm.value.notfallkontakt,
    eltern_email: tnForm.value.eltern_email,
  })
  tnSpeichern.value = false
  if (err) {
    tnFehler.value = err.message
    return
  }
  tnForm.value = { vorname: '', nachname: '', geburtsdatum: '', geschlecht: '', notfallkontakt: '', eltern_email: '' }
  await ladeTeilnehmer()
}

async function tnRolleAendern(tn: TN, rolle: 'TN' | 'HL') {
  await supabase.from('anmeldungen_tn').update({ rolle }).eq('id', tn.id)
  tn.rolle = rolle
}

// --- Leiter ---
const leiterListe = ref<LeiterAnmeldung[]>([])
const leiterForm = ref({ vorname: '', nachname: '', geburtsdatum: '', geschlecht: '', email: '', anwesend_von: '', anwesend_bis: '' })
const leiterSpeichern = ref(false)
const leiterFehler = ref('')
const aemtliListe = ref<Aemtli[]>([])
const leiterRollenMap = ref<Record<string, Aemtli[]>>({})
const neueRolleName = ref<Record<string, string>>({})

async function ladeLeiter() {
  const { data, error: err } = await supabase
    .from('anmeldungen_leiter')
    .select('id, vorname, nachname, geburtsdatum, geschlecht, ahv_nr, anwesend_von, anwesend_bis, status')
    .eq('lager_id', lagerId)
    .order('nachname')
  if (!err) leiterListe.value = data ?? []
}

async function ladeAemtli() {
  const { data, error: err } = await supabase.from('aemtli').select('id, name').order('name')
  if (!err) aemtliListe.value = data ?? []
}

async function ladeLeiterRollen() {
  const { data, error: err } = await supabase
    .from('leiter_rollen')
    .select('anmeldung_leiter_id, aemtli:aemtli_id (id, name)')
  if (err) return
  const map: Record<string, Aemtli[]> = {}
  for (const row of data ?? []) {
    const aemtli = row.aemtli as unknown as Aemtli
    if (!map[row.anmeldung_leiter_id]) map[row.anmeldung_leiter_id] = []
    map[row.anmeldung_leiter_id].push(aemtli)
  }
  leiterRollenMap.value = map
}

async function leiterHinzufuegen() {
  leiterFehler.value = ''
  leiterSpeichern.value = true
  const { error: err } = await supabase.from('anmeldungen_leiter').insert({
    lager_id: lagerId,
    vorname: leiterForm.value.vorname,
    nachname: leiterForm.value.nachname,
    geburtsdatum: leiterForm.value.geburtsdatum || null,
    geschlecht: leiterForm.value.geschlecht || null,
    email: leiterForm.value.email,
    anwesend_von: leiterForm.value.anwesend_von || null,
    anwesend_bis: leiterForm.value.anwesend_bis || null,
  })
  leiterSpeichern.value = false
  if (err) {
    leiterFehler.value = err.message
    return
  }
  leiterForm.value = { vorname: '', nachname: '', geburtsdatum: '', geschlecht: '', email: '', anwesend_von: '', anwesend_bis: '' }
  await ladeLeiter()
}

async function rolleZuweisen(anmeldungLeiterId: string, aemtliId: string) {
  if (!aemtliId) return
  await supabase.from('leiter_rollen').insert({ anmeldung_leiter_id: anmeldungLeiterId, aemtli_id: aemtliId })
  await ladeLeiterRollen()
}

async function neueRolleErstellen(anmeldungLeiterId: string) {
  const name = (neueRolleName.value[anmeldungLeiterId] ?? '').trim()
  if (!name) return
  const { data, error: err } = await supabase.from('aemtli').insert({ name }).select('id, name').single()
  if (err || !data) return
  aemtliListe.value.push(data)
  aemtliListe.value.sort((a, b) => a.name.localeCompare(b.name))
  neueRolleName.value[anmeldungLeiterId] = ''
  await rolleZuweisen(anmeldungLeiterId, data.id)
}

// --- Gruppen ---
const gruppenListe = ref<Gruppe[]>([])
const anzahlGruppenInput = ref(4)
const gruppenErstellen = ref(false)
const gruppenFehler = ref('')

async function ladeGruppen() {
  const { data, error: err } = await supabase
    .from('lagergruppen')
    .select(
      `id, name,
       gruppen_mitglieder (
         id, anmeldung_tn_id, anmeldung_leiter_id,
         anmeldungen_tn ( vorname, nachname, geschlecht ),
         anmeldungen_leiter ( vorname, nachname, geschlecht )
       )`,
    )
    .eq('lager_id', lagerId)
    .order('name')
  if (err) return
  gruppenListe.value = (data ?? []).map((g: any) => ({
    id: g.id,
    name: g.name,
    mitglieder: (g.gruppen_mitglieder ?? []).map((m: any) => {
      const person = m.anmeldungen_tn ?? m.anmeldungen_leiter
      return {
        id: m.id,
        name: person ? `${person.vorname} ${person.nachname}` : '?',
        typ: m.anmeldung_tn_id ? 'tn' : 'leiter',
        geschlecht: person?.geschlecht ?? null,
      }
    }),
  }))
}

function interleaveNachGeschlecht<T extends { geschlecht: string | null; alter?: number | null }>(liste: T[]): T[] {
  const buckets: Record<string, T[]> = { m: [], w: [], d: [], unbekannt: [] }
  for (const person of liste) {
    const key = person.geschlecht ?? 'unbekannt'
    ;(buckets[key] ?? buckets.unbekannt).push(person)
  }
  for (const bucket of Object.values(buckets)) {
    bucket.sort((a, b) => (b.alter ?? 0) - (a.alter ?? 0))
  }
  const ergebnis: T[] = []
  const indices: Record<string, number> = { m: 0, w: 0, d: 0, unbekannt: 0 }
  let verbleibend = liste.length
  while (verbleibend > 0) {
    for (const key of Object.keys(buckets)) {
      if (indices[key] < buckets[key].length) {
        ergebnis.push(buckets[key][indices[key]])
        indices[key]++
        verbleibend--
      }
    }
  }
  return ergebnis
}

function schlangenVerteilung<T>(liste: T[], anzahlGruppen: number): T[][] {
  const gruppen: T[][] = Array.from({ length: anzahlGruppen }, () => [])
  let index = 0
  let richtung = 1
  for (const person of liste) {
    gruppen[index].push(person)
    index += richtung
    if (index === anzahlGruppen) {
      index = anzahlGruppen - 1
      richtung = -1
    } else if (index < 0) {
      index = 0
      richtung = 1
    }
  }
  return gruppen
}

async function gruppenAutomatischBilden() {
  gruppenFehler.value = ''
  const anzahl = anzahlGruppenInput.value
  if (anzahl < 1) return
  gruppenErstellen.value = true

  const tnMitAlter = tnListe.value.map((tn) => ({ ...tn, alter: berechneAlter(tn.geburtsdatum) }))
  const leiterMitAlter = leiterListe.value.map((l) => ({ ...l, alter: berechneAlter(l.geburtsdatum) }))

  const tnVerteilung = schlangenVerteilung(interleaveNachGeschlecht(tnMitAlter), anzahl)
  const leiterVerteilung = schlangenVerteilung(interleaveNachGeschlecht(leiterMitAlter), anzahl)

  // Alte Gruppen dieses Lagers ersetzen
  const alteGruppenIds = gruppenListe.value.map((g) => g.id)
  if (alteGruppenIds.length) {
    await supabase.from('lagergruppen').delete().in('id', alteGruppenIds)
  }

  for (let i = 0; i < anzahl; i++) {
    const { data: neueGruppe, error: err } = await supabase
      .from('lagergruppen')
      .insert({ lager_id: lagerId, name: `Gruppe ${i + 1}` })
      .select('id')
      .single()
    if (err || !neueGruppe) {
      gruppenFehler.value = err?.message ?? 'Gruppe konnte nicht erstellt werden.'
      continue
    }
    const mitgliederRows = [
      ...tnVerteilung[i].map((tn) => ({ lagergruppe_id: neueGruppe.id, anmeldung_tn_id: tn.id })),
      ...leiterVerteilung[i].map((l) => ({ lagergruppe_id: neueGruppe.id, anmeldung_leiter_id: l.id })),
    ]
    if (mitgliederRows.length) {
      await supabase.from('gruppen_mitglieder').insert(mitgliederRows)
    }
  }

  gruppenErstellen.value = false
  await ladeGruppen()
}

onMounted(async () => {
  loading.value = true

  const [{ data: lagerData, error: lagerError }, { data: bloeckeData, error: bloeckeError }] = await Promise.all([
    supabase.from('lager').select('id, name, jahr, ort').eq('id', lagerId).single(),
    supabase
      .from('programmbloecke')
      .select(
        'id, code, nummer, titel, tag, start_zeit, end_zeit, ort, verantwortlich, geschichte, sicherheitsueberlegungen, programmabschnitt, material, notizen',
      )
      .eq('lager_id', lagerId),
  ])

  if (lagerError || bloeckeError) {
    error.value = lagerError?.message ?? bloeckeError?.message ?? 'Lager konnte nicht geladen werden.'
    loading.value = false
    return
  }

  lager.value = lagerData
  bloecke.value = bloeckeData ?? []
  ausgewaehlterTag.value = tage.value[0] ?? null

  await Promise.all([ladeTeilnehmer(), ladeLeiter(), ladeAemtli(), ladeLeiterRollen(), ladeGruppen()])

  loading.value = false
})
</script>

<template>
  <main>
    <p><router-link to="/lager">← Zurück zur Übersicht</router-link></p>

    <p v-if="loading">Lade...</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <template v-else-if="lager">
      <h1>{{ lager.name }}</h1>
      <p class="hint" v-if="lager.ort">📍 {{ lager.ort }}</p>

      <nav class="tabs">
        <button :class="{ aktiv: activeTab === 'programm' }" @click="activeTab = 'programm'">Programm</button>
        <button :class="{ aktiv: activeTab === 'teilnehmer' }" @click="activeTab = 'teilnehmer'">
          Teilnehmer ({{ tnListe.length }})
        </button>
        <button :class="{ aktiv: activeTab === 'leiter' }" @click="activeTab = 'leiter'">
          Leiter ({{ leiterListe.length }})
        </button>
        <button :class="{ aktiv: activeTab === 'gruppen' }" @click="activeTab = 'gruppen'">Gruppen</button>
      </nav>

      <!-- Programm -->
      <section v-if="activeTab === 'programm'">
        <p v-if="!bloecke.length" class="hint">
          Noch keine Programmblöcke erfasst. Über den eCamp-PDF-Import lassen sich alle Blöcke auf einmal einlesen.
        </p>

        <nav v-else class="tage">
          <button
            v-for="tag in tage"
            :key="tag"
            :class="{ aktiv: tag === ausgewaehlterTag }"
            @click="ausgewaehlterTag = tag; offenerBlock = null"
          >
            {{ formatTag(tag) }}
          </button>
        </nav>

        <div v-if="blocksFuerTag.length" class="timetable">
          <template v-for="b in blocksFuerTag" :key="b.id">
            <div class="block-zeile" @click="toggleBlock(b.id)">
              <span class="zeit">{{ formatZeit(b.start_zeit) }}–{{ formatZeit(b.end_zeit) }}</span>
              <span class="code" :class="'code-' + b.code" :title="codeLabel[b.code]">{{ b.code }}</span>
              <span class="titel">{{ b.nummer ? b.nummer + ' ' : '' }}{{ b.titel }}</span>
              <span class="verantwortlich">{{ b.verantwortlich }}</span>
            </div>
            <div v-if="offenerBlock === b.id" class="block-detail">
              <p v-if="b.ort"><strong>Ort:</strong> {{ b.ort }}</p>
              <p v-if="b.geschichte"><strong>Geschichte:</strong> {{ b.geschichte }}</p>
              <p v-if="b.sicherheitsueberlegungen">
                <strong>Sicherheitsüberlegungen:</strong> {{ b.sicherheitsueberlegungen }}
              </p>

              <div v-if="b.programmabschnitt?.length">
                <strong>Programmabschnitt</strong>
                <table class="abschnitt-tabelle">
                  <tbody>
                    <tr v-for="(a, i) in b.programmabschnitt" :key="i">
                      <td class="abschnitt-zeit">{{ a.zeit }}</td>
                      <td>{{ a.programm }}</td>
                      <td class="abschnitt-verantwortlich">{{ a.verantwortlich }}</td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <div v-if="b.material?.length">
                <strong>Material</strong>
                <ul class="material-liste">
                  <li v-for="(m, i) in b.material" :key="i">{{ m.name }} <span v-if="m.wer">– {{ m.wer }}</span></li>
                </ul>
              </div>

              <p v-if="b.notizen"><strong>Notizen:</strong> {{ b.notizen }}</p>
            </div>
          </template>
        </div>
      </section>

      <!-- Teilnehmer -->
      <section v-if="activeTab === 'teilnehmer'">
        <p class="hint">
          Öffentliches Anmeldeformular:
          <router-link :to="`/lager/${lagerId}/anmelden-tn`">/lager/{{ lagerId }}/anmelden-tn</router-link>
        </p>

        <table v-if="tnListe.length" class="liste">
          <thead>
            <tr>
              <th>Name</th>
              <th>Alter</th>
              <th>Geschlecht</th>
              <th>Rolle</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="tn in tnListe" :key="tn.id">
              <td>{{ tn.vorname }} {{ tn.nachname }}</td>
              <td>{{ berechneAlter(tn.geburtsdatum) ?? '–' }}</td>
              <td>{{ tn.geschlecht ?? '–' }}</td>
              <td>
                <select :value="tn.rolle" @change="tnRolleAendern(tn, ($event.target as HTMLSelectElement).value as 'TN' | 'HL')">
                  <option value="TN">TN</option>
                  <option value="HL">HL</option>
                </select>
              </td>
              <td>{{ tn.status }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else class="hint">Noch keine Teilnehmer-Anmeldungen.</p>

        <h3>Manuell erfassen</h3>
        <form @submit.prevent="tnHinzufuegen" class="inline-form">
          <input v-model="tnForm.vorname" placeholder="Vorname" required />
          <input v-model="tnForm.nachname" placeholder="Nachname" required />
          <input v-model="tnForm.geburtsdatum" type="date" required />
          <select v-model="tnForm.geschlecht">
            <option value="">Geschlecht</option>
            <option value="m">m</option>
            <option value="w">w</option>
            <option value="d">d</option>
          </select>
          <input v-model="tnForm.notfallkontakt" placeholder="Notfallkontakt" required />
          <input v-model="tnForm.eltern_email" type="email" placeholder="E-Mail Eltern" required />
          <button type="submit" :disabled="tnSpeichern">{{ tnSpeichern ? 'Speichere...' : 'Hinzufügen' }}</button>
        </form>
        <p v-if="tnFehler" class="error">{{ tnFehler }}</p>
      </section>

      <!-- Leiter -->
      <section v-if="activeTab === 'leiter'">
        <p class="hint">
          Öffentliches Anmeldeformular:
          <router-link :to="`/lager/${lagerId}/anmelden-leiter`">/lager/{{ lagerId }}/anmelden-leiter</router-link>
        </p>

        <table v-if="leiterListe.length" class="liste">
          <thead>
            <tr>
              <th>Name</th>
              <th>Alter</th>
              <th>Anwesend</th>
              <th>Ämtli / Rollen</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="l in leiterListe" :key="l.id">
              <td>{{ l.vorname }} {{ l.nachname }}</td>
              <td>{{ berechneAlter(l.geburtsdatum) ?? '–' }}</td>
              <td>{{ l.anwesend_von ?? '–' }} – {{ l.anwesend_bis ?? '–' }}</td>
              <td>
                <span v-for="r in leiterRollenMap[l.id] ?? []" :key="r.id" class="rollen-pill">{{ r.name }}</span>
                <select @change="rolleZuweisen(l.id, ($event.target as HTMLSelectElement).value); ($event.target as HTMLSelectElement).value = ''">
                  <option value="">+ Rolle</option>
                  <option v-for="a in aemtliListe" :key="a.id" :value="a.id">{{ a.name }}</option>
                </select>
                <input
                  v-model="neueRolleName[l.id]"
                  placeholder="neue Rolle..."
                  class="neue-rolle-input"
                  @keyup.enter="neueRolleErstellen(l.id)"
                />
              </td>
            </tr>
          </tbody>
        </table>
        <p v-else class="hint">Noch keine Leiter-Anmeldungen.</p>

        <h3>Manuell erfassen</h3>
        <form @submit.prevent="leiterHinzufuegen" class="inline-form">
          <input v-model="leiterForm.vorname" placeholder="Vorname" required />
          <input v-model="leiterForm.nachname" placeholder="Nachname" required />
          <input v-model="leiterForm.geburtsdatum" type="date" />
          <select v-model="leiterForm.geschlecht">
            <option value="">Geschlecht</option>
            <option value="m">m</option>
            <option value="w">w</option>
            <option value="d">d</option>
          </select>
          <input v-model="leiterForm.email" type="email" placeholder="E-Mail" required />
          <input v-model="leiterForm.anwesend_von" type="date" />
          <input v-model="leiterForm.anwesend_bis" type="date" />
          <button type="submit" :disabled="leiterSpeichern">{{ leiterSpeichern ? 'Speichere...' : 'Hinzufügen' }}</button>
        </form>
        <p v-if="leiterFehler" class="error">{{ leiterFehler }}</p>
      </section>

      <!-- Gruppen -->
      <section v-if="activeTab === 'gruppen'">
        <p class="hint">
          Verteilt alle Teilnehmer und Leiter automatisch auf die gewählte Anzahl Gruppen – ausgewogen nach
          Geschlecht und Alter, Leiter gut über alle Gruppen verteilt. Ein erneuter Klick verteilt neu.
        </p>
        <div class="inline-form">
          <label>
            Anzahl Gruppen
            <input v-model.number="anzahlGruppenInput" type="number" min="1" max="20" />
          </label>
          <button @click="gruppenAutomatischBilden" :disabled="gruppenErstellen">
            {{ gruppenErstellen ? 'Verteile...' : 'Gruppen automatisch bilden' }}
          </button>
        </div>
        <p v-if="gruppenFehler" class="error">{{ gruppenFehler }}</p>

        <div v-if="gruppenListe.length" class="gruppen-grid">
          <div v-for="g in gruppenListe" :key="g.id" class="gruppe-karte">
            <h4>{{ g.name }}</h4>
            <ul>
              <li v-for="m in g.mitglieder" :key="m.id" :class="m.typ">
                {{ m.name }} <span class="hint">({{ m.typ === 'leiter' ? 'Leiter' : 'TN' }})</span>
              </li>
            </ul>
          </div>
        </div>
        <p v-else class="hint">Noch keine Gruppen gebildet.</p>
      </section>
    </template>
  </main>
</template>

<style scoped>
main {
  max-width: 900px;
  margin: 2rem auto;
  padding: 0 1rem;
}
.hint {
  color: var(--color-text-muted);
  font-size: 0.9rem;
}
.tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  margin: 1.25rem 0;
  border-bottom: 1px solid var(--color-border);
  padding-bottom: 0.75rem;
}
.tabs button {
  background: none;
  color: var(--color-text-muted);
  border: 1px solid var(--color-border);
}
.tabs button.aktiv {
  background: var(--color-accent);
  color: #fdfbf3;
  border-color: var(--color-accent);
}
.tage {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  margin: 1rem 0;
}
.tage button {
  background: var(--color-surface);
  color: var(--color-text);
  border: 1px solid var(--color-border);
}
.tage button.aktiv {
  background: var(--color-accent);
  color: #fdfbf3;
  border-color: var(--color-accent);
}
.timetable {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  overflow: hidden;
}
.block-zeile {
  display: grid;
  grid-template-columns: 100px 40px 1fr 160px;
  gap: 0.75rem;
  align-items: center;
  padding: 0.6rem 0.9rem;
  border-bottom: 1px solid var(--color-border);
  cursor: pointer;
}
.block-zeile:hover {
  background: var(--color-surface-muted);
}
.zeit {
  font-size: 0.85rem;
  color: var(--color-text-muted);
  font-variant-numeric: tabular-nums;
}
.code {
  font-size: 0.7rem;
  font-weight: 700;
  text-align: center;
  padding: 0.2rem 0;
  border-radius: var(--radius-pill);
  color: #fdfbf3;
}
.code-LP {
  background: #6b7fa8;
}
.code-LS {
  background: var(--color-accent);
}
.code-LA {
  background: #c98a3f;
}
.code-ES {
  background: #8a7f68;
}
.titel {
  font-size: 0.95rem;
}
.verantwortlich {
  font-size: 0.8rem;
  color: var(--color-text-muted);
  text-align: right;
}
.block-detail {
  padding: 0.85rem 1.25rem 1.1rem;
  background: var(--color-surface-muted);
  border-bottom: 1px solid var(--color-border);
  font-size: 0.9rem;
}
.block-detail p {
  margin: 0.4rem 0;
}
.abschnitt-tabelle {
  width: 100%;
  border-collapse: collapse;
  margin: 0.4rem 0 0.8rem;
  font-size: 0.85rem;
}
.abschnitt-tabelle td {
  padding: 0.3rem 0.5rem 0.3rem 0;
  border-bottom: 1px solid var(--color-border);
  vertical-align: top;
}
.abschnitt-zeit {
  white-space: nowrap;
  color: var(--color-text-muted);
}
.abschnitt-verantwortlich {
  color: var(--color-text-muted);
  white-space: nowrap;
}
.material-liste {
  margin: 0.4rem 0 0.8rem;
  padding-left: 1.2rem;
}
.liste {
  width: 100%;
  border-collapse: collapse;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  margin: 1rem 0;
  font-size: 0.9rem;
}
.liste th,
.liste td {
  text-align: left;
  padding: 0.5rem 0.7rem;
  border-bottom: 1px solid var(--color-border);
  vertical-align: middle;
}
.liste th {
  color: var(--color-text-muted);
  font-weight: 700;
  font-size: 0.8rem;
}
.rollen-pill {
  display: inline-block;
  background: var(--color-pill-bg);
  color: var(--color-text);
  border-radius: var(--radius-pill);
  padding: 0.15rem 0.6rem;
  font-size: 0.78rem;
  margin: 0.1rem 0.3rem 0.1rem 0;
}
.neue-rolle-input {
  width: 110px;
  margin-left: 0.4rem;
}
.inline-form {
  display: flex;
  flex-wrap: wrap;
  gap: 0.6rem;
  align-items: center;
  margin: 0.75rem 0 1rem;
}
.inline-form label {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  font-size: 0.8rem;
  color: var(--color-text-muted);
}
.gruppen-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 0.75rem;
  margin-top: 1rem;
}
.gruppe-karte {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 0.85rem 1rem;
}
.gruppe-karte h4 {
  margin: 0 0 0.5rem;
}
.gruppe-karte ul {
  list-style: none;
  padding: 0;
  margin: 0;
  font-size: 0.88rem;
}
.gruppe-karte li {
  padding: 0.15rem 0;
}
.gruppe-karte li.leiter {
  font-weight: 700;
}
.error {
  color: var(--color-danger);
}
</style>
