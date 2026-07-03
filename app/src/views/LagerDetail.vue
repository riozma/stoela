<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
import { generateIcs, downloadIcs } from '../lib/ics'
import { ladeWetter, type TagesWetter } from '../lib/weather'
import LagerDashboard from '../components/lager/LagerDashboard.vue'
import LagerTimelinePanel from '../components/lager/LagerTimelinePanel.vue'
import LagerEinkauf from '../components/lager/LagerEinkauf.vue'
import LagerMap from '../components/lager/LagerMap.vue'
import ProgrammGesamt from '../components/lager/ProgrammGesamt.vue'
import ProgrammTag from '../components/lager/ProgrammTag.vue'
import ProgrammBlockEdit from '../components/lager/ProgrammBlockEdit.vue'
import { heuteIso, lagerLaeuft, tageZwischen } from '../lib/programmUtils'
import AemtliKueche from '../components/lager/AemtliKueche.vue'
import AemtliFinanzen from '../components/lager/AemtliFinanzen.vue'
import AemtliGeneric from '../components/lager/AemtliGeneric.vue'
import AemtliKiosk from '../components/lager/AemtliKiosk.vue'
import AemtliTelefon from '../components/lager/AemtliTelefon.vue'
import AemtliGuteFee from '../components/lager/AemtliGuteFee.vue'
import AemtliKuchenstand from '../components/lager/AemtliKuchenstand.vue'
import AemtliSponsoring from '../components/lager/AemtliSponsoring.vue'
import AemtliKrankenpflege from '../components/lager/AemtliKrankenpflege.vue'
import AemtliGelaende from '../components/lager/AemtliGelaende.vue'
import AemtliBastel from '../components/lager/AemtliBastel.vue'
import AemtliSkiweekend from '../components/lager/AemtliSkiweekend.vue'
import QuittungenPanel from '../components/lager/QuittungenPanel.vue'
import LagerFahrplan from '../components/lager/LagerFahrplan.vue'
import VorweekendPanel from '../components/lager/VorweekendPanel.vue'
import ElterninfoPanel from '../components/lager/ElterninfoPanel.vue'
import LagerNav from '../components/lager/LagerNav.vue'
import AppHeader from '../components/AppHeader.vue'
import { aemtliSlug, tabIdForAemtli } from '../lib/aemtliSlug'
import { GESCHUETZTE_AEMTLI, istGeschuetztesAemtli } from '../lib/aemtliPermissions'
import { synchronisiereProgrammZuordnungen } from '../lib/programmZuordnung'
import type { MaterialMitZuordnung, NamensZuordnung, ProgrammabschnittMitZuordnung } from '../lib/nameMatching'
import { bestaetigenBis, formatFaelligkeit } from '../lib/workflowUtils'
import { logLagerAktivitaet, ladeLetzteAenderungen, type LagerAenderung } from '../lib/lagerAktivitaet'

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
  organisation_id: string | null
  ort: string | null
  start_datum: string | null
  end_datum: string | null
  status: string
  ort_lat: number | null
  ort_lng: number | null
  created_by: string | null
  vor_lager_id: string | null
  vorweekend_start: string | null
  vorweekend_ende: string | null
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
  anmeldung_art?: string
  bestaetigen_bis?: string | null
  von_vorjahr?: boolean
}
interface Aemtli {
  id: string
  name: string
}
interface OrgPersonPool {
  id: string
  profile_id: string | null
  vorname: string
  nachname: string
  email: string | null
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
const navOffen = ref(false)
const programmStatistik = ref<{ name: string; bloecke_absolut: number; bloecke_total: number; anteil_prozent: number; anwesend_tage: number | null }[]>([])
const moerderliAktiv = ref(false)
const letzteAenderungen = ref<LagerAenderung[]>([])
const tnNavCount = ref(0)
const bloeckeLaden = ref(false)
const bloeckeVollGeladen = ref(false)

const BLOECKE_BASIS_SELECT = 'id, code, nummer, titel, tag, start_zeit, end_zeit, ort, verantwortlich'
const BLOECKE_VOLL_SELECT =
  `${BLOECKE_BASIS_SELECT}, geschichte, sicherheitsueberlegungen, programmabschnitt, material, notizen, verantwortlich_zuordnungen`

const tnCountNav = computed(() => (tnListe.value.length ? tnListe.value.length : tnNavCount.value))

const route = useRoute()
const router = useRouter()
const { session } = useAuth()
const lagerId = computed(() => route.params.id as string)

type Tab = 'dashboard' | 'programm' | 'teilnehmer' | 'leiter' | 'gruppen' | 'einkauf' | 'team' | 'einstellungen' | 'quittungen' | 'fahrplan' | 'vorweekend' | 'elterninfo' | string

const activeTab = computed<Tab>(() => {
  if (route.name === 'lager-aemtli') return `aemtli:${route.params.aemtliSlug as string}`
  if (typeof route.name === 'string' && route.name.startsWith('programm')) return 'programm'
  return (route.params.section as string) || 'dashboard'
})

const programmRoute = computed(() => {
  if (route.name === 'programm-tag') return { view: 'tag' as const, date: route.params.programmTag as string }
  if (route.name === 'programm-block') return { view: 'block' as const, blockId: route.params.blockId as string }
  if (route.name === 'programm-neu') return { view: 'neu' as const }
  return { view: 'gesamt' as const }
})

const alleProgrammTage = computed(() => {
  if (lager.value?.start_datum && lager.value?.end_datum) {
    return tageZwischen(lager.value.start_datum, lager.value.end_datum)
  }
  return tage.value
})

const programmLink = computed(() => {
  const heute = heuteIso()
  if (lager.value && lagerLaeuft(lager.value.start_datum, lager.value.end_datum) && alleProgrammTage.value.includes(heute)) {
    return `/lager/${lagerId.value}/programm/tag/${heute}`
  }
  return `/lager/${lagerId.value}/programm`
})
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
const vorLagerIdForm = ref('')
const andereLager = ref<{ id: string; name: string; jahr: number }[]>([])
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
const leiterProvisorisch = computed(() =>
  leiterListe.value.filter((l) => l.status === 'angemeldet'),
)
const leiterBestaetigt = computed(() => leiterListe.value.filter((l) => l.status === 'bestaetigt'))

// --- Programm ---
const tage = computed(() => {
  const einzigartig = new Set(bloecke.value.map((b) => b.tag).filter((t): t is string => !!t))
  return [...einzigartig].sort()
})

function formatTag(tag: string) {
  const datum = new Date(tag + 'T00:00:00')
  return new Intl.DateTimeFormat('de-CH', { weekday: 'short', day: 'numeric', month: 'numeric' }).format(datum)
}

function programmEinstieg() {
  router.push(programmLink.value)
}

async function programmBlockGespeichert() {
  bloeckeVollGeladen.value = false
  await ladeBloeckeVoll()
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
    .eq('lager_id', lagerId.value)
    .order('nachname')
  tnListe.value = data ?? []
}

async function tnHinzufuegen() {
  tnFehler.value = ''
  tnSpeichern.value = true
  const { error: err } = await supabase.from('anmeldungen_tn').insert({
    lager_id: lagerId.value,
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
const leiterSpeichern = ref(false)
const leiterFehler = ref('')
const verknuepfManuell = ref<Record<string, string>>({})
const aemtliListe = ref<Aemtli[]>([])
const leiterRollenMap = ref<Record<string, LeiterRolleZuweisung[]>>({})
const neueRolleName = ref<Record<string, string>>({})
const orgPersonenPool = ref<OrgPersonPool[]>([])
const orgPersonAuswahl = ref('')

async function ladeLeiter() {
  const { data } = await supabase
    .from('anmeldungen_leiter')
    .select('id, profile_id, vorname, nachname, email, geburtsdatum, geschlecht, ahv_nr, anwesend_von, anwesend_bis, status, anmeldung_art, bestaetigen_bis, von_vorjahr')
    .eq('lager_id', lagerId.value)
    .order('nachname')
  leiterListe.value = data ?? []
}

async function leiterBestaetigen(anmeldungId: string) {
  leiterFehler.value = ''
  const { error: err } = await supabase.rpc('leiter_bestaetigen', { p_anmeldung_id: anmeldungId })
  if (err) { leiterFehler.value = err.message; return }
  await leiterNachAenderung()
}

async function leiterAnfrageBearbeiten(anmeldungId: string, entscheidung: 'genehmigen' | 'ablehnen') {
  const { error: err } = await supabase.rpc('leiter_anfrage_bearbeiten', {
    p_anmeldung_id: anmeldungId,
    p_entscheidung: entscheidung,
    p_verknuepf_mit: entscheidung === 'genehmigen' ? verknuepfManuell.value[anmeldungId] || null : null,
  })
  if (err) { leiterFehler.value = err.message; return }
  delete verknuepfManuell.value[anmeldungId]
  await Promise.all([leiterNachAenderung(), ladeTeam()])
}

function passendeManuelleLeiter(anfrage: LeiterAnmeldung) {
  return leiterListe.value.filter(
    (l) =>
      !l.profile_id
      && (l.status === 'bestaetigt' || l.status === 'angemeldet')
      && l.vorname.toLowerCase() === anfrage.vorname.toLowerCase()
      && l.nachname.toLowerCase() === anfrage.nachname.toLowerCase(),
  )
}

async function ladeAemtli() {
  const { data } = await supabase.from('aemtli').select('id, name').order('name')
  aemtliListe.value = data ?? []
}

async function ladeOrgPersonenPool() {
  const orgId = lager.value?.organisation_id
  if (!orgId) {
    orgPersonenPool.value = []
    return
  }
  const { data } = await supabase
    .from('org_personen')
    .select('id, profile_id, vorname, nachname, email')
    .eq('organisation_id', orgId)
    .eq('aktiv', true)
    .order('nachname')
  orgPersonenPool.value = (data ?? []) as OrgPersonPool[]
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
  if (!orgPersonAuswahl.value) return
  leiterFehler.value = ''
  leiterSpeichern.value = true
  const person = orgPersonenPool.value.find((p) => p.id === orgPersonAuswahl.value)
  if (!person) {
    leiterSpeichern.value = false
    leiterFehler.value = 'Bitte Person aus dem Verein auswählen.'
    return
  }
  if (leiterListe.value.some((l) =>
    (person.profile_id && l.profile_id === person.profile_id)
    || (l.vorname.toLowerCase() === person.vorname.toLowerCase() && l.nachname.toLowerCase() === person.nachname.toLowerCase()),
  )) {
    leiterSpeichern.value = false
    leiterFehler.value = 'Diese Person ist bereits in der Lagerleiter-Liste.'
    return
  }

  const status = person.profile_id ? 'bestaetigt' : 'angemeldet'
  const { data: neu, error: err } = await supabase.from('anmeldungen_leiter').insert({
    lager_id: lagerId.value,
    profile_id: person.profile_id,
    vorname: person.vorname,
    nachname: person.nachname,
    email: person.email,
    status,
    anmeldung_art: person.profile_id ? 'fix' : 'provisorisch',
    bestaetigen_bis: lager.value?.start_datum ? bestaetigenBis(lager.value.start_datum) : null,
  }).select('id').single()
  leiterSpeichern.value = false
  if (err) { leiterFehler.value = err.message; return }
  if (person.profile_id) {
    await supabase.from('lager_leiter').upsert({
      lager_id: lagerId.value,
      profile_id: person.profile_id,
      rolle: 'leiter',
      status: 'bestaetigt',
    }, { onConflict: 'lager_id,profile_id' })
  }
  const name = `${person.vorname} ${person.nachname}`
  orgPersonAuswahl.value = ''
  void logLagerAktivitaet(lagerId.value, `Leiter aus Verein hinzugefügt: ${name}`, 'leiter')
  await leiterNachAenderung()
  await ladeLetzteAenderungenListe()
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
    .eq('lager_id', lagerId.value)
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
      .insert({ lager_id: lagerId.value, name: `Gruppe ${i + 1}` })
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
  const { error: err } = await supabase.from('lagergruppen').insert({ lager_id: lagerId.value, name })
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
  void logLagerAktivitaet(lagerId.value, `Gruppe umbenannt: «${name}»`, 'gruppen')
  void ladeLetzteAenderungenListe()
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

async function ladeTeam() {
  const { data } = await supabase
    .from('lager_leiter')
    .select('id, profile_id, rolle, status, profiles(email, vorname, nachname)')
    .eq('lager_id', lagerId.value)
  teamListe.value = (data ?? []).map((row: any) => ({
    ...row,
    profiles: Array.isArray(row.profiles) ? row.profiles[0] : row.profiles,
  })) as TeamMitglied[]
}

async function teamEntfernen(teamId: string) {
  await supabase.from('lager_leiter').delete().eq('id', teamId)
  await ladeTeam()
}

// --- Einstellungen / ICS ---
const statusSpeichern = ref(false)

async function vorLagerSpeichern() {
  if (!lager.value) return
  await supabase.from('lager').update({ vor_lager_id: vorLagerIdForm.value || null }).eq('id', lagerId.value)
  lager.value.vor_lager_id = vorLagerIdForm.value || null
}

async function statusAendern(neuerStatus: string) {
  statusSpeichern.value = true
  await supabase.from('lager').update({ status: neuerStatus }).eq('id', lagerId.value)
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
  }).eq('id', lagerId.value)
  lagerSpeichern.value = false
  if (!err && lager.value) {
    Object.assign(lager.value, lagerForm.value)
  }
}

function zuBlockSpringen(blockId: string) {
  router.push(`/lager/${lagerId.value}/programm/block/${blockId}`)
}

async function pruefeKueche() {
  if (!session.value) return
  const { data: kue } = await supabase.rpc('is_kueche', { p_lager_id: lagerId.value })
  istKueche.value = !!kue
}

async function ladeMeineAemtli() {
  if (!session.value) return
  const email = session.value.user.email ?? ''

  const { data: meineLeiter } = await supabase
    .from('anmeldungen_leiter')
    .select('id')
    .eq('lager_id', lagerId.value)
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

  // Lagerleitung sieht alle Vereins-Ämtli (Übersicht & Zuweisung)
  if (isLeitung.value) {
    const { data: alle } = await supabase.from('aemtli').select('id, name').order('name')
    for (const a of alle ?? []) set.set(a.id, a)
  }

  meineAemtli.value = [...set.values()].sort((a, b) => a.name.localeCompare(b.name))
}

function aemtliKomponente(name: string) {
  const slug = aemtliSlug(name)
  const map: Record<string, string> = {
    kueche: 'kueche', finanzen: 'finanzen', kiosk: 'kiosk', telefon: 'telefon',
    'gute-fee': 'gute_fee', 'hl-team': 'hl', krankenpflege: 'krankenpflege',
    'foto-diashow': 'foto', 'buro-bastelmat': 'bastel', disco: 'disco',
    skiweekend: 'skiweekend', material: 'material', werbung: 'werbung',
    motto: 'motto', hauswart: 'hauswart', gelaendespielwiese: 'gelaende',
    kuchenstand: 'kuchenstand', sponsoring: 'sponsoring', verkleidung: 'verkleidung',
    'social-media': 'werbung', publicity: 'werbung',
  }
  return map[slug] ?? 'generic'
}

async function ladeProgrammStatistik() {
  if (!isLeitung.value) return
  const { data } = await supabase.rpc('lager_programm_statistik', { p_lager_id: lagerId.value })
  programmStatistik.value = (data as typeof programmStatistik.value) ?? []
}

async function ladeMoerderliStatus() {
  const { data } = await supabase.from('gute_fee_spiel').select('oeffentlich').eq('lager_id', lagerId.value).maybeSingle()
  moerderliAktiv.value = !!data?.oeffentlich
}

function zuHoeckImProgramm() {
  const morgen = new Date()
  morgen.setDate(morgen.getDate() + 1)
  const tag = morgen.toISOString().slice(0, 10)
  if (alleProgrammTage.value.includes(tag)) {
    router.push(`/lager/${lagerId.value}/programm/tag/${tag}`)
    return
  }
  programmEinstieg()
}

function tabWechseln(tab: Tab) {
  if (tab === 'programm') {
    programmEinstieg()
    return
  }
  if (tab.startsWith('aemtli:')) {
    router.push(`/lager/${lagerId.value}/aemtli/${tab.slice(7)}`)
    return
  }
  router.push(`/lager/${lagerId.value}/${tab}`)
}

async function programmZuordnungenAktualisieren(silent = false) {
  zuordnungLade.value = true
  if (!silent) zuordnungNachricht.value = ''
  await synchronisiereProgrammZuordnungen(lagerId.value)
  const { data: bloeckeData } = await supabase.from('programmbloecke').select(
    'id, code, nummer, titel, tag, start_zeit, end_zeit, ort, verantwortlich, geschichte, sicherheitsueberlegungen, programmabschnitt, material, notizen, verantwortlich_zuordnungen',
  ).eq('lager_id', lagerId.value)
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

const willkommenLink = computed(() => `${window.location.origin}/lager/${lagerId.value}/willkommen`)

function mapBloecke(data: Record<string, unknown>[]): Block[] {
  return data.map((b) => ({
    ...(b as unknown as Block),
    programmabschnitt: (b.programmabschnitt as Programmabschnitt[] | undefined) ?? [],
    material: (b.material as MaterialItem[] | undefined) ?? [],
    verantwortlich_zuordnungen: (b.verantwortlich_zuordnungen as NamensZuordnung[] | undefined) ?? [],
  }))
}

async function ladeBloeckeBasis() {
  bloeckeLaden.value = true
  const { data, error: bErr } = await supabase
    .from('programmbloecke')
    .select(BLOECKE_BASIS_SELECT)
    .eq('lager_id', lagerId.value)
  if (!bErr && data) {
    bloecke.value = mapBloecke(data)
  }
  bloeckeLaden.value = false
}

async function ladeBloeckeVoll() {
  if (bloeckeVollGeladen.value) return
  bloeckeLaden.value = true
  const { data, error: bErr } = await supabase
    .from('programmbloecke')
    .select(BLOECKE_VOLL_SELECT)
    .eq('lager_id', lagerId.value)
  if (!bErr && data) {
    bloecke.value = mapBloecke(data)
    bloeckeVollGeladen.value = true
  }
  bloeckeLaden.value = false
}

async function ladeTnNavCount() {
  const { count } = await supabase
    .from('anmeldungen_tn')
    .select('*', { count: 'exact', head: true })
    .eq('lager_id', lagerId.value)
  tnNavCount.value = count ?? 0
}

async function ladeLetzteAenderungenListe() {
  letzteAenderungen.value = await ladeLetzteAenderungen(lagerId.value, 10)
}

async function ladeNavKontext() {
  const tasks: Promise<unknown>[] = [ladeLeiter(), ladeTnNavCount()]
  if (session.value) {
    const uid = session.value.user.id
    tasks.push(
      (async () => {
        const { data: p } = await supabase.from('profiles').select('vorname, nachname').eq('id', uid).single()
        profil.value = p
      })(),
      pruefeKueche(),
      ladeMeineAemtli(),
      ladeTeam(),
    )
  }
  await Promise.all(tasks)
  await ladeMoerderliStatus()
}

async function ladeTabDaten(tab: Tab) {
  if (tab === 'programm') {
    await Promise.all([ladeBloeckeVoll(), ladeWetterFallsNoetig()])
    return
  }
  if (tab === 'leiter') {
    await Promise.all([ladeLeiter(), ladeLeiterRollen(), ladeAemtli(), ladeOrgPersonenPool()])
    return
  }
  if (tab === 'teilnehmer') {
    await ladeTeilnehmer()
    return
  }
  if (tab === 'gruppen') {
    await ladeGruppen()
    return
  }
  if (tab === 'einstellungen') {
    const { data } = await supabase
      .from('lager')
      .select('id, name, jahr')
      .neq('id', lagerId.value)
      .order('jahr', { ascending: false })
    andereLager.value = data ?? []
    return
  }
  if (tab === 'dashboard') {
    await Promise.all([ladeLetzteAenderungenListe(), ladeProgrammStatistik(), ladeMoerderliStatus()])
  }
}

async function ladeLagerSeite() {
  loading.value = true
  error.value = ''
  bloeckeVollGeladen.value = false
  bloecke.value = []
  tnNavCount.value = 0
  wetter.value = []

  const { data: lagerData, error: lagerError } = await supabase
    .from('lager')
    .select('id, name, jahr, organisation_id, ort, start_datum, end_datum, status, ort_lat, ort_lng, created_by, vor_lager_id, vorweekend_start, vorweekend_ende')
    .eq('id', lagerId.value)
    .single()

  if (lagerError) {
    error.value = lagerError.message ?? 'Lager konnte nicht geladen werden.'
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
  vorLagerIdForm.value = lagerData.vor_lager_id ?? ''
  loading.value = false

  await Promise.all([ladeBloeckeBasis(), ladeNavKontext()])
  await ladeTabDaten(activeTab.value)
}

onMounted(() => { void ladeLagerSeite() })
watch(lagerId, () => { void ladeLagerSeite() })

async function ladeWetterFallsNoetig() {
  if (wetter.value.length || !lager.value) return
  if (!lager.value.ort_lat || !lager.value.ort_lng || !lager.value.start_datum || !lager.value.end_datum) return
  try {
    wetter.value = await ladeWetter(lager.value.ort_lat, lager.value.ort_lng, lager.value.start_datum, lager.value.end_datum)
  } catch { /* optional */ }
}

watch(activeTab, (tab) => { void ladeTabDaten(tab) })

watch(
  () => route.name,
  (name) => {
    if (name !== 'programm' || !lager.value) return
    const heute = heuteIso()
    if (lagerLaeuft(lager.value.start_datum, lager.value.end_datum) && alleProgrammTage.value.includes(heute)) {
      router.replace(`/lager/${lagerId.value}/programm/tag/${heute}`)
    }
  },
)
</script>

<template>
  <div class="lager-page">
    <div class="lager-top-full">
      <AppHeader
        :lager-name="lager?.name"
        :show-alle-lager="true"
        show-nav-toggle
        :nav-open="navOffen"
        @toggle-nav="navOffen = !navOffen"
      />
      <LagerNav
        v-if="lager"
        :lager-id="lagerId"
        :active-tab="activeTab"
        :programm-link="programmLink"
        :meine-aemtli="meineAemtli"
        :is-leitung="isLeitung"
        :hat-kueche-tab="hatKuecheTab"
        :leiter-anfragen="leiterAnfragen.length"
        :tn-count="tnCountNav"
        :leiter-count="leiterBestaetigt.length + leiterProvisorisch.length"
        :mobile-open="navOffen"
        :moerderli-aktiv="moerderliAktiv"
        @close="navOffen = false"
      />
    </div>

    <main class="lager-main">
    <p v-if="loading">Lade...</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <template v-else-if="lager">

      <section v-if="activeTab === 'dashboard'">
        <LagerTimelinePanel
          :lager-id="lagerId"
          :start-datum="lager.start_datum"
          :end-datum="lager.end_datum"
          :is-leitung="isLeitung"
          @fahrplan="tabWechseln('fahrplan')"
        />
        <LagerDashboard
          :lager="lager"
          :bloecke="bloecke"
          :user-name="userName"
          :ist-anwesend="istAnwesend"
          :bearbeiten="true"
          :hat-kueche-tab="hatKuecheTab"
          :is-leitung="isLeitung"
          :leiter-anfragen="leiterAnfragen.length"
          :letzte-aenderungen="letzteAenderungen"
          :programm-statistik="programmStatistik"
          @tab="tabWechseln($event as Tab)"
          @hoeck="zuHoeckImProgramm"
          @block="zuBlockSpringen"
        />
        <LagerMap
          v-if="lager.ort || (lager.ort_lat && lager.ort_lng)"
          :lat="lager.ort_lat"
          :lng="lager.ort_lng"
          :ort="lager.ort"
        />
      </section>

      <!-- Fahrplan -->
      <section v-if="activeTab === 'fahrplan'">
        <LagerFahrplan
          :lager-id="lagerId"
          :start-datum="lager.start_datum"
          :is-leitung="isLeitung"
          :vor-lager-id="lager.vor_lager_id"
        />
      </section>

      <!-- Vorweekend -->
      <section v-if="activeTab === 'vorweekend'">
        <VorweekendPanel
          :lager-id="lagerId"
          :vorweekend-start="lager.vorweekend_start"
          :vorweekend-ende="lager.vorweekend_ende"
        />
      </section>

      <!-- Elterninfo -->
      <section v-if="activeTab === 'elterninfo'">
        <ElterninfoPanel
          :lager-id="lagerId"
          :lager-name="lager.name"
          :jahr="lager.jahr"
          :start-datum="lager.start_datum"
          :end-datum="lager.end_datum"
          :ort="lager.ort"
        />
      </section>

      <!-- Programm -->
      <section v-if="activeTab === 'programm'">
        <p v-if="bloeckeLaden && !bloeckeVollGeladen" class="hint">Lade Programmdetails…</p>

        <div v-if="programmRoute.view !== 'block' && programmRoute.view !== 'neu' && wetter.length" class="wetter-banner">
          <span v-for="w in wetter.slice(0, 5)" :key="w.datum" class="wetter-tag">
            {{ formatTag(w.datum) }}: {{ w.beschreibung }} {{ w.tempMin }}–{{ w.tempMax }}°
          </span>
        </div>

        <div v-if="programmRoute.view !== 'block' && programmRoute.view !== 'neu' && bloecke.length" class="programm-toolbar">
          <button class="secondary klein" :disabled="zuordnungLade" @click="programmZuordnungenAktualisieren()">
            {{ zuordnungLade ? 'Gleiche ab...' : 'Namen mit Leitern/Ämtli abgleichen' }}
          </button>
          <span v-if="zuordnungNachricht" class="hint">{{ zuordnungNachricht }}</span>
        </div>

        <ProgrammGesamt
          v-if="programmRoute.view === 'gesamt'"
          :lager-id="lagerId"
          :start-datum="lager.start_datum"
          :end-datum="lager.end_datum"
          :bloecke="bloecke"
        />

        <ProgrammTag
          v-else-if="programmRoute.view === 'tag' && session"
          :lager-id="lagerId"
          :tag="programmRoute.date"
          :bloecke="bloecke"
          :session-user-id="session.user.id"
          :user-name="userName"
          :alle-tage="alleProgrammTage"
          :start-datum="lager.start_datum"
          :end-datum="lager.end_datum"
        />

        <ProgrammBlockEdit
          v-else-if="programmRoute.view === 'block'"
          :lager-id="lagerId"
          :block-id="programmRoute.blockId"
          @saved="programmBlockGespeichert"
        />

        <ProgrammBlockEdit
          v-else-if="programmRoute.view === 'neu'"
          :lager-id="lagerId"
          @saved="programmBlockGespeichert"
        />

        <p v-if="programmRoute.view === 'gesamt' && !bloecke.length" class="hint">
          Noch keine Programmblöcke. «Neues Programm» klicken oder eCamp-PDF importieren.
        </p>
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

        <div v-if="leiterProvisorisch.length" class="anfragen-box">
          <h3>Provisorisch angemeldet ({{ leiterProvisorisch.length }})</h3>
          <p class="hint">Spätestens 3 Monate vor Lager bestätigen – An-/Abreisedaten festlegen.</p>
          <div v-for="a in leiterProvisorisch" :key="a.id" class="anfrage-karte">
            <strong>{{ a.vorname }} {{ a.nachname }}</strong>
            <span v-if="a.von_vorjahr" class="badge prov">Vorjahr</span>
            <span class="hint">
              {{ a.email ?? '–' }}
              <template v-if="a.bestaetigen_bis"> · bestätigen bis {{ formatFaelligkeit(a.bestaetigen_bis) }}</template>
            </span>
            <div v-if="isLeitung || a.profile_id === session?.user.id" class="inline-form">
              <button @click="leiterBestaetigen(a.id)">Als fix bestätigen</button>
            </div>
          </div>
        </div>

        <div v-if="leiterAnfragen.length && isLeitung" class="anfragen-box">
          <h3>Offene Anfragen ({{ leiterAnfragen.length }})</h3>
          <div v-for="a in leiterAnfragen" :key="a.id" class="anfrage-karte">
            <strong>{{ a.vorname }} {{ a.nachname }}</strong>
            <span class="hint">{{ a.email }} · {{ a.anwesend_von ?? '?' }} – {{ a.anwesend_bis ?? '?' }}</span>
            <div v-if="passendeManuelleLeiter(a).length" class="verknuepf-box">
              <label>
                Mit manuellem Eintrag verknüpfen
                <select v-model="verknuepfManuell[a.id]">
                  <option value="">Als neuen Leiter freischalten</option>
                  <option v-for="m in passendeManuelleLeiter(a)" :key="m.id" :value="m.id">
                    {{ m.vorname }} {{ m.nachname }} (manuell erfasst)
                  </option>
                </select>
              </label>
            </div>
            <div class="inline-form">
              <button @click="leiterAnfrageBearbeiten(a.id, 'genehmigen')">Freischalten</button>
              <button class="secondary" @click="leiterAnfrageBearbeiten(a.id, 'ablehnen')">Ablehnen</button>
            </div>
          </div>
        </div>

        <table v-if="leiterBestaetigt.length" class="liste">
          <thead><tr><th>Name</th><th>Login</th><th>Alter</th><th>Gruppe</th><th>Anwesend</th><th>Status</th><th>Ämtli</th></tr></thead>
          <tbody>
            <tr v-for="l in leiterBestaetigt" :key="l.id">
              <td>{{ l.vorname }} {{ l.nachname }} <span v-if="l.von_vorjahr" class="badge prov">VJ</span></td>
              <td>
                <span v-if="l.profile_id" class="hint">✓</span>
                <span v-else class="login-offen">ohne Login</span>
              </td>
              <td>{{ berechneAlter(l.geburtsdatum) ?? '–' }}</td>
              <td><span v-if="gruppeTagLeiter[l.id]" class="gruppen-tag">{{ gruppeTagLeiter[l.id] }}</span><span v-else>–</span></td>
              <td>{{ l.anwesend_von ?? '–' }} – {{ l.anwesend_bis ?? '–' }}</td>
              <td>{{ l.anmeldung_art === 'provisorisch' ? 'provisorisch' : 'fix' }}</td>
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
        <h3>Leiter hinzufügen (aus Verein)</h3>
        <p class="hint">
          Neue Leiter zuerst im <router-link :to="`/organisation?org=${lager.organisation_id ?? ''}`">Verein erfassen</router-link>,
          danach hier auswählen.
        </p>
        <form @submit.prevent="leiterHinzufuegen" class="inline-form">
          <select v-model="orgPersonAuswahl" required>
            <option value="">Person aus Verein wählen</option>
            <option
              v-for="p in orgPersonenPool.filter((p) => !leiterListe.some((l) => l.vorname === p.vorname && l.nachname === p.nachname))"
              :key="p.id"
              :value="p.id"
            >
              {{ p.vorname }} {{ p.nachname }}{{ p.profile_id ? '' : ' (ohne Login)' }}
            </option>
          </select>
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
          :lager-id="lagerId" :aemtli-id="a.id" :lager-name="lager.name"
          :user-id="session.user.id" :start-datum="lager.start_datum" :end-datum="lager.end_datum"
          :bloecke="bloecke.map((b) => ({ id: b.id, titel: b.titel, code: b.code }))"
        />
        <AemtliFinanzen
          v-else-if="aemtliKomponente(a.name) === 'finanzen'"
          :lager-id="lagerId" :aemtli-id="a.id" :ist-kassier="hatFinanzenAemtli"
        />
        <AemtliKiosk v-else-if="aemtliKomponente(a.name) === 'kiosk'" :lager-id="lagerId" :aemtli-id="a.id" :aemtli-name="a.name" :start-datum="lager.start_datum" :end-datum="lager.end_datum" />
        <AemtliTelefon v-else-if="aemtliKomponente(a.name) === 'telefon'" :lager-id="lagerId" :aemtli-id="a.id" :aemtli-name="a.name" />
        <AemtliGuteFee v-else-if="aemtliKomponente(a.name) === 'gute_fee'" :lager-id="lagerId" :aemtli-id="a.id" :aemtli-name="a.name" :is-gute-fee="true" :start-datum="lager.start_datum" :end-datum="lager.end_datum" />
        <AemtliSkiweekend v-else-if="aemtliKomponente(a.name) === 'skiweekend'" :lager-id="lagerId" :aemtli-id="a.id" :aemtli-name="a.name" />
        <AemtliKrankenpflege v-else-if="aemtliKomponente(a.name) === 'krankenpflege'" :lager-id="lagerId" :aemtli-id="a.id" :aemtli-name="a.name" />
        <AemtliKuchenstand v-else-if="aemtliKomponente(a.name) === 'kuchenstand'" :lager-id="lagerId" :aemtli-id="a.id" :aemtli-name="a.name" />
        <AemtliSponsoring v-else-if="aemtliKomponente(a.name) === 'sponsoring'" :lager-id="lagerId" :aemtli-id="a.id" :aemtli-name="a.name" />
        <AemtliGelaende v-else-if="aemtliKomponente(a.name) === 'gelaende'" :lager-id="lagerId" :aemtli-id="a.id" :aemtli-name="a.name" :lat="lager.ort_lat" :lng="lager.ort_lng" />
        <AemtliBastel v-else-if="aemtliKomponente(a.name) === 'bastel'" :lager-id="lagerId" :aemtli-id="a.id" :aemtli-name="a.name" />
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

        <h3>Vorjahres-Lager</h3>
        <p class="hint">Für Leiter-Übernahme und Fahrplan – wird beim «Leiter vom Vorjahr» verwendet.</p>
        <div class="inline-form">
          <select v-model="vorLagerIdForm">
            <option value="">– keins –</option>
            <option v-for="a in andereLager" :key="a.id" :value="a.id">{{ a.name }} ({{ a.jahr }})</option>
          </select>
          <button type="button" class="secondary" @click="vorLagerSpeichern">Speichern</button>
        </div>

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
  </div>
</template>

<style scoped>
.hint { color: var(--color-text-muted); font-size: 0.9rem; }
.geschuetzt-hinweis { padding: 0.6rem 0.85rem; background: var(--color-surface-muted); border-radius: var(--radius-md); margin-bottom: 1rem; }
.lager-page { min-height: 100vh; }
.lager-top-full {
  position: sticky;
  top: 0;
  z-index: 100;
  width: 100%;
  background: var(--color-surface);
  border-bottom: 1px solid var(--color-border);
  margin-bottom: 0.5rem;
  box-shadow: 0 1px 0 rgba(0, 0, 0, 0.04);
}
.lager-main {
  max-width: 960px;
  margin: 0 auto;
  padding: 0 1rem 2rem;
}
.login-offen { font-size: 0.78rem; color: var(--color-text-muted); font-style: italic; }
.verknuepf-box { margin: 0.5rem 0; }
.verknuepf-box label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.82rem; color: var(--color-text-muted); }
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
.link-box { display: block; background: var(--color-surface-muted); padding: 0.5rem 0.75rem; border-radius: var(--radius-md); font-size: 0.85rem; word-break: break-all; margin: 0.5rem 0 1.5rem; }
.error { color: var(--color-danger); }
.anfragen-box { margin-bottom: 1.25rem; padding: 1rem; background: var(--color-surface-muted); border-radius: var(--radius-md); }
.anfrage-karte { padding: 0.6rem 0; border-bottom: 1px solid var(--color-border); }
.anfrage-karte:last-child { border-bottom: none; }
.badge.prov { display: inline-block; margin-left: 0.35rem; padding: 0.05rem 0.4rem; border-radius: var(--radius-pill); font-size: 0.7rem; background: #c98a3f; color: #fff; }
.lager-form { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 0.75rem; margin-bottom: 1.5rem; }
.lager-form label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.85rem; color: var(--color-text-muted); }
</style>
