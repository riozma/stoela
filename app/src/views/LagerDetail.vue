<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
import { generateIcs, downloadIcs } from '../lib/ics'
import { ladeWetter, type TagesWetter } from '../lib/weather'
import LagerDashboard from '../components/lager/LagerDashboard.vue'
import LagerEinkauf from '../components/lager/LagerEinkauf.vue'
import LagerMap from '../components/lager/LagerMap.vue'
import ProgrammHoeck from '../components/lager/ProgrammHoeck.vue'
import AemtliKueche from '../components/lager/AemtliKueche.vue'
import AemtliFinanzen from '../components/lager/AemtliFinanzen.vue'
import AemtliGeneric from '../components/lager/AemtliGeneric.vue'
import QuittungenPanel from '../components/lager/QuittungenPanel.vue'
import LagerNav from '../components/lager/LagerNav.vue'
import { aemtliSlug, tabIdForAemtli } from '../lib/aemtliSlug'
import { GESCHUETZTE_AEMTLI, istGeschuetztesAemtli } from '../lib/aemtliPermissions'
import { synchronisiereProgrammZuordnungen } from '../lib/programmZuordnung'
import { aemtliName, leiterName, type MaterialMitZuordnung, type NamensZuordnung, type ProgrammabschnittMitZuordnung } from '../lib/nameMatching'

interface Programmabschnitt extends ProgrammabschnittMitZuordnung {}
interface MaterialItem extends MaterialMitZuordnung {}
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
  verantwortlich_zuordnungen: NamensZuordnung[]
}
interface Lager {
  id: string
  name: string
  jahr: number
  ort: string | null
  start_datum: string | null
  end_datum: string | null
  status: string
  ort_lat: number | null
  ort_lng: number | null
  created_by: string | null
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
  profile_id: string | null
  vorname: string
  nachname: string
  email?: string
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
interface LeiterRolleZuweisung {
  zuweisungId: string
  id: string
  name: string
}
interface GruppenMitglied {
  id: string
  name: string
  typ: 'tn' | 'leiter'
  geschlecht: string | null
  anmeldungId: string
}
interface Gruppe {
  id: string
  name: string
  mitglieder: GruppenMitglied[]
}
interface TeamMitglied {
  id: string
  profile_id: string
  rolle: string
  status: string
  profiles: { email: string; vorname: string | null; nachname: string | null }
}
interface Reminder {
  id: string
  titel: string
  nachricht: string | null
  faellig_am: string
  status: string
  gesendet_am: string | null
  ziel_rolle: string | null
  ziel_aemtli_id: string | null
}

const route = useRoute()
const { session } = useAuth()
const lagerId = route.params.id as string

type Tab = 'dashboard' | 'programm' | 'teilnehmer' | 'leiter' | 'gruppen' | 'einkauf' | 'team' | 'reminders' | 'einstellungen' | 'quittungen' | string
const activeTab = ref<Tab>('dashboard')
const profil = ref<{ vorname: string | null; nachname: string | null } | null>(null)
const istKueche = ref(false)
const meineAemtli = ref<Aemtli[]>([])

/** Nur echtes Finanzen-Ämtli – Lagerleitung allein zählt nicht als Kassier */
const hatFinanzenAemtli = computed(() =>
  meineAemtli.value.some((a) => aemtliSlug(a.name) === 'finanzen'),
)
const hatKuecheTab = computed(() =>
  meineAemtli.value.some((a) => aemtliSlug(a.name) === 'kueche'),
)
const zuordnungLade = ref(false)
const zuordnungNachricht = ref('')
const lagerForm = ref({ name: '', ort: '', start_datum: '', end_datum: '', jahr: 0 })
const lagerSpeichern = ref(false)

const lager = ref<Lager | null>(null)
const bloecke = ref<Block[]>([])
const loading = ref(true)
const error = ref('')
const wetter = ref<TagesWetter[]>([])

const isLeitung = computed(() => {
  if (!session.value) return false
  if (lager.value?.created_by === session.value.user.id) return true
  const me = teamListe.value.find((t) => t.profile_id === session.value!.user.id)
  return me?.rolle === 'lagerleitung' && me?.status === 'bestaetigt'
})

const userName = computed(() => {
  const p = profil.value
  if (p?.vorname) return `${p.vorname} ${p.nachname ?? ''}`.trim()
  return session.value?.user.email?.split('@')[0] ?? ''
})

const istAnwesend = computed(() => {
  const heute = new Date().toISOString().slice(0, 10)
  if (lager.value?.start_datum && heute < lager.value.start_datum) return false
  if (lager.value?.end_datum && heute > lager.value.end_datum) return false
  const uid = session.value?.user.id
  const me = leiterListe.value.find((l) => l.profile_id === uid && l.status === 'bestaetigt')
  if (me?.anwesend_von && heute < me.anwesend_von) return false
  if (me?.anwesend_bis && heute > me.anwesend_bis) return false
  return !!teamListe.value.find((t) => t.profile_id === uid && t.status === 'bestaetigt')
})

const leiterAnfragen = computed(() => leiterListe.value.filter((l) => l.status === 'angefragt'))
const leiterBestaetigt = computed(() => leiterListe.value.filter((l) => l.status === 'bestaetigt' || l.status === 'angemeldet'))

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

// --- Teilnehmer ---
const tnListe = ref<TN[]>([])
const tnForm = ref({ vorname: '', nachname: '', geburtsdatum: '', geschlecht: '', notfallkontakt: '', eltern_email: '' })
const tnSpeichern = ref(false)
const tnFehler = ref('')

async function ladeTeilnehmer() {
  const { data } = await supabase
    .from('anmeldungen_tn')
    .select('id, vorname, nachname, geburtsdatum, geschlecht, ahv_nr, rolle, status')
    .eq('lager_id', lagerId)
    .order('nachname')
  tnListe.value = data ?? []
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
  if (err) { tnFehler.value = err.message; return }
  tnForm.value = { vorname: '', nachname: '', geburtsdatum: '', geschlecht: '', notfallkontakt: '', eltern_email: '' }
  await ladeTeilnehmer()
}

async function leiterNachAenderung() {
  await ladeLeiter()
  await ladeMeineAemtli()
  await programmZuordnungenAktualisieren(true)
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
const leiterRollenMap = ref<Record<string, LeiterRolleZuweisung[]>>({})
const neueRolleName = ref<Record<string, string>>({})

async function ladeLeiter() {
  const { data } = await supabase
    .from('anmeldungen_leiter')
    .select('id, profile_id, vorname, nachname, email, geburtsdatum, geschlecht, ahv_nr, anwesend_von, anwesend_bis, status')
    .eq('lager_id', lagerId)
    .order('nachname')
  leiterListe.value = data ?? []
}

async function leiterAnfrageBearbeiten(anmeldungId: string, entscheidung: 'genehmigen' | 'ablehnen') {
  const { error: err } = await supabase.rpc('leiter_anfrage_bearbeiten', {
    p_anmeldung_id: anmeldungId,
    p_entscheidung: entscheidung,
  })
  if (err) { leiterFehler.value = err.message; return }
  await Promise.all([leiterNachAenderung(), ladeTeam()])
}

async function ladeAemtli() {
  const { data } = await supabase.from('aemtli').select('id, name').order('name')
  aemtliListe.value = data ?? []
}

async function ladeLeiterRollen() {
  const leiterIds = leiterListe.value.map((l) => l.id)
  if (!leiterIds.length) {
    leiterRollenMap.value = {}
    return
  }
  const { data } = await supabase
    .from('leiter_rollen')
    .select('id, anmeldung_leiter_id, aemtli:aemtli_id (id, name)')
    .in('anmeldung_leiter_id', leiterIds)
  if (!data) return
  const map: Record<string, LeiterRolleZuweisung[]> = {}
  for (const row of data) {
    const aemtli = row.aemtli as unknown as Aemtli
    if (!aemtli?.id) continue
    if (!map[row.anmeldung_leiter_id]) map[row.anmeldung_leiter_id] = []
    map[row.anmeldung_leiter_id].push({ zuweisungId: row.id, id: aemtli.id, name: aemtli.name })
  }
  leiterRollenMap.value = map
}

async function rolleEntfernen(zuweisungId: string) {
  if (!isLeitung.value) return
  await supabase.from('leiter_rollen').delete().eq('id', zuweisungId)
  await ladeLeiterRollen()
  await ladeMeineAemtli()
  await programmZuordnungenAktualisieren(true)
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
  if (err) { leiterFehler.value = err.message; return }
  leiterForm.value = { vorname: '', nachname: '', geburtsdatum: '', geschlecht: '', email: '', anwesend_von: '', anwesend_bis: '' }
  await leiterNachAenderung()
}

async function rolleZuweisen(anmeldungLeiterId: string, aemtliId: string) {
  if (!aemtliId) return
  leiterFehler.value = ''
  const aemtli = aemtliListe.value.find((a) => a.id === aemtliId)
  if (aemtli && istGeschuetztesAemtli(aemtli.name) && !isLeitung.value) {
    leiterFehler.value = `Nur die Lagerleitung kann «${aemtli.name}» zuweisen.`
    return
  }
  const { error: err } = await supabase.from('leiter_rollen').insert({ anmeldung_leiter_id: anmeldungLeiterId, aemtli_id: aemtliId })
  if (err) { leiterFehler.value = err.message; return }
  await ladeLeiterRollen()
  await ladeMeineAemtli()
  await programmZuordnungenAktualisieren(true)
}

function zuweisbareAemtli(leiterId: string) {
  const zugewiesen = new Set((leiterRollenMap.value[leiterId] ?? []).map((r) => r.id))
  return aemtliListe.value.filter((a) => {
    if (zugewiesen.has(a.id)) return false
    if (istGeschuetztesAemtli(a.name) && !isLeitung.value) return false
    return true
  })
}

async function neueRolleErstellen(anmeldungLeiterId: string) {
  const name = (neueRolleName.value[anmeldungLeiterId] ?? '').trim()
  if (!name) return
  if (istGeschuetztesAemtli(name) && !isLeitung.value) {
    leiterFehler.value = `Das Ämtli «${name}» kann nur die Lagerleitung vergeben.`
    return
  }
  if ((GESCHUETZTE_AEMTLI as readonly string[]).includes(name)) {
    const existing = aemtliListe.value.find((a) => a.name === name)
    if (existing) {
      neueRolleName.value[anmeldungLeiterId] = ''
      await rolleZuweisen(anmeldungLeiterId, existing.id)
      return
    }
  }
  const { data, error: err } = await supabase.from('aemtli').insert({ name }).select('id, name').single()
  if (err || !data) return
  aemtliListe.value.push(data)
  aemtliListe.value.sort((a, b) => a.name.localeCompare(b.name))
  neueRolleName.value[anmeldungLeiterId] = ''
  await rolleZuweisen(anmeldungLeiterId, data.id)
}

// --- Gruppen ---
const gruppenListe = ref<Gruppe[]>([])
const gruppenNamen = ref<Record<string, string>>({})
const anzahlGruppenInput = ref(4)
const gruppenErstellen = ref(false)
const gruppenFehler = ref('')
const neueGruppeName = ref('')

const gruppeTagTn = computed(() => {
  const map: Record<string, string> = {}
  for (const g of gruppenListe.value) {
    for (const m of g.mitglieder) {
      if (m.typ === 'tn') map[m.anmeldungId] = g.name
    }
  }
  return map
})

const gruppeTagLeiter = computed(() => {
  const map: Record<string, string> = {}
  for (const g of gruppenListe.value) {
    for (const m of g.mitglieder) {
      if (m.typ === 'leiter') map[m.anmeldungId] = g.name
    }
  }
  return map
})

async function ladeGruppen() {
  const { data } = await supabase
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

  gruppenListe.value = (data ?? []).map((g: any) => ({
    id: g.id,
    name: g.name,
    mitglieder: (g.gruppen_mitglieder ?? []).map((m: any) => {
      const person = m.anmeldungen_tn ?? m.anmeldungen_leiter
      return {
        id: m.id,
        name: person ? `${person.vorname} ${person.nachname}` : '?',
        typ: m.anmeldung_tn_id ? 'tn' as const : 'leiter' as const,
        geschlecht: person?.geschlecht ?? null,
        anmeldungId: m.anmeldung_tn_id ?? m.anmeldung_leiter_id,
      }
    }),
  }))

  const namen: Record<string, string> = {}
  for (const g of gruppenListe.value) namen[g.id] = g.name
  gruppenNamen.value = namen
}

function interleaveNachGeschlecht<T extends { geschlecht: string | null; alter?: number | null }>(liste: T[]): T[] {
  const buckets: Record<string, T[]> = { m: [], w: [], d: [], unbekannt: [] }
  for (const person of liste) {
    const key = person.geschlecht ?? 'unbekannt'
    ;(buckets[key] ?? buckets.unbekannt).push(person)
  }
  for (const bucket of Object.values(buckets)) bucket.sort((a, b) => (b.alter ?? 0) - (a.alter ?? 0))
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
    if (index === anzahlGruppen) { index = anzahlGruppen - 1; richtung = -1 }
    else if (index < 0) { index = 0; richtung = 1 }
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

  const alteGruppenIds = gruppenListe.value.map((g) => g.id)
  if (alteGruppenIds.length) await supabase.from('lagergruppen').delete().in('id', alteGruppenIds)

  for (let i = 0; i < anzahl; i++) {
    const { data: neueGruppe, error: err } = await supabase
      .from('lagergruppen')
      .insert({ lager_id: lagerId, name: `Gruppe ${i + 1}` })
      .select('id')
      .single()
    if (err || !neueGruppe) { gruppenFehler.value = err?.message ?? 'Fehler'; continue }
    const rows = [
      ...tnVerteilung[i].map((tn) => ({ lagergruppe_id: neueGruppe.id, anmeldung_tn_id: tn.id })),
      ...leiterVerteilung[i].map((l) => ({ lagergruppe_id: neueGruppe.id, anmeldung_leiter_id: l.id })),
    ]
    if (rows.length) await supabase.from('gruppen_mitglieder').insert(rows)
  }

  gruppenErstellen.value = false
  await ladeGruppen()
}

async function gruppeManuellErstellen() {
  gruppenFehler.value = ''
  const name = neueGruppeName.value.trim() || `Gruppe ${gruppenListe.value.length + 1}`
  const { error: err } = await supabase.from('lagergruppen').insert({ lager_id: lagerId, name })
  if (err) { gruppenFehler.value = err.message; return }
  neueGruppeName.value = ''
  await ladeGruppen()
}

async function gruppeUmbenennen(gruppeId: string) {
  const name = (gruppenNamen.value[gruppeId] ?? '').trim()
  if (!name) return
  const alt = gruppenListe.value.find((g) => g.id === gruppeId)?.name
  if (alt === name) return
  const { error: err } = await supabase.from('lagergruppen').update({ name }).eq('id', gruppeId)
  if (err) {
    gruppenFehler.value = err.message
    if (alt) gruppenNamen.value[gruppeId] = alt
    return
  }
  const g = gruppenListe.value.find((x) => x.id === gruppeId)
  if (g) g.name = name
}

async function mitgliedZuGruppeHinzufuegen(gruppeId: string, typ: 'tn' | 'leiter', anmeldungId: string) {
  if (!anmeldungId) return
  gruppenFehler.value = ''
  if (typ === 'tn') {
    await supabase.from('gruppen_mitglieder').delete().eq('anmeldung_tn_id', anmeldungId)
    const { error: err } = await supabase.from('gruppen_mitglieder').insert({ lagergruppe_id: gruppeId, anmeldung_tn_id: anmeldungId })
    if (err) { gruppenFehler.value = err.message; return }
  } else {
    await supabase.from('gruppen_mitglieder').delete().eq('anmeldung_leiter_id', anmeldungId)
    const { error: err } = await supabase.from('gruppen_mitglieder').insert({ lagergruppe_id: gruppeId, anmeldung_leiter_id: anmeldungId })
    if (err) { gruppenFehler.value = err.message; return }
  }
  await ladeGruppen()
}

function tnGruppenLabel(tnId: string, aktuelleGruppeId: string): string {
  for (const g of gruppenListe.value) {
    if (g.id === aktuelleGruppeId) continue
    if (g.mitglieder.some((m) => m.typ === 'tn' && m.anmeldungId === tnId)) return ` (${g.name})`
  }
  return ''
}

function leiterGruppenLabel(leiterId: string, aktuelleGruppeId: string): string {
  for (const g of gruppenListe.value) {
    if (g.id === aktuelleGruppeId) continue
    if (g.mitglieder.some((m) => m.typ === 'leiter' && m.anmeldungId === leiterId)) return ` (${g.name})`
  }
  return ''
}

function tnInGruppe(tnId: string, gruppeId: string) {
  const g = gruppenListe.value.find((x) => x.id === gruppeId)
  return g?.mitglieder.some((m) => m.typ === 'tn' && m.anmeldungId === tnId) ?? false
}

function leiterInGruppe(leiterId: string, gruppeId: string) {
  const g = gruppenListe.value.find((x) => x.id === gruppeId)
  return g?.mitglieder.some((m) => m.typ === 'leiter' && m.anmeldungId === leiterId) ?? false
}

async function mitgliedEntfernen(mitgliedId: string) {
  await supabase.from('gruppen_mitglieder').delete().eq('id', mitgliedId)
  await ladeGruppen()
}

async function gruppeLoeschen(gruppeId: string) {
  await supabase.from('lagergruppen').delete().eq('id', gruppeId)
  await ladeGruppen()
}

// --- Team / Berechtigungen ---
const teamListe = ref<TeamMitglied[]>([])
const freischaltEmail = ref('')
const freischaltFehler = ref('')
const freischaltNachricht = ref('')

async function ladeTeam() {
  const { data } = await supabase
    .from('lager_leiter')
    .select('id, profile_id, rolle, status, profiles(email, vorname, nachname)')
    .eq('lager_id', lagerId)
  teamListe.value = (data ?? []).map((row: any) => ({
    ...row,
    profiles: Array.isArray(row.profiles) ? row.profiles[0] : row.profiles,
  })) as TeamMitglied[]
}

async function teamFreischalten() {
  freischaltFehler.value = ''
  freischaltNachricht.value = ''
  const { error: err } = await supabase.rpc('freischalten_teammitglied', {
    p_lager_id: lagerId,
    p_email: freischaltEmail.value.trim(),
    p_rolle: 'leiter',
  })
  if (err) { freischaltFehler.value = err.message; return }
  freischaltNachricht.value = `${freischaltEmail.value} hat jetzt Zugriff auf dieses Lager.`
  freischaltEmail.value = ''
  await ladeTeam()
}

async function teamEntfernen(teamId: string) {
  await supabase.from('lager_leiter').delete().eq('id', teamId)
  await ladeTeam()
}

// --- Reminders ---
const reminders = ref<Reminder[]>([])
const reminderForm = ref({ titel: '', nachricht: '', faellig_am: '' })
const reminderFehler = ref('')
const reminderSenden = ref(false)

async function ladeReminders() {
  const { data } = await supabase
    .from('reminders')
    .select('id, titel, nachricht, faellig_am, status, gesendet_am, ziel_rolle, ziel_aemtli_id')
    .eq('lager_id', lagerId)
    .order('faellig_am')
  reminders.value = data ?? []
}

async function reminderErstellen() {
  reminderFehler.value = ''
  const { error: err } = await supabase.from('reminders').insert({
    lager_id: lagerId,
    titel: reminderForm.value.titel,
    nachricht: reminderForm.value.nachricht || null,
    faellig_am: reminderForm.value.faellig_am,
  })
  if (err) { reminderFehler.value = err.message; return }
  reminderForm.value = { titel: '', nachricht: '', faellig_am: '' }
  await ladeReminders()
}

async function reminderJetztSenden(reminderId?: string) {
  reminderSenden.value = true
  const { data, error: err } = await supabase.functions.invoke('send-reminder', {
    body: reminderId ? { reminder_id: reminderId } : {},
  })
  reminderSenden.value = false
  if (err) { reminderFehler.value = err.message; return }
  if (data?.ergebnis?.some((r: { status: string }) => r.status === 'fehlgeschlagen')) {
    reminderFehler.value = 'Mindestens ein Reminder konnte nicht gesendet werden.'
  }
  await ladeReminders()
}

// --- Einstellungen / ICS ---
const statusSpeichern = ref(false)

async function statusAendern(neuerStatus: string) {
  statusSpeichern.value = true
  await supabase.from('lager').update({ status: neuerStatus }).eq('id', lagerId)
  if (lager.value) lager.value.status = neuerStatus
  statusSpeichern.value = false
}

async function lagerSpeichernFn() {
  if (!lager.value) return
  lagerSpeichern.value = true
  const { error: err } = await supabase.from('lager').update({
    name: lagerForm.value.name,
    ort: lagerForm.value.ort || null,
    start_datum: lagerForm.value.start_datum || null,
    end_datum: lagerForm.value.end_datum || null,
    jahr: lagerForm.value.jahr,
  }).eq('id', lagerId)
  lagerSpeichern.value = false
  if (!err && lager.value) {
    Object.assign(lager.value, lagerForm.value)
  }
}

function zuBlockSpringen(blockId: string) {
  const block = bloecke.value.find((b) => b.id === blockId)
  if (block?.tag) {
    ausgewaehlterTag.value = block.tag
    offenerBlock.value = blockId
  }
  activeTab.value = 'programm'
}

async function pruefeKueche() {
  if (!session.value) return
  const { data: kue } = await supabase.rpc('is_kueche', { p_lager_id: lagerId })
  istKueche.value = !!kue
}

async function ladeMeineAemtli() {
  if (!session.value) return
  const email = session.value.user.email ?? ''

  const { data: meineLeiter } = await supabase
    .from('anmeldungen_leiter')
    .select('id')
    .eq('lager_id', lagerId)
    .eq('status', 'bestaetigt')
    .ilike('email', email)

  const leiterIds = meineLeiter?.map((l) => l.id) ?? []
  const set = new Map<string, Aemtli>()

  if (leiterIds.length) {
    const { data: lr } = await supabase
      .from('leiter_rollen')
      .select('aemtli:aemtli_id ( id, name )')
      .in('anmeldung_leiter_id', leiterIds)
    for (const row of lr ?? []) {
      const a = row.aemtli as unknown as Aemtli
      if (a?.id) set.set(a.id, a)
    }
  }

  meineAemtli.value = [...set.values()].sort((a, b) => a.name.localeCompare(b.name))
}

function aemtliKomponente(name: string) {
  const slug = aemtliSlug(name)
  if (slug === 'kueche') return 'kueche'
  if (slug === 'finanzen') return 'finanzen'
  return 'generic'
}

function zuHoeckImProgramm() {
  const morgen = new Date()
  morgen.setDate(morgen.getDate() + 1)
  const tag = morgen.toISOString().slice(0, 10)
  if (tage.value.includes(tag)) ausgewaehlterTag.value = tag
  else if (tage.value.length) ausgewaehlterTag.value = tage.value[0]
  activeTab.value = 'programm'
}

function tabWechseln(tab: Tab) {
  activeTab.value = tab
}

function leiterFuerMatching() {
  return leiterListe.value.map((l) => ({ id: l.id, vorname: l.vorname, nachname: l.nachname }))
}

function formatZuordnung(z: NamensZuordnung): string {
  if (z.leiter_id) {
    const n = leiterName(leiterFuerMatching(), z.leiter_id)
    if (n) return n
  }
  if (z.aemtli_id) {
    const n = aemtliName(aemtliListe.value, z.aemtli_id)
    if (n) return `Ämtli: ${n}`
  }
  return `${z.name} (unzugeordnet)`
}

function formatMaterialWer(m: MaterialItem): string {
  if (m.wer_leiter_id) {
    const n = leiterName(leiterFuerMatching(), m.wer_leiter_id)
    if (n) return n
  }
  if (m.wer_aemtli_id) {
    const n = aemtliName(aemtliListe.value, m.wer_aemtli_id)
    if (n) return `Ämtli: ${n}`
  }
  return m.wer ?? '–'
}

function formatAbschnittVerantwortlich(a: Programmabschnitt): string {
  if (a.verantwortlich_leiter_id) {
    const n = leiterName(leiterFuerMatching(), a.verantwortlich_leiter_id)
    if (n) return n
  }
  if (a.verantwortlich_aemtli_id) {
    const n = aemtliName(aemtliListe.value, a.verantwortlich_aemtli_id)
    if (n) return `Ämtli: ${n}`
  }
  return a.verantwortlich ?? '–'
}

async function programmZuordnungenAktualisieren(silent = false) {
  zuordnungLade.value = true
  if (!silent) zuordnungNachricht.value = ''
  await synchronisiereProgrammZuordnungen(lagerId)
  const { data: bloeckeData } = await supabase.from('programmbloecke').select(
    'id, code, nummer, titel, tag, start_zeit, end_zeit, ort, verantwortlich, geschichte, sicherheitsueberlegungen, programmabschnitt, material, notizen, verantwortlich_zuordnungen',
  ).eq('lager_id', lagerId)
  bloecke.value = (bloeckeData ?? []).map((b) => ({
    ...b,
    verantwortlich_zuordnungen: b.verantwortlich_zuordnungen ?? [],
  }))
  zuordnungLade.value = false
  if (!silent) zuordnungNachricht.value = 'Programm-Verantwortliche abgeglichen.'
}

function icsExport(modus: 'ganzes' | 'eigen') {
  if (!lager.value) return
  let zeitraum: { von: string; bis: string } | undefined
  if (modus === 'eigen' && lager.value.start_datum && lager.value.end_datum) {
    zeitraum = { von: lager.value.start_datum, bis: lager.value.end_datum }
  }
  const ics = generateIcs(lager.value.name, bloecke.value, zeitraum)
  const suffix = modus === 'ganzes' ? 'komplett' : 'lagerzeit'
  downloadIcs(`${lager.value.name}-${suffix}.ics`, ics)
}

const willkommenLink = computed(() => `${window.location.origin}/lager/${lagerId}/willkommen`)

onMounted(async () => {
  loading.value = true

  const [{ data: lagerData, error: lagerError }, { data: bloeckeData, error: bloeckeError }] = await Promise.all([
    supabase.from('lager').select('id, name, jahr, ort, start_datum, end_datum, status, ort_lat, ort_lng, created_by').eq('id', lagerId).single(),
    supabase.from('programmbloecke').select(
      'id, code, nummer, titel, tag, start_zeit, end_zeit, ort, verantwortlich, geschichte, sicherheitsueberlegungen, programmabschnitt, material, notizen, verantwortlich_zuordnungen',
    ).eq('lager_id', lagerId),
  ])

  if (lagerError || bloeckeError) {
    error.value = lagerError?.message ?? bloeckeError?.message ?? 'Lager konnte nicht geladen werden.'
    loading.value = false
    return
  }

  lager.value = lagerData
  lagerForm.value = {
    name: lagerData.name,
    ort: lagerData.ort ?? '',
    start_datum: lagerData.start_datum ?? '',
    end_datum: lagerData.end_datum ?? '',
    jahr: lagerData.jahr,
  }
  bloecke.value = (bloeckeData ?? []).map((b) => ({
    ...b,
    verantwortlich_zuordnungen: b.verantwortlich_zuordnungen ?? [],
  }))
  ausgewaehlterTag.value = tage.value[0] ?? null

  if (lager.value.ort_lat && lager.value.ort_lng && lager.value.start_datum && lager.value.end_datum) {
    try {
      wetter.value = await ladeWetter(lager.value.ort_lat, lager.value.ort_lng, lager.value.start_datum, lager.value.end_datum)
    } catch { /* optional */ }
  }

  if (session.value) {
    const { data: p } = await supabase.from('profiles').select('vorname, nachname').eq('id', session.value.user.id).single()
    profil.value = p
    await pruefeKueche()
    await ladeMeineAemtli()
  }

  await Promise.all([ladeTeilnehmer(), ladeAemtli(), ladeGruppen(), ladeTeam(), ladeReminders()])
  await ladeLeiter()
  await ladeLeiterRollen()
  await programmZuordnungenAktualisieren(true)
  loading.value = false
})

watch(activeTab, async (tab) => {
  if (tab === 'leiter') {
    await ladeLeiter()
    await ladeLeiterRollen()
  }
})
</script>

<template>
  <main>
    <p><router-link to="/lager">← Zurück zur Übersicht</router-link></p>

    <p v-if="loading">Lade...</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <template v-else-if="lager">
      <header class="lager-header">
        <div>
          <h1 class="lager-titel">{{ lager.name }}</h1>
          <p class="lager-meta">{{ lager.jahr }} · {{ lager.status.replace('_', ' ') }}</p>
        </div>
      </header>

      <LagerNav
        :active-tab="activeTab"
        :meine-aemtli="meineAemtli"
        :is-leitung="isLeitung"
        :hat-kueche-tab="hatKuecheTab"
        :leiter-anfragen="leiterAnfragen.length"
        :tn-count="tnListe.length"
        :leiter-count="leiterBestaetigt.length"
        @navigate="tabWechseln($event as Tab)"
      />

      <section v-if="activeTab === 'dashboard'">
        <LagerDashboard
          :lager="lager"
          :bloecke="bloecke"
          :user-name="userName"
          :ist-anwesend="istAnwesend"
          :bearbeiten="true"
          :hat-kueche-tab="hatKuecheTab"
          :is-leitung="isLeitung"
          :leiter-anfragen="leiterAnfragen.length"
          @tab="tabWechseln($event as Tab)"
          @hoeck="zuHoeckImProgramm"
          @block="zuBlockSpringen"
        />
        <LagerMap
          v-if="lager.ort_lat && lager.ort_lng"
          :lat="lager.ort_lat"
          :lng="lager.ort_lng"
          :ort="lager.ort"
        />
      </section>

      <!-- Programm (nur Leiterteam) -->
      <section v-if="activeTab === 'programm'">
        <div v-if="wetter.length" class="wetter-banner">
          <span v-for="w in wetter.slice(0, 5)" :key="w.datum" class="wetter-tag">
            {{ formatTag(w.datum) }}: {{ w.beschreibung }} {{ w.tempMin }}–{{ w.tempMax }}°
          </span>
        </div>

        <div v-if="bloecke.length" class="programm-toolbar">
          <button class="secondary klein" :disabled="zuordnungLade" @click="programmZuordnungenAktualisieren()">
            {{ zuordnungLade ? 'Gleiche ab...' : 'Namen mit Leitern/Ämtli abgleichen' }}
          </button>
          <span v-if="zuordnungNachricht" class="hint">{{ zuordnungNachricht }}</span>
        </div>

        <p v-if="!bloecke.length" class="hint">Noch keine Programmblöcke. Import über eCamp-PDF möglich.</p>

        <nav v-else class="tage">
          <button v-for="tag in tage" :key="tag" :class="{ aktiv: tag === ausgewaehlterTag }" @click="ausgewaehlterTag = tag; offenerBlock = null">
            {{ formatTag(tag) }}
          </button>
        </nav>

        <ProgrammHoeck
          v-if="ausgewaehlterTag && session"
          :lager-id="lagerId"
          :tag="ausgewaehlterTag"
          :bloecke="bloecke"
          :user-id="session.user.id"
          :user-name="userName"
        />

        <div v-if="blocksFuerTag.length" class="timetable">
          <template v-for="b in blocksFuerTag" :key="b.id">
            <div class="block-zeile" :id="'block-' + b.id" @click="toggleBlock(b.id)">
              <span class="zeit">{{ formatZeit(b.start_zeit) }}–{{ formatZeit(b.end_zeit) }}</span>
              <span class="code" :class="'code-' + b.code">{{ b.code }}</span>
              <span class="titel">{{ b.nummer ? b.nummer + ' ' : '' }}{{ b.titel }}</span>
              <span class="verantwortlich">{{ b.verantwortlich }}</span>
            </div>
            <div v-if="offenerBlock === b.id" class="block-detail">
              <p v-if="b.ort"><strong>Ort:</strong> {{ b.ort }}</p>
              <p v-if="b.verantwortlich || b.verantwortlich_zuordnungen?.length">
                <strong>Verantwortlich:</strong>
                <span v-if="b.verantwortlich_zuordnungen?.length">
                  <span
                    v-for="(z, zi) in b.verantwortlich_zuordnungen"
                    :key="zi"
                    class="zuordnung-pill"
                    :class="{ unzugeordnet: !z.leiter_id && !z.aemtli_id }"
                  >{{ formatZuordnung(z) }}</span>
                </span>
                <span v-else>{{ b.verantwortlich }}</span>
              </p>
              <p v-if="b.geschichte"><strong>Geschichte:</strong> {{ b.geschichte }}</p>
              <p v-if="b.sicherheitsueberlegungen"><strong>Sicherheitsüberlegungen:</strong> {{ b.sicherheitsueberlegungen }}</p>
              <div v-if="b.programmabschnitt?.length">
                <strong>Programmabschnitt</strong>
                <table class="abschnitt-tabelle">
                  <tbody>
                    <tr v-for="(a, i) in b.programmabschnitt" :key="i">
                      <td class="abschnitt-zeit">{{ a.zeit ?? '–' }}</td>
                      <td>{{ a.programm }}</td>
                      <td class="abschnitt-verantwortlich">{{ formatAbschnittVerantwortlich(a) }}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div v-if="b.material?.length">
                <strong>Material</strong>
                <ul class="material-liste">
                  <li v-for="(m, i) in b.material" :key="i">
                    {{ m.name }}
                    <span class="material-wer" :class="{ unzugeordnet: m.wer && !m.wer_leiter_id && !m.wer_aemtli_id }">
                      – {{ formatMaterialWer(m) }}
                    </span>
                  </li>
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
          Anmeldung: <router-link :to="`/lager/${lagerId}/anmelden-tn`">/anmelden-tn</router-link> ·
          Infoseite TN: <router-link :to="`/lager/${lagerId}/willkommen`">/willkommen</router-link>
        </p>
        <table v-if="tnListe.length" class="liste">
          <thead><tr><th>Name</th><th>Alter</th><th>Gruppe</th><th>Rolle</th><th>Status</th></tr></thead>
          <tbody>
            <tr v-for="tn in tnListe" :key="tn.id">
              <td>{{ tn.vorname }} {{ tn.nachname }}</td>
              <td>{{ berechneAlter(tn.geburtsdatum) ?? '–' }}</td>
              <td><span v-if="gruppeTagTn[tn.id]" class="gruppen-tag">{{ gruppeTagTn[tn.id] }}</span><span v-else>–</span></td>
              <td>
                <select :value="tn.rolle" @change="tnRolleAendern(tn, ($event.target as HTMLSelectElement).value as 'TN' | 'HL')">
                  <option value="TN">TN</option><option value="HL">HL</option>
                </select>
              </td>
              <td>{{ tn.status }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else class="hint">Noch keine Teilnehmer.</p>
        <h3>Manuell erfassen</h3>
        <form @submit.prevent="tnHinzufuegen" class="inline-form">
          <input v-model="tnForm.vorname" placeholder="Vorname" required />
          <input v-model="tnForm.nachname" placeholder="Nachname" required />
          <input v-model="tnForm.geburtsdatum" type="date" required />
          <select v-model="tnForm.geschlecht"><option value="">Geschlecht</option><option value="m">m</option><option value="w">w</option><option value="d">d</option></select>
          <input v-model="tnForm.notfallkontakt" placeholder="Notfallkontakt" required />
          <input v-model="tnForm.eltern_email" type="email" placeholder="E-Mail Eltern" required />
          <button type="submit" :disabled="tnSpeichern">{{ tnSpeichern ? 'Speichere...' : 'Hinzufügen' }}</button>
        </form>
        <p v-if="tnFehler" class="error">{{ tnFehler }}</p>
      </section>

      <!-- Leiter -->
      <section v-if="activeTab === 'leiter'">
        <p class="hint">
          Leiterbewerbung:
          <router-link :to="`/lager/${lagerId}/anmelden-leiter`">/anmelden-leiter</router-link>
        </p>
        <p v-if="isLeitung" class="hint geschuetzt-hinweis">
          Nur die Lagerleitung kann die Ämtli <strong>Küche</strong> und <strong>Finanzen</strong> zuweisen.
        </p>

        <div v-if="leiterAnfragen.length && isLeitung" class="anfragen-box">
          <h3>Offene Anfragen ({{ leiterAnfragen.length }})</h3>
          <div v-for="a in leiterAnfragen" :key="a.id" class="anfrage-karte">
            <strong>{{ a.vorname }} {{ a.nachname }}</strong>
            <span class="hint">{{ a.email }} · {{ a.anwesend_von ?? '?' }} – {{ a.anwesend_bis ?? '?' }}</span>
            <div class="inline-form">
              <button @click="leiterAnfrageBearbeiten(a.id, 'genehmigen')">Freischalten</button>
              <button class="secondary" @click="leiterAnfrageBearbeiten(a.id, 'ablehnen')">Ablehnen</button>
            </div>
          </div>
        </div>

        <table v-if="leiterBestaetigt.length" class="liste">
          <thead><tr><th>Name</th><th>Alter</th><th>Gruppe</th><th>Anwesend</th><th>Ämtli</th></tr></thead>
          <tbody>
            <tr v-for="l in leiterBestaetigt" :key="l.id">
              <td>{{ l.vorname }} {{ l.nachname }}</td>
              <td>{{ berechneAlter(l.geburtsdatum) ?? '–' }}</td>
              <td><span v-if="gruppeTagLeiter[l.id]" class="gruppen-tag">{{ gruppeTagLeiter[l.id] }}</span><span v-else>–</span></td>
              <td>{{ l.anwesend_von ?? '–' }} – {{ l.anwesend_bis ?? '–' }}</td>
              <td class="aemtli-zelle">
                <div class="rollen-zeile">
                  <span v-for="r in leiterRollenMap[l.id] ?? []" :key="r.zuweisungId" class="rollen-pill">
                    {{ r.name }}
                    <button
                      v-if="isLeitung"
                      type="button"
                      class="rollen-entfernen"
                      title="Rolle entfernen"
                      @click="rolleEntfernen(r.zuweisungId)"
                    >×</button>
                  </span>
                  <span v-if="!(leiterRollenMap[l.id] ?? []).length" class="hint rollen-leer">–</span>
                </div>
                <div v-if="isLeitung" class="rollen-zuweisen">
                  <select
                    v-if="zuweisbareAemtli(l.id).length"
                    @change="rolleZuweisen(l.id, ($event.target as HTMLSelectElement).value); ($event.target as HTMLSelectElement).value = ''"
                  >
                    <option value="">+ Ämtli</option>
                    <option v-for="a in zuweisbareAemtli(l.id)" :key="a.id" :value="a.id">{{ a.name }}</option>
                  </select>
                  <input
                    v-model="neueRolleName[l.id]"
                    placeholder="neues Ämtli..."
                    class="neue-rolle-input"
                    @keyup.enter="neueRolleErstellen(l.id)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-else class="hint">Noch keine Leiter.</p>
        <h3>Manuell erfassen</h3>
        <form @submit.prevent="leiterHinzufuegen" class="inline-form">
          <input v-model="leiterForm.vorname" placeholder="Vorname" required />
          <input v-model="leiterForm.nachname" placeholder="Nachname" required />
          <input v-model="leiterForm.geburtsdatum" type="date" />
          <select v-model="leiterForm.geschlecht"><option value="">Geschlecht</option><option value="m">m</option><option value="w">w</option><option value="d">d</option></select>
          <input v-model="leiterForm.email" type="email" placeholder="E-Mail" required />
          <input v-model="leiterForm.anwesend_von" type="date" />
          <input v-model="leiterForm.anwesend_bis" type="date" />
          <button type="submit" :disabled="leiterSpeichern">{{ leiterSpeichern ? 'Speichere...' : 'Hinzufügen' }}</button>
        </form>
        <p v-if="leiterFehler" class="error">{{ leiterFehler }}</p>
      </section>

      <!-- Gruppen -->
      <section v-if="activeTab === 'gruppen'">
        <p class="hint">Jede Person kann höchstens in <strong>einer</strong> Gruppe sein. Beim Zuweisen zu einer neuen Gruppe wird die alte automatisch ersetzt.</p>

        <h3>Automatisch verteilen</h3>
        <div class="inline-form">
          <label>Anzahl Gruppen <input v-model.number="anzahlGruppenInput" type="number" min="1" max="20" /></label>
          <button @click="gruppenAutomatischBilden" :disabled="gruppenErstellen">{{ gruppenErstellen ? 'Verteile...' : 'Automatisch bilden' }}</button>
        </div>

        <h3>Manuell erstellen</h3>
        <div class="inline-form">
          <input v-model="neueGruppeName" placeholder="Gruppenname (optional)" />
          <button class="secondary" @click="gruppeManuellErstellen">Gruppe erstellen</button>
        </div>
        <p v-if="gruppenFehler" class="error">{{ gruppenFehler }}</p>

        <div v-if="gruppenListe.length" class="gruppen-grid">
          <div v-for="g in gruppenListe" :key="g.id" class="gruppe-karte">
            <input
              v-model="gruppenNamen[g.id]"
              class="gruppe-name-input"
              title="Gruppenname bearbeiten"
              @blur="gruppeUmbenennen(g.id)"
              @keyup.enter="($event.target as HTMLInputElement).blur()"
            />
            <ul>
              <li v-for="m in g.mitglieder" :key="m.id">
                {{ m.name }} <span class="hint">({{ m.typ === 'leiter' ? 'Leiter' : 'TN' }})</span>
                <button class="secondary klein" @click="mitgliedEntfernen(m.id)">×</button>
              </li>
            </ul>
            <div class="inline-form">
              <select @change="mitgliedZuGruppeHinzufuegen(g.id, 'tn', ($event.target as HTMLSelectElement).value); ($event.target as HTMLSelectElement).value = ''">
                <option value="">+ TN hinzufügen</option>
                <option
                  v-for="tn in tnListe.filter((t) => !tnInGruppe(t.id, g.id))"
                  :key="tn.id"
                  :value="tn.id"
                >
                  {{ tn.vorname }} {{ tn.nachname }}{{ tnGruppenLabel(tn.id, g.id) }}
                </option>
              </select>
              <select @change="mitgliedZuGruppeHinzufuegen(g.id, 'leiter', ($event.target as HTMLSelectElement).value); ($event.target as HTMLSelectElement).value = ''">
                <option value="">+ Leiter hinzufügen</option>
                <option
                  v-for="l in leiterListe.filter((x) => !leiterInGruppe(x.id, g.id))"
                  :key="l.id"
                  :value="l.id"
                >
                  {{ l.vorname }} {{ l.nachname }}{{ leiterGruppenLabel(l.id, g.id) }}
                </option>
              </select>
              <button class="secondary klein" @click="gruppeLoeschen(g.id)">Gruppe löschen</button>
            </div>
          </div>
        </div>
        <p v-else class="hint">Noch keine Gruppen.</p>
      </section>

      <!-- Einkauf -->
      <section v-if="activeTab === 'einkauf' && session">
        <LagerEinkauf
          :lager-id="lagerId"
          :lager-name="lager.name"
          :user-id="session.user.id"
          :ist-kueche="istKueche"
          :bloecke="bloecke.map((b) => ({ id: b.id, titel: b.titel, code: b.code }))"
        />
      </section>

      <!-- Dynamische Ämtli-Tabs -->
      <section v-for="a in meineAemtli" :key="a.id" v-show="activeTab === tabIdForAemtli(a.name)">
        <AemtliKueche
          v-if="aemtliKomponente(a.name) === 'kueche' && session"
          :lager-id="lagerId"
          :aemtli-id="a.id"
          :lager-name="lager.name"
          :user-id="session.user.id"
          :start-datum="lager.start_datum"
          :end-datum="lager.end_datum"
          :bloecke="bloecke.map((b) => ({ id: b.id, titel: b.titel, code: b.code }))"
        />
        <AemtliFinanzen
          v-else-if="aemtliKomponente(a.name) === 'finanzen'"
          :lager-id="lagerId"
          :aemtli-id="a.id"
          :ist-kassier="hatFinanzenAemtli"
        />
        <AemtliGeneric v-else :lager-id="lagerId" :aemtli-id="a.id" :aemtli-name="a.name" />
      </section>

      <!-- Quittungen (alle Leiter) -->
      <section v-if="activeTab === 'quittungen' && session">
        <QuittungenPanel
          :key="`quittungen-${hatFinanzenAemtli}`"
          :lager-id="lagerId"
          :user-id="session.user.id"
          :ist-kassier="hatFinanzenAemtli"
        />
      </section>

      <!-- Team / Berechtigungen -->
      <section v-if="activeTab === 'team'">
        <p class="hint">Nur freigeschaltete Teammitglieder und die Ersteller/in sehen dieses Lager.</p>
        <table v-if="teamListe.length" class="liste">
          <thead><tr><th>Name</th><th>E-Mail</th><th>Rolle</th><th>Status</th><th></th></tr></thead>
          <tbody>
            <tr v-for="t in teamListe" :key="t.id">
              <td>{{ t.profiles.vorname ?? '' }} {{ t.profiles.nachname ?? '' }}</td>
              <td>{{ t.profiles.email }}</td>
              <td>{{ t.rolle }}</td>
              <td>{{ t.status }}</td>
              <td>
                <button v-if="isLeitung && t.profile_id !== session?.user.id" class="secondary klein" @click="teamEntfernen(t.id)">Entfernen</button>
              </td>
            </tr>
          </tbody>
        </table>

        <div v-if="isLeitung" class="freischalten-box">
          <h3>Teammitglied freischalten</h3>
          <p class="hint">Die Person muss sich zuerst einmal eingeloggt haben (Google oder Passwort).</p>
          <div class="inline-form">
            <input v-model="freischaltEmail" type="email" placeholder="E-Mail-Adresse" />
            <button @click="teamFreischalten">Freischalten</button>
          </div>
          <p v-if="freischaltNachricht">{{ freischaltNachricht }}</p>
          <p v-if="freischaltFehler" class="error">{{ freischaltFehler }}</p>
        </div>
      </section>

      <!-- Reminders -->
      <section v-if="activeTab === 'reminders'">
        <p class="hint">
          Erinnerungen werden per E-Mail über Resend versendet.
          Ohne eigene Domain (onboarding@resend.dev) gehen Test-Mails nur an die E-Mail deines Resend-Accounts.
        </p>
        <button @click="reminderJetztSenden()" :disabled="reminderSenden">Fällige Reminder jetzt senden</button>

        <table v-if="reminders.length" class="liste">
          <thead><tr><th>Titel</th><th>Fällig</th><th>Status</th><th></th></tr></thead>
          <tbody>
            <tr v-for="r in reminders" :key="r.id">
              <td>{{ r.titel }}</td>
              <td>{{ new Date(r.faellig_am).toLocaleString('de-CH') }}</td>
              <td>{{ r.status }}</td>
              <td>
                <button v-if="r.status === 'geplant'" class="secondary klein" @click="reminderJetztSenden(r.id)" :disabled="reminderSenden">Senden</button>
              </td>
            </tr>
          </tbody>
        </table>

        <h3>Neuer Reminder</h3>
        <form @submit.prevent="reminderErstellen" class="reminder-form">
          <input v-model="reminderForm.titel" placeholder="Titel" required />
          <textarea v-model="reminderForm.nachricht" placeholder="Nachricht" rows="3"></textarea>
          <input v-model="reminderForm.faellig_am" type="datetime-local" required />
          <button type="submit">Reminder erstellen</button>
        </form>
        <p v-if="reminderFehler" class="error">{{ reminderFehler }}</p>
      </section>

      <!-- Einstellungen -->
      <section v-if="activeTab === 'einstellungen'">
        <h3>Lager bearbeiten</h3>
        <form @submit.prevent="lagerSpeichernFn" class="lager-form">
          <label>Name <input v-model="lagerForm.name" required /></label>
          <label>Ort <input v-model="lagerForm.ort" /></label>
          <label>Jahr <input v-model.number="lagerForm.jahr" type="number" required /></label>
          <label>Start <input v-model="lagerForm.start_datum" type="date" /></label>
          <label>Ende <input v-model="lagerForm.end_datum" type="date" /></label>
          <button type="submit" :disabled="lagerSpeichern">{{ lagerSpeichern ? 'Speichere...' : 'Speichern' }}</button>
        </form>

        <h3>Lager-Status</h3>
        <select :value="lager.status" @change="statusAendern(($event.target as HTMLSelectElement).value)" :disabled="statusSpeichern">
          <option value="planung">Planung</option>
          <option value="anmeldung_offen">Anmeldung offen</option>
          <option value="laufend">Laufend</option>
          <option value="abgeschlossen">Abgeschlossen</option>
          <option value="archiviert">Archiviert</option>
        </select>

        <h3>Willkommens-Link für TN</h3>
        <p class="hint">Teilnehmer/innen sehen nur diese Seite – kein Programm:</p>
        <code class="link-box">{{ willkommenLink }}</code>

        <h3>Kalender-Export (ICS)</h3>
        <div class="inline-form">
          <button class="secondary" @click="icsExport('ganzes')">Ganzes Programm (.ics)</button>
          <button class="secondary" @click="icsExport('eigen')">Nur Lagerzeitraum (.ics)</button>
        </div>
      </section>
    </template>
  </main>
</template>

<style scoped>
main { max-width: 900px; margin: 2rem auto; padding: 0 1rem; }
.hint { color: var(--color-text-muted); font-size: 0.9rem; }
.geschuetzt-hinweis { padding: 0.6rem 0.85rem; background: var(--color-surface-muted); border-radius: var(--radius-md); margin-bottom: 1rem; }
.lager-header { margin-bottom: 0.5rem; }
.lager-titel { margin: 0; font-size: 1.5rem; }
.lager-meta { margin: 0.25rem 0 0; font-size: 0.88rem; color: var(--color-text-muted); text-transform: capitalize; }
.tage { display: flex; flex-wrap: wrap; gap: 0.4rem; margin: 1rem 0; }
.tage button { background: var(--color-surface); color: var(--color-text); border: 1px solid var(--color-border); }
.tage button.aktiv { background: var(--color-accent); color: #fdfbf3; border-color: var(--color-accent); }
.wetter-banner { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 1rem; font-size: 0.8rem; color: var(--color-text-muted); }
.wetter-tag { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-pill); padding: 0.2rem 0.6rem; }
.timetable { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); overflow: hidden; }
.block-zeile { display: grid; grid-template-columns: 100px 40px 1fr 160px; gap: 0.75rem; align-items: center; padding: 0.6rem 0.9rem; border-bottom: 1px solid var(--color-border); cursor: pointer; }
.block-zeile:hover { background: var(--color-surface-muted); }
.zeit { font-size: 0.85rem; color: var(--color-text-muted); font-variant-numeric: tabular-nums; }
.code { font-size: 0.7rem; font-weight: 700; text-align: center; padding: 0.2rem 0; border-radius: var(--radius-pill); color: #fdfbf3; }
.code-LP { background: #6b7fa8; } .code-LS { background: var(--color-accent); } .code-LA { background: #c98a3f; } .code-ES { background: #8a7f68; }
.titel { font-size: 0.95rem; }
.verantwortlich { font-size: 0.8rem; color: var(--color-text-muted); text-align: right; }
.block-detail { padding: 0.85rem 1.25rem 1.1rem; background: var(--color-surface-muted); border-bottom: 1px solid var(--color-border); font-size: 0.9rem; }
.block-detail p { margin: 0.4rem 0; }
.abschnitt-tabelle { width: 100%; border-collapse: collapse; margin: 0.4rem 0 0.8rem; font-size: 0.85rem; }
.abschnitt-tabelle td { padding: 0.3rem 0.5rem 0.3rem 0; border-bottom: 1px solid var(--color-border); vertical-align: top; }
.abschnitt-zeit { white-space: nowrap; color: var(--color-text-muted); }
.abschnitt-verantwortlich { color: var(--color-text-muted); white-space: nowrap; }
.material-liste { margin: 0.4rem 0 0.8rem; padding-left: 1.2rem; }
.material-wer.unzugeordnet { color: var(--color-text-muted); font-style: italic; }
.zuordnung-pill { display: inline-block; background: var(--color-pill-bg); border-radius: var(--radius-pill); padding: 0.1rem 0.5rem; font-size: 0.78rem; margin: 0.15rem 0.3rem 0.15rem 0; }
.zuordnung-pill.unzugeordnet { background: var(--color-surface-muted); color: var(--color-text-muted); font-style: italic; }
.programm-toolbar { display: flex; flex-wrap: wrap; align-items: center; gap: 0.6rem; margin-bottom: 0.75rem; }
.liste { width: 100%; border-collapse: collapse; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); margin: 1rem 0; font-size: 0.9rem; }
.liste th, .liste td { text-align: left; padding: 0.5rem 0.7rem; border-bottom: 1px solid var(--color-border); vertical-align: middle; }
.liste th { color: var(--color-text-muted); font-weight: 700; font-size: 0.8rem; }
.gruppen-tag { display: inline-block; background: var(--color-accent); color: #fdfbf3; border-radius: var(--radius-pill); padding: 0.1rem 0.55rem; font-size: 0.78rem; }
.rollen-pill { display: inline-flex; align-items: center; gap: 0.15rem; background: var(--color-pill-bg); border-radius: var(--radius-pill); padding: 0.15rem 0.45rem 0.15rem 0.6rem; font-size: 0.78rem; margin: 0.1rem 0.3rem 0.1rem 0; }
.rollen-entfernen { background: none; border: none; color: var(--color-text-muted); padding: 0 0.2rem; font-size: 0.85rem; line-height: 1; cursor: pointer; }
.rollen-entfernen:hover { color: var(--color-danger); }
.neue-rolle-input { width: 110px; margin-left: 0.4rem; }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.6rem; align-items: center; margin: 0.75rem 0 1rem; }
.inline-form label { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.8rem; color: var(--color-text-muted); }
.gruppen-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 0.75rem; margin-top: 1rem; }
.gruppe-karte { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.85rem 1rem; }
.gruppe-name-input {
  font-weight: 700; font-size: 1rem; width: 100%; margin-bottom: 0.5rem;
  border: 1px solid transparent; background: transparent; border-radius: var(--radius-sm);
  padding: 0.25rem 0.4rem; transition: border-color 0.15s, background 0.15s;
}
.gruppe-name-input:hover,
.gruppe-name-input:focus {
  border-color: var(--color-border); background: var(--color-surface-muted); outline: none;
}
.aemtli-zelle { min-width: 180px; }
.rollen-zeile { display: flex; flex-wrap: wrap; align-items: center; gap: 0.15rem; min-height: 1.5rem; margin-bottom: 0.25rem; }
.rollen-leer { font-size: 0.85rem; }
.rollen-zuweisen { display: flex; flex-wrap: wrap; align-items: center; gap: 0.35rem; }
.gruppe-karte ul { list-style: none; padding: 0; margin: 0 0 0.5rem; font-size: 0.88rem; }
.gruppe-karte li { padding: 0.15rem 0; display: flex; align-items: center; gap: 0.4rem; }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.5rem; }
.freischalten-box { margin-top: 1.5rem; padding: 1rem; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); }
.reminder-form { display: flex; flex-direction: column; gap: 0.6rem; max-width: 400px; margin-top: 1rem; }
.link-box { display: block; background: var(--color-surface-muted); padding: 0.5rem 0.75rem; border-radius: var(--radius-md); font-size: 0.85rem; word-break: break-all; margin: 0.5rem 0 1.5rem; }
.error { color: var(--color-danger); }
.anfragen-box { margin-bottom: 1.25rem; padding: 1rem; background: var(--color-surface-muted); border-radius: var(--radius-md); }
.anfrage-karte { padding: 0.6rem 0; border-bottom: 1px solid var(--color-border); }
.anfrage-karte:last-child { border-bottom: none; }
.lager-form { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 0.75rem; margin-bottom: 1.5rem; }
.lager-form label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.85rem; color: var(--color-text-muted); }
</style>
