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
import ProgrammGesamt from '../components/lager/ProgrammGesamt.vue'
import ProgrammTag from '../components/lager/ProgrammTag.vue'
import ProgrammBlockEdit from '../components/lager/ProgrammBlockEdit.vue'
import ProgrammImportPanel from '../components/lager/ProgrammImportPanel.vue'
import { heuteIso, tageZwischen } from '../lib/programmUtils'
import { pruefeTnAnmeldungAktivierung } from '../lib/tnAnmeldung'
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
import AemtliMotto from '../components/lager/AemtliMotto.vue'
import AemtliMaterial from '../components/lager/AemtliMaterial.vue'
import StatistikPanel from '../components/lager/StatistikPanel.vue'
import LagerGeminiPanel from '../components/lager/LagerGeminiPanel.vue'
import LagerChatbotPanel from '../components/lager/LagerChatbotPanel.vue'
import QuittungenPanel from '../components/lager/QuittungenPanel.vue'
import LagerFahrplan from '../components/lager/LagerFahrplan.vue'
import VorweekendPanel from '../components/lager/VorweekendPanel.vue'
import ElterninfoPanel from '../components/lager/ElterninfoPanel.vue'
import LeiterZeitstrahlPanel from '../components/lager/LeiterZeitstrahlPanel.vue'
import LagerKalenderPanel from '../components/lager/LagerKalenderPanel.vue'
import OeffentlicheTerminePanel from '../components/lager/OeffentlicheTerminePanel.vue'
import LagerNav from '../components/lager/LagerNav.vue'
import AppHeader from '../components/AppHeader.vue'
import { aemtliSlug, tabIdForAemtli } from '../lib/aemtliSlug'
import { GESCHUETZTE_AEMTLI, istGeschuetztesAemtli } from '../lib/aemtliPermissions'
import { synchronisiereProgrammZuordnungen } from '../lib/programmZuordnung'
import type { MaterialMitZuordnung, NamensZuordnung, ProgrammabschnittMitZuordnung } from '../lib/nameMatching'
import { bestaetigenBis, formatFaelligkeit } from '../lib/workflowUtils'
import { logLagerAktivitaet, ladeLetzteAenderungen, type LagerAenderung } from '../lib/lagerAktivitaet'
import { isNavSectionAllowed } from '../lib/lagerNavConfig'
import { leiterAlsCsv, leiterCsvDownload, type LeiterExportZeile } from '../lib/leiterCsv'
import LagerBearbeitung from '../components/lager/LagerBearbeitung.vue'

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
  telefon?: string | null
  geburtsdatum: string | null
  geschlecht: string | null
  ahv_nr: string | null
  anwesend_von: string | null
  anwesend_bis: string | null
  status: string
  anmeldung_art?: string
  bestaetigen_bis?: string | null
  von_vorjahr?: boolean
  essensgewohnheiten?: string | null
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
interface LeiterZeile {
  leiter: LeiterAnmeldung
  team: TeamMitglied | null
  nurTeam: boolean
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

type Tab = 'dashboard' | 'chatbot' | 'programm' | 'teilnehmer' | 'leiter' | 'gruppen' | 'einkauf' | 'team' | 'einstellungen' | 'quittungen' | 'fahrplan' | 'vorweekend' | 'elterninfo' | 'statistik' | 'gemini' | string

const activeTab = computed<Tab>(() => {
  if (route.name === 'lager-aemtli') return `aemtli:${route.params.aemtliSlug as string}`
  if (typeof route.name === 'string' && route.name.startsWith('programm')) return 'programm'
  return (route.params.section as string) || 'dashboard'
})

const tabErlaubt = computed(() => {
  if (activeTab.value.startsWith('aemtli:')) {
    const slug = activeTab.value.slice(7)
    if (meineAemtli.value.some((a) => aemtliSlug(a.name) === slug)) return true
    if (slug === 'finanzen' && isLeitung.value) return true
    return false
  }
  if (!isNavSectionAllowed(activeTab.value)) return false
  return true
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
  return `/lager/${lagerId.value}/programm`
})
const profil = ref<{ vorname: string | null; nachname: string | null } | null>(null)
const istKueche = ref(false)
const meineAemtli = ref<Aemtli[]>([])
const zugewieseneAemtli = ref<Aemtli[]>([])

/** Nur echtes Finanzen-Ämtli – Lagerleitung allein zählt nicht */
const hatFinanzenAemtli = computed(() =>
  zugewieseneAemtli.value.some((a) => aemtliSlug(a.name) === 'finanzen'),
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
const organisationName = ref('')
const lagerLoeschen = ref(false)
const lagerLoeschenFehler = ref('')

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

const leiterZeilen = computed<LeiterZeile[]>(() => {
  const teamByProfile = new Map<string, TeamMitglied>()
  for (const t of teamListe.value) teamByProfile.set(t.profile_id, t)

  const zeilen: LeiterZeile[] = leiterBestaetigt.value.map((leiter) => ({
    leiter,
    team: leiter.profile_id ? (teamByProfile.get(leiter.profile_id) ?? null) : null,
    nurTeam: false,
  }))

  const leiterProfileIds = new Set(
    leiterBestaetigt.value.map((l) => l.profile_id).filter((id): id is string => !!id),
  )
  for (const t of teamListe.value) {
    if (leiterProfileIds.has(t.profile_id)) continue
    zeilen.push({
      leiter: {
        id: `team-only-${t.id}`,
        profile_id: t.profile_id,
        vorname: t.profiles?.vorname ?? '',
        nachname: t.profiles?.nachname ?? '',
        email: t.profiles?.email,
        telefon: null,
        geburtsdatum: null,
        geschlecht: null,
        ahv_nr: null,
        anwesend_von: null,
        anwesend_bis: null,
        status: 'bestaetigt',
      },
      team: t,
      nurTeam: true,
    })
  }

  return zeilen.sort((a, b) =>
    `${a.leiter.nachname} ${a.leiter.vorname}`.localeCompare(
      `${b.leiter.nachname} ${b.leiter.vorname}`,
      'de',
    ),
  )
})

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

async function programmImportiert() {
  bloeckeVollGeladen.value = false
  await ladeBloeckeVoll()
  await ladeLetzteAenderungenListe()
}

async function geminiVorschlagAngewendet(actionType: string) {
  if (
    actionType === 'insert_programmblock'
    || actionType === 'update_programmblock'
    || actionType === 'delete_programmblock'
  ) {
    bloeckeVollGeladen.value = false
    await ladeBloeckeVoll()
  }
  if (actionType === 'insert_tn' || actionType === 'update_tn') {
    await Promise.all([ladeTeilnehmer(), ladeGruppen()])
  }
  if (
    actionType === 'insert_leiter'
    || actionType === 'update_leiter'
    || actionType === 'assign_leiter_aemtli'
  ) {
    await Promise.all([ladeLeiter(), ladeLeiterRollen(), ladeTeam(), ladeGruppen()])
  }
  if (actionType === 'create_gruppe' || actionType === 'assign_gruppenmitglied') {
    await ladeGruppen()
  }
  await ladeLetzteAenderungenListe()
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

async function tnLoeschen(tnId: string) {
  if (!isLeitung.value) return
  const sicher = window.confirm('Teilnehmer/in wirklich löschen?')
  if (!sicher) return
  await supabase.from('anmeldungen_tn').delete().eq('id', tnId).eq('lager_id', lagerId.value)
  await Promise.all([ladeTeilnehmer(), ladeGruppen()])
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
const leiterBearbeitenId = ref<string | null>(null)
const leiterListenAnsicht = ref<'grob' | 'detail' | 'verwaltung'>('grob')
const leiterEditForm = ref({
  vorname: '',
  nachname: '',
  geburtsdatum: '',
  geschlecht: '',
  ahv_nr: '',
  telefon: '',
  anwesend_von: '',
  anwesend_bis: '',
})

const verfuegbareOrgPersonen = computed(() =>
  orgPersonenPool.value.filter((p) => {
    if (p.profile_id && leiterListe.value.some((l) => l.profile_id === p.profile_id)) return false
    const name = `${p.vorname} ${p.nachname}`.trim().toLowerCase()
    if (!name) return true
    return !leiterListe.value.some(
      (l) => `${l.vorname} ${l.nachname}`.trim().toLowerCase() === name,
    )
  }),
)

const istBestaetigterLeiter = computed(() =>
  !!teamListe.value.find((t) => t.profile_id === session.value?.user.id && t.status === 'bestaetigt'),
)

const leiterExportZeilen = computed<LeiterExportZeile[]>(() =>
  leiterBestaetigt.value.map((l) => {
    const team = teamListe.value.find((t) => t.profile_id === l.profile_id)
    const aemtli = (leiterRollenMap.value[l.id] ?? []).map((r) => r.name).join(', ')
    return {
      vorname: l.vorname,
      nachname: l.nachname,
      email: team?.profiles?.email ?? l.email,
      telefon: l.telefon,
      geburtsdatum: l.geburtsdatum,
      geschlecht: l.geschlecht,
      ahv_nr: l.ahv_nr,
      anwesend_von: l.anwesend_von,
      anwesend_bis: l.anwesend_bis,
      status: l.status,
      anmeldung_art: l.anmeldung_art,
      essensgewohnheiten: l.essensgewohnheiten,
      profile_id: l.profile_id,
      aemtli: aemtli || undefined,
      app_rolle: team?.rolle,
    }
  }),
)

function leiterCsvHerunterladen() {
  const name = (lager.value?.name ?? 'lager').replace(/\s+/g, '_')
  leiterCsvDownload(`${name}_leiter.csv`, leiterAlsCsv(leiterExportZeilen.value))
}

async function ladeLeiter() {
  const { data } = await supabase
    .from('anmeldungen_leiter')
    .select('id, profile_id, vorname, nachname, email, telefon, geburtsdatum, geschlecht, ahv_nr, anwesend_von, anwesend_bis, status, anmeldung_art, bestaetigen_bis, von_vorjahr, essensgewohnheiten')
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

async function leiterLoeschen(leiter: LeiterAnmeldung) {
  if (!isLeitung.value) return
  const sicher = window.confirm(`Leiter "${leiter.vorname} ${leiter.nachname}" wirklich löschen?`)
  if (!sicher) return
  leiterFehler.value = ''
  const { error: delErr } = await supabase.rpc('leiter_anmeldung_sicher_loeschen', {
    p_anmeldung_id: leiter.id,
  })
  if (delErr) {
    leiterFehler.value = delErr.message
    if (delErr.message.includes('letzte Lagerleitung')) {
      window.alert('Es muss mindestens eine Person die Rolle Lagerleitung (Lalei) behalten.')
    }
    return
  }
  await Promise.all([leiterNachAenderung(), ladeTeam(), ladeGruppen()])
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

  const { data, error } = await supabase.rpc('list_verein_personen_fuer_lager', {
    p_organisation_id: orgId,
  })

  if (!error && data?.length) {
    orgPersonenPool.value = data.map((row: {
      id: string
      profile_id: string | null
      vorname: string
      nachname: string
      email: string | null
    }) => ({
      id: row.id,
      profile_id: row.profile_id,
      vorname: row.vorname,
      nachname: row.nachname,
      email: row.email,
    }))
    return
  }

  const [{ data: mitglieder }, { data: personen }] = await Promise.all([
    supabase.rpc('list_verein_mitglieder_mit_profil', { p_organisation_id: orgId }),
    supabase
      .from('org_personen')
      .select('id, profile_id, vorname, nachname, email')
      .eq('organisation_id', orgId)
      .eq('aktiv', true),
  ])

  const pool: OrgPersonPool[] = []
  const profileIds = new Set<string>()

  for (const m of mitglieder ?? []) {
    if (!m.profile_id) continue
    profileIds.add(m.profile_id)
    pool.push({
      id: `login-${m.profile_id}`,
      profile_id: m.profile_id,
      vorname: m.vorname ?? '',
      nachname: m.nachname ?? '',
      email: m.email ?? null,
    })
  }

  for (const p of personen ?? []) {
    if (p.profile_id && profileIds.has(p.profile_id)) continue
    pool.push({
      id: `person-${p.id}`,
      profile_id: p.profile_id,
      vorname: p.vorname,
      nachname: p.nachname,
      email: p.email,
    })
  }

  pool.sort((a, b) => `${a.nachname} ${a.vorname}`.localeCompare(`${b.nachname} ${b.vorname}`, 'de'))
  orgPersonenPool.value = pool
  if (error && !pool.length) leiterFehler.value = error.message
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

  let pProfileId: string | null = person.profile_id
  let pOrgPersonId: string | null = null
  if (person.id.startsWith('login-')) {
    pProfileId = person.id.slice(6)
  } else if (person.id.startsWith('person-')) {
    pOrgPersonId = person.id.slice(7)
    if (!pProfileId) pProfileId = null
  }

  const { error: err } = await supabase.rpc('lager_leiter_aus_verein_hinzufuegen', {
    p_lager_id: lagerId.value,
    p_profile_id: pProfileId,
    p_org_person_id: pOrgPersonId,
    p_als_lalei: false,
    p_anwesend_von: lager.value?.start_datum ?? null,
    p_anwesend_bis: lager.value?.end_datum ?? null,
    p_vorname: person.vorname || null,
    p_nachname: person.nachname || null,
  })
  leiterSpeichern.value = false
  if (err) {
    leiterFehler.value = err.message
    return
  }
  const name = `${person.vorname} ${person.nachname}`.trim() || person.email || 'Leiter'
  orgPersonAuswahl.value = ''
  void logLagerAktivitaet(lagerId.value, `Leiter aus Verein hinzugefügt: ${name}`, 'leiter')
  await leiterNachAenderung()
  await ladeLetzteAenderungenListe()
}

function darfLeiterBearbeiten(l: LeiterAnmeldung) {
  return isLeitung.value || (l.profile_id != null && l.profile_id === session.value?.user.id)
}

function leiterBearbeitenStart(l: LeiterAnmeldung) {
  if (l.id.startsWith('team-only-')) return
  if (leiterBearbeitenId.value === l.id) {
    leiterBearbeitenId.value = null
    return
  }
  leiterBearbeitenId.value = l.id
  leiterEditForm.value = {
    vorname: l.vorname,
    nachname: l.nachname,
    geburtsdatum: l.geburtsdatum ?? '',
    geschlecht: l.geschlecht ?? '',
    ahv_nr: l.ahv_nr ?? '',
    telefon: l.telefon ?? '',
    anwesend_von: l.anwesend_von ?? '',
    anwesend_bis: l.anwesend_bis ?? '',
  }
}

function leiterBearbeitenAbbrechen() {
  leiterBearbeitenId.value = null
}

async function leiterBearbeitenSpeichern() {
  if (!leiterBearbeitenId.value) return
  leiterFehler.value = ''
  const { error: err } = await supabase.rpc('leiter_anmeldung_speichern', {
    p_anmeldung_id: leiterBearbeitenId.value,
    p_vorname: leiterEditForm.value.vorname,
    p_nachname: leiterEditForm.value.nachname,
    p_geburtsdatum: leiterEditForm.value.geburtsdatum || null,
    p_geschlecht: leiterEditForm.value.geschlecht || null,
    p_ahv_nr: leiterEditForm.value.ahv_nr || null,
    p_telefon: leiterEditForm.value.telefon || null,
    p_anwesend_von: leiterEditForm.value.anwesend_von || null,
    p_anwesend_bis: leiterEditForm.value.anwesend_bis || null,
  })
  if (err) {
    leiterFehler.value = err.message
    return
  }
  leiterBearbeitenId.value = null
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
  const leiterMitAlter = leiterListe.value
    .filter((l) => ['bestaetigt', 'angemeldet'].includes(l.status))
    .map((l) => ({ ...l, alter: berechneAlter(l.geburtsdatum) }))
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
  leiterFehler.value = ''
  const { error } = await supabase.rpc('lager_leiter_sicher_entfernen', { p_lager_leiter_id: teamId })
  if (error) {
    leiterFehler.value = error.message
    if (error.message.includes('letzte Lagerleitung')) {
      window.alert('Es muss mindestens eine Person die Rolle Lagerleitung (Lalei) behalten.')
    }
    return
  }
  await Promise.all([ladeTeam(), ladeLeiter()])
}

async function teamRolleAendern(teamId: string, rolle: string) {
  leiterFehler.value = ''
  const { error } = await supabase.rpc('lager_leiter_rolle_setzen', {
    p_lager_leiter_id: teamId,
    p_rolle: rolle,
  })
  if (error) {
    leiterFehler.value = error.message
    if (error.message.includes('mindestens eine Person')) {
      window.alert('Es muss mindestens eine Person die Rolle Lagerleitung (Lalei) behalten.')
    }
    return
  }
  await Promise.all([ladeTeam(), ladeLeiter()])
}

// --- Einstellungen / ICS ---
const statusSpeichern = ref(false)
const statusFehler = ref('')
const statusFehlendLinks = ref<{ label: string; tab: string }[]>([])

async function vorLagerSpeichern() {
  if (!lager.value) return
  await supabase.from('lager').update({ vor_lager_id: vorLagerIdForm.value || null }).eq('id', lagerId.value)
  lager.value.vor_lager_id = vorLagerIdForm.value || null
}

async function statusAendern(neuerStatus: string) {
  statusFehler.value = ''
  statusFehlendLinks.value = []
  if (neuerStatus === 'anmeldung_offen' && lager.value) {
    const check = pruefeTnAnmeldungAktivierung(lager.value)
    if (!check.ok) {
      statusFehler.value = `TN-Anmeldung kann erst aktiviert werden, wenn alle Pflichtangaben gesetzt sind.`
      statusFehlendLinks.value = check.fehlend
      return
    }
  }
  statusSpeichern.value = true
  const { error } = await supabase.from('lager').update({ status: neuerStatus }).eq('id', lagerId.value)
  statusSpeichern.value = false
  if (error) {
    statusFehler.value = error.message
    return
  }
  if (lager.value) lager.value.status = neuerStatus
}

function zuPflichtTab(tab: string) {
  void router.push(`/lager/${lagerId.value}/${tab}`)
}

function pflichtTabLabel(tab: string) {
  if (tab === 'einstellungen') return 'Zu Einstellungen'
  if (tab === 'teilnehmer') return 'Zu Teilnehmer'
  if (tab === 'kalender') return 'Zum Kalender'
  return tab
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
    await supabase.rpc('lager_termine_sync', { p_lager_id: lagerId.value })
  }
}

async function lagerLoeschenFn() {
  if (!isLeitung.value || !lager.value) return
  const sicher = window.confirm(
    `Lager "${lager.value.name}" wirklich löschen?\n\nDieser Schritt kann nicht rückgängig gemacht werden.`,
  )
  if (!sicher) return

  lagerLoeschen.value = true
  lagerLoeschenFehler.value = ''
  const { error: err } = await supabase.from('lager').delete().eq('id', lagerId.value)
  lagerLoeschen.value = false

  if (err) {
    lagerLoeschenFehler.value = err.message
    return
  }
  await router.replace('/organisation')
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
  const zugewiesen = new Map<string, Aemtli>()

  if (leiterIds.length) {
    const { data: lr } = await supabase
      .from('leiter_rollen')
      .select('aemtli:aemtli_id ( id, name )')
      .in('anmeldung_leiter_id', leiterIds)
    for (const row of lr ?? []) {
      const a = row.aemtli as unknown as Aemtli
      if (a?.id) zugewiesen.set(a.id, a)
    }
  }

  zugewieseneAemtli.value = [...zugewiesen.values()].sort((a, b) => a.name.localeCompare(b.name))

  const set = new Map(zugewiesen)

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
    await Promise.all([ladeLeiter(), ladeLeiterRollen(), ladeAemtli(), ladeOrgPersonenPool(), ladeGruppen()])
    return
  }
  if (tab === 'teilnehmer') {
    await Promise.all([ladeTeilnehmer(), ladeGruppen()])
    return
  }
  if (tab === 'gruppen') {
    await Promise.all([ladeTeilnehmer(), ladeLeiter(), ladeGruppen()])
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
  organisationName.value = ''
  if (lagerData.organisation_id) {
    const { data: org } = await supabase
      .from('organisation')
      .select('name')
      .eq('id', lagerData.organisation_id)
      .single()
    organisationName.value = org?.name ?? ''
  }
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
        :is-leitung="isLeitung"
        :meine-aemtli="meineAemtli"
        :leiter-anfragen="leiterAnfragen.length"
        :tn-count="tnCountNav"
        :leiter-count="leiterBestaetigt.length + leiterProvisorisch.length"
        :mobile-open="navOffen"
        @close="navOffen = false"
      />
    </div>

    <main class="lager-main">
    <p v-if="loading">Lade...</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <template v-else-if="lager">

      <LagerBearbeitung v-if="!tabErlaubt" :lager-id="lagerId" :bereich="activeTab" />

      <template v-else>

      <section v-if="activeTab === 'dashboard'">
        <LagerTimelinePanel
          :lager-id="lagerId"
          :start-datum="lager.start_datum"
          :end-datum="lager.end_datum"
          :is-leitung="isLeitung"
          :zeige-fahrplan-link="false"
          @fahrplan="tabWechseln('fahrplan')"
        />
        <LagerDashboard
          :lager="lager"
          :bloecke="bloecke"
          :user-name="userName"
          :ist-anwesend="istAnwesend"
          :bearbeiten="true"
          :hat-kueche-tab="hatKuecheTab"
          :hat-finanzen-aemtli="hatFinanzenAemtli"
          :is-leitung="isLeitung"
          :leiter-anfragen="leiterAnfragen.length"
          :letzte-aenderungen="letzteAenderungen"
          :programm-statistik="programmStatistik"
          @tab="tabWechseln($event as Tab)"
          @hoeck="zuHoeckImProgramm"
          @block="zuBlockSpringen"
        />
      </section>

      <!-- Allgemeiner Lager-Chatbot -->
      <section v-if="activeTab === 'chatbot'">
        <LagerChatbotPanel
          :lager-id="lagerId"
          :lager-name="lager.name"
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

      <!-- Kalender -->
      <section v-if="activeTab === 'kalender'">
        <h2>Lager-Kalender</h2>
        <LagerKalenderPanel
          :lager-id="lagerId"
          :lager-name="lager.name"
          :organisation-id="lager.organisation_id"
          :organisation-name="organisationName"
          :is-leitung="isLeitung"
        />
      </section>

      <!-- Leiter-Zeitstrahl (Vollansicht) -->
      <section v-if="activeTab === 'leiter-zeitstrahl'">
        <h2>Leiter-Anwesenheit im Zeitverlauf</h2>
        <LeiterZeitstrahlPanel
          :lager-id="lagerId"
          :start-datum="lager.start_datum"
          :end-datum="lager.end_datum"
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

        <ProgrammImportPanel
          v-if="programmRoute.view === 'gesamt' && isLeitung && !bloecke.length"
          :lager-id="lagerId"
          @imported="programmImportiert"
        />

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
          :key="`block-${programmRoute.blockId}`"
          :lager-id="lagerId"
          :block-id="programmRoute.blockId"
          @saved="programmBlockGespeichert"
        />

        <ProgrammBlockEdit
          v-else-if="programmRoute.view === 'neu'"
          key="block-neu"
          :lager-id="lagerId"
          @saved="programmBlockGespeichert"
        />

        <p v-if="programmRoute.view === 'gesamt' && !bloecke.length" class="hint">
          Noch keine Programmblöcke. «Neues Programm» klicken oder eCamp-PDF importieren.
        </p>
      </section>

      <!-- Teilnehmer -->
      <section v-if="activeTab === 'teilnehmer'">
        <h3>TN-Anmeldung</h3>
        <p v-if="isLeitung" class="hint">
          «Anmeldung offen» oder «Laufend» erlauben die öffentliche TN-Anmeldung.
          Stammdaten (Name, Start, Ende, Ort) müssen unter Einstellungen gesetzt sein.
        </p>
        <div v-if="isLeitung" class="anmeldung-aktivierung">
          <label>
            Lager-Status für TN-Anmeldung
            <select :value="lager.status" @change="statusAendern(($event.target as HTMLSelectElement).value)" :disabled="statusSpeichern">
              <option value="planung">Planung (Anmeldung geschlossen)</option>
              <option value="anmeldung_offen">Anmeldung offen</option>
              <option value="laufend">Laufend (Anmeldung weiterhin möglich)</option>
              <option value="abgeschlossen">Abgeschlossen</option>
              <option value="archiviert">Archiviert</option>
            </select>
          </label>
          <p v-if="statusFehler" class="error">{{ statusFehler }}</p>
          <ul v-if="statusFehlendLinks.length" class="status-fehlend">
            <li v-for="f in statusFehlendLinks" :key="f.label">
              <strong>{{ f.label }}</strong> fehlt –
              <button type="button" class="link-like" @click="zuPflichtTab(f.tab)">
                {{ pflichtTabLabel(f.tab) }}
              </button>
            </li>
          </ul>
        </div>
        <p v-else class="hint">Status: <strong>{{ lager.status }}</strong></p>

        <OeffentlicheTerminePanel
          v-if="isLeitung"
          :lager-id="lagerId"
          :is-leitung="isLeitung"
          kompakt
        />

        <p class="hint">
          Anmeldung: <router-link :to="`/lager/${lagerId}/anmelden-tn`">/anmelden-tn</router-link> ·
          Infoseite TN: <router-link :to="`/lager/${lagerId}/willkommen`">/willkommen</router-link>
        </p>
        <table v-if="tnListe.length" class="liste">
          <thead>
            <tr>
              <th>Name</th><th>Alter</th><th>Gruppe</th><th>Rolle</th><th>Status</th>
              <th v-if="isLeitung"></th>
            </tr>
          </thead>
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
              <td v-if="isLeitung">
                <button type="button" class="secondary klein" @click="tnLoeschen(tn.id)">Entfernen</button>
              </td>
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

      <!-- Leiter & Team -->
      <section v-if="activeTab === 'leiter'">
        <h2>Leiter &amp; Team</h2>
        <LeiterZeitstrahlPanel
          v-if="lager.start_datum && lager.end_datum"
          :lager-id="lagerId"
          :start-datum="lager.start_datum"
          :end-datum="lager.end_datum"
        />
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

        <nav class="leiter-ansicht-nav">
          <button type="button" :class="{ aktiv: leiterListenAnsicht === 'grob' }" @click="leiterListenAnsicht = 'grob'">Übersicht</button>
          <button type="button" :class="{ aktiv: leiterListenAnsicht === 'detail' }" @click="leiterListenAnsicht = 'detail'">Detailansicht</button>
          <button type="button" :class="{ aktiv: leiterListenAnsicht === 'verwaltung' }" @click="leiterListenAnsicht = 'verwaltung'">Team &amp; Ämtli</button>
          <button v-if="leiterBestaetigt.length" type="button" class="secondary" @click="leiterCsvHerunterladen">CSV herunterladen</button>
        </nav>

        <table v-if="leiterListenAnsicht === 'grob' && leiterBestaetigt.length" class="liste">
          <thead>
            <tr><th>Name</th><th>Alter</th><th>Gruppe</th><th>Anwesend</th><th>Essen</th></tr>
          </thead>
          <tbody>
            <tr v-for="l in leiterBestaetigt" :key="l.id">
              <td>{{ l.vorname }} {{ l.nachname }}</td>
              <td>{{ berechneAlter(l.geburtsdatum) ?? '–' }}</td>
              <td><span v-if="gruppeTagLeiter[l.id]" class="gruppen-tag">{{ gruppeTagLeiter[l.id] }}</span><span v-else>–</span></td>
              <td>{{ l.anwesend_von ?? '–' }} – {{ l.anwesend_bis ?? '–' }}</td>
              <td>{{ l.essensgewohnheiten?.trim() || '–' }}</td>
            </tr>
          </tbody>
        </table>

        <div v-if="leiterListenAnsicht === 'detail' && leiterBestaetigt.length" class="detail-scroll">
          <table class="liste leiter-detail-tabelle">
            <thead>
              <tr>
                <th>Name</th><th>E-Mail</th><th>Telefon</th><th>Geburtsdatum</th><th>Geschlecht</th>
                <th>AHV</th><th>Anwesend</th><th>Status</th><th>Essen</th><th>Ämtli</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="l in leiterBestaetigt" :key="l.id">
                <td>{{ l.vorname }} {{ l.nachname }}</td>
                <td>{{ l.email ?? '–' }}</td>
                <td>{{ l.telefon ?? '–' }}</td>
                <td>{{ l.geburtsdatum ?? '–' }}</td>
                <td>{{ l.geschlecht ?? '–' }}</td>
                <td>{{ l.ahv_nr ?? '–' }}</td>
                <td>{{ l.anwesend_von ?? '–' }} – {{ l.anwesend_bis ?? '–' }}</td>
                <td>{{ l.anmeldung_art === 'provisorisch' ? 'provisorisch' : 'fix' }}</td>
                <td>{{ l.essensgewohnheiten?.trim() || '–' }}</td>
                <td>{{ (leiterRollenMap[l.id] ?? []).map((r) => r.name).join(', ') || '–' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else-if="leiterListenAnsicht !== 'verwaltung' && !leiterBestaetigt.length" class="hint">Noch keine bestätigten Leiter.</p>

        <template v-if="leiterListenAnsicht === 'verwaltung'">
        <h3>Leiter &amp; Team</h3>
        <p class="hint">
          Stammdaten, Ämtli und App-Berechtigungen in einer Tabelle. Lagerleitung (Lalei) steuert das Lager –
          mindestens eine Person muss Lalei bleiben.
        </p>

        <table v-if="leiterZeilen.length" class="liste leiter-team-tabelle">
          <thead>
            <tr>
              <th>Name</th>
              <th>E-Mail</th>
              <th>Login</th>
              <th>Alter</th>
              <th>Gruppe</th>
              <th>Anwesend</th>
              <th>Anmeldung</th>
              <th>App-Rolle</th>
              <th>Zugang</th>
              <th>Ämtli</th>
              <th>Aktionen</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="z in leiterZeilen" :key="z.leiter.id">
              <tr :class="{ 'zeile-bearbeiten': leiterBearbeitenId === z.leiter.id }">
                <td>
                  <template v-if="leiterBearbeitenId === z.leiter.id">
                    <div class="inline-edit-gruppe">
                      <input v-model="leiterEditForm.vorname" class="inline-inp" placeholder="Vorname" required />
                      <input v-model="leiterEditForm.nachname" class="inline-inp" placeholder="Nachname" required />
                    </div>
                  </template>
                  <template v-else>
                    {{ z.leiter.vorname }} {{ z.leiter.nachname }}
                    <span v-if="z.leiter.von_vorjahr" class="badge prov">VJ</span>
                  </template>
                </td>
                <td>
                  <template v-if="leiterBearbeitenId === z.leiter.id">
                    <input v-model="leiterEditForm.telefon" class="inline-inp breit" placeholder="Telefon" />
                  </template>
                  <template v-else>
                    {{ z.team?.profiles?.email ?? z.leiter.email ?? '–' }}
                  </template>
                </td>
                <td>
                  <span v-if="z.leiter.profile_id" class="hint">✓</span>
                  <span v-else class="login-offen">ohne Login</span>
                </td>
                <td>
                  <template v-if="leiterBearbeitenId === z.leiter.id">
                    <input v-model="leiterEditForm.geburtsdatum" type="date" class="inline-inp" />
                  </template>
                  <template v-else>
                    {{ berechneAlter(z.leiter.geburtsdatum) ?? '–' }}
                  </template>
                </td>
                <td>
                  <span v-if="!z.nurTeam && gruppeTagLeiter[z.leiter.id]" class="gruppen-tag">{{ gruppeTagLeiter[z.leiter.id] }}</span>
                  <span v-else>–</span>
                </td>
                <td>
                  <template v-if="leiterBearbeitenId === z.leiter.id">
                    <div class="inline-edit-gruppe">
                      <input v-model="leiterEditForm.anwesend_von" type="date" class="inline-inp" title="Anwesend von" />
                      <span class="hint">–</span>
                      <input v-model="leiterEditForm.anwesend_bis" type="date" class="inline-inp" title="Anwesend bis" />
                    </div>
                  </template>
                  <template v-else>
                    {{ z.leiter.anwesend_von ?? '–' }} – {{ z.leiter.anwesend_bis ?? '–' }}
                  </template>
                </td>
                <td>
                  <span v-if="z.nurTeam" class="hint">nur App</span>
                  <span v-else>{{ z.leiter.anmeldung_art === 'provisorisch' ? 'provisorisch' : 'fix' }}</span>
                </td>
                <td>
                  <select
                    v-if="isLeitung && z.team"
                    :value="z.team.rolle"
                    @change="teamRolleAendern(z.team!.id, ($event.target as HTMLSelectElement).value)"
                  >
                    <option value="leiter">Leiter</option>
                    <option value="lagerleitung">Lagerleitung (Lalei)</option>
                  </select>
                  <span v-else-if="z.team">{{ z.team.rolle === 'lagerleitung' ? 'Lagerleitung' : 'Leiter' }}</span>
                  <span v-else class="hint">–</span>
                </td>
                <td>{{ z.team?.status ?? '–' }}</td>
                <td class="aemtli-zelle">
                  <template v-if="!z.nurTeam">
                    <div class="rollen-zeile">
                      <span v-for="r in leiterRollenMap[z.leiter.id] ?? []" :key="r.zuweisungId" class="rollen-pill">
                        {{ r.name }}
                        <button
                          v-if="isLeitung"
                          type="button"
                          class="rollen-entfernen"
                          title="Rolle entfernen"
                          @click="rolleEntfernen(r.zuweisungId)"
                        >×</button>
                      </span>
                      <span v-if="!(leiterRollenMap[z.leiter.id] ?? []).length" class="hint rollen-leer">–</span>
                    </div>
                    <div v-if="isLeitung" class="rollen-zuweisen">
                      <select
                        v-if="zuweisbareAemtli(z.leiter.id).length"
                        @change="rolleZuweisen(z.leiter.id, ($event.target as HTMLSelectElement).value); ($event.target as HTMLSelectElement).value = ''"
                      >
                        <option value="">+ Ämtli</option>
                        <option v-for="a in zuweisbareAemtli(z.leiter.id)" :key="a.id" :value="a.id">{{ a.name }}</option>
                      </select>
                      <input
                        v-model="neueRolleName[z.leiter.id]"
                        placeholder="neues Ämtli..."
                        class="neue-rolle-input"
                        @keyup.enter="neueRolleErstellen(z.leiter.id)"
                      />
                    </div>
                  </template>
                  <span v-else class="hint">–</span>
                </td>
                <td>
                  <div class="inline-aktionen">
                    <template v-if="leiterBearbeitenId === z.leiter.id">
                      <button type="button" class="klein" @click="leiterBearbeitenSpeichern">Speichern</button>
                      <button type="button" class="secondary klein" @click="leiterBearbeitenAbbrechen">Abbrechen</button>
                    </template>
                    <template v-else-if="isLeitung || darfLeiterBearbeiten(z.leiter)">
                      <button
                        v-if="!z.nurTeam && darfLeiterBearbeiten(z.leiter)"
                        type="button"
                        class="secondary klein"
                        @click="leiterBearbeitenStart(z.leiter)"
                      >
                        Bearbeiten
                      </button>
                      <button
                        v-if="isLeitung && !z.nurTeam"
                        type="button"
                        class="secondary klein"
                        @click="leiterLoeschen(z.leiter)"
                      >
                        Entfernen
                      </button>
                      <button
                        v-if="isLeitung && z.team && z.team.profile_id !== session?.user.id"
                        type="button"
                        class="secondary klein"
                        @click="teamEntfernen(z.team!.id)"
                      >
                        App entfernen
                      </button>
                    </template>
                    <span v-else class="hint">–</span>
                  </div>
                </td>
              </tr>
              <tr v-if="leiterBearbeitenId === z.leiter.id" class="zeile-bearbeiten-extra">
                <td colspan="11">
                  <div class="inline-edit-extra">
                    <label>
                      Geschlecht
                      <select v-model="leiterEditForm.geschlecht">
                        <option value="">–</option>
                        <option value="m">m</option>
                        <option value="w">w</option>
                        <option value="d">d</option>
                      </select>
                    </label>
                    <label>
                      AHV
                      <input v-model="leiterEditForm.ahv_nr" placeholder="756.xxxx.xxxx.xx" />
                    </label>
                    <span class="hint">Stammdaten werden ins Profil übernommen und gelten vereinweit.</span>
                  </div>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
        <p v-else class="hint">Noch keine Leiter.</p>

        <h3>Leiter hinzufügen (aus Verein)</h3>
        <p class="hint">
          Alle bestätigten Vereinsmitglieder (mit und ohne Login) sowie manuelle Einträge aus dem
          <router-link :to="`/organisation?org=${lager.organisation_id ?? ''}`">Verein</router-link>.
        </p>
        <form @submit.prevent="leiterHinzufuegen" class="inline-form">
          <select v-model="orgPersonAuswahl" required>
            <option value="">Person aus Verein wählen</option>
            <option
              v-for="p in verfuegbareOrgPersonen"
              :key="p.id"
              :value="p.id"
            >
              {{ p.vorname }} {{ p.nachname }}{{ p.email ? ` (${p.email})` : '' }}{{ p.profile_id ? '' : ' · ohne Login' }}
            </option>
          </select>
          <button type="submit" :disabled="leiterSpeichern">{{ leiterSpeichern ? 'Speichere...' : 'Hinzufügen' }}</button>
        </form>
        <p v-if="leiterFehler" class="error">{{ leiterFehler }}</p>
        </template>
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
          :kann-melden="istBestaetigterLeiter || isLeitung"
          :bloecke="bloecke.map((b) => ({ id: b.id, titel: b.titel, code: b.code }))"
        />
      </section>

      <!-- Dynamische Ämtli-Tabs -->
      <section v-for="a in meineAemtli" :key="a.id" v-show="activeTab === tabIdForAemtli(a.name)">
        <AemtliKueche
          v-if="aemtliKomponente(a.name) === 'kueche' && session"
          :lager-id="lagerId" :aemtli-id="a.id" :lager-name="lager.name"
          :user-id="session.user.id" :start-datum="lager.start_datum" :end-datum="lager.end_datum"
          :kann-einkauf-melden="istBestaetigterLeiter || isLeitung"
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
        <AemtliMotto v-else-if="aemtliKomponente(a.name) === 'motto'" :lager-id="lagerId" :aemtli-id="a.id" :aemtli-name="a.name" />
        <AemtliMaterial v-else-if="aemtliKomponente(a.name) === 'material'" :lager-id="lagerId" :aemtli-id="a.id" :aemtli-name="a.name" />
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

      <!-- Statistik -->
      <section v-if="activeTab === 'statistik' && isLeitung">
        <StatistikPanel :lager-id="lagerId" />
      </section>

      <!-- Gemini (nur Lagerleitung) -->
      <section v-if="activeTab === 'gemini'">
        <LagerGeminiPanel
          v-if="isLeitung"
          :lager-id="lagerId"
          :organisation-id="lager.organisation_id"
          :lager-name="lager.name"
          :lager-jahr="lager.jahr"
          :lager-status="lager.status"
          :start-datum="lager.start_datum"
          :end-datum="lager.end_datum"
          :ort="lager.ort"
          @applied="geminiVorschlagAngewendet"
        />
        <p v-else class="error">Nur Lagerleitung hat Zugriff auf Gemini.</p>
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
        <p class="hint">
          Aktuell: <strong>{{ lager.status }}</strong> –
          TN-Anmeldung aktivieren unter <button type="button" class="link-like" @click="zuPflichtTab('teilnehmer')">Teilnehmer</button>.
        </p>

        <h3>Willkommens-Link für TN</h3>
        <p class="hint">Teilnehmer/innen sehen nur diese Seite – kein Programm:</p>
        <code class="link-box">{{ willkommenLink }}</code>

        <h3>Kalender-Export (ICS)</h3>
        <div class="inline-form">
          <button class="secondary" @click="icsExport('ganzes')">Ganzes Programm (.ics)</button>
          <button class="secondary" @click="icsExport('eigen')">Nur Lagerzeitraum (.ics)</button>
        </div>

        <div v-if="isLeitung" class="danger-zone">
          <h3>Lager löschen</h3>
          <p class="hint">Nur Lagerleitung kann ein Lager endgültig löschen.</p>
          <button
            type="button"
            class="danger"
            :disabled="lagerLoeschen"
            @click="lagerLoeschenFn"
          >
            {{ lagerLoeschen ? 'Lösche...' : 'Lager löschen' }}
          </button>
          <p v-if="lagerLoeschenFehler" class="error">{{ lagerLoeschenFehler }}</p>
        </div>
      </section>

      </template>
    </template>
    </main>
  </div>
</template>

<style scoped>
.leiter-ansicht-nav { display: flex; flex-wrap: wrap; gap: 0.4rem; align-items: center; margin: 0.75rem 0 1rem; }
.leiter-ansicht-nav button { background: var(--color-surface); border: 1px solid var(--color-border); font-size: 0.85rem; color: var(--color-text); }
.leiter-ansicht-nav button.aktiv { background: var(--color-accent); color: #fdfbf3; border-color: var(--color-accent); }
.detail-scroll { overflow-x: auto; margin-bottom: 1rem; }
.leiter-detail-tabelle { font-size: 0.8rem; min-width: 900px; }
.anmeldung-aktivierung { margin: 0 0 1rem; padding: 0.75rem; border: 1px solid var(--color-border); border-radius: var(--radius-md); }
.anmeldung-aktivierung label { display: flex; flex-direction: column; gap: 0.3rem; font-size: 0.85rem; color: var(--color-text-muted); }
.leiter-team-tabelle { font-size: 0.82rem; }
.leiter-team-tabelle th, .leiter-team-tabelle td { padding: 0.4rem 0.5rem; vertical-align: top; }
.zeile-bearbeiten { background: var(--color-surface-muted); }
.zeile-bearbeiten-extra td { padding-top: 0; border-bottom: 1px solid var(--color-border); }
.inline-edit-gruppe { display: flex; flex-wrap: wrap; align-items: center; gap: 0.3rem; }
.inline-inp { font-size: 0.82rem; padding: 0.2rem 0.35rem; max-width: 7.5rem; }
.inline-inp.breit { max-width: 10rem; }
.inline-edit-extra { display: flex; flex-wrap: wrap; align-items: flex-end; gap: 0.65rem 1rem; padding: 0.25rem 0 0.5rem; }
.inline-edit-extra label { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.75rem; color: var(--color-text-muted); }
.inline-aktionen { display: flex; flex-wrap: wrap; gap: 0.3rem; }
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
.link-like { border: none; background: transparent; color: var(--color-accent); padding: 0; cursor: pointer; text-decoration: underline; }
.status-fehlend { margin: 0.5rem 0 0; padding-left: 1.2rem; font-size: 0.88rem; }
.danger-zone {
  margin-top: 1.5rem;
  padding: 1rem;
  border: 1px solid color-mix(in oklab, var(--color-danger) 45%, transparent);
  border-radius: var(--radius-md);
  background: color-mix(in oklab, var(--color-danger) 7%, var(--color-surface));
}
.danger {
  background: var(--color-danger);
  color: #fff;
  border-color: transparent;
}
.anfragen-box { margin-bottom: 1.25rem; padding: 1rem; background: var(--color-surface-muted); border-radius: var(--radius-md); }
.anfrage-karte { padding: 0.6rem 0; border-bottom: 1px solid var(--color-border); }
.anfrage-karte:last-child { border-bottom: none; }
.badge.prov { display: inline-block; margin-left: 0.35rem; padding: 0.05rem 0.4rem; border-radius: var(--radius-pill); font-size: 0.7rem; background: #c98a3f; color: #fff; }
.lager-form { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 0.75rem; margin-bottom: 1.5rem; }
.lager-form label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.85rem; color: var(--color-text-muted); }
</style>
