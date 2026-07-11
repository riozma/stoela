<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
import { useGooglePlaces } from '../composables/useGooglePlaces'
import AppHeader from '../components/AppHeader.vue'
import LagerFahrplan from '../components/lager/LagerFahrplan.vue'
import { ECAMP_URL } from '../lib/constants'
import { downloadIcs } from '../lib/ics'
import { orgKalenderHttpsUrl, orgKalenderWebcalUrl } from '../lib/orgKalender'
import {
  leerRessourceForm,
  RESSOURCE_TYP_LABELS,
  SICHTBARKEIT_LABELS,
  type OrgRessource,
  type OrgRessourceForm,
  type OrgRessourceTyp,
} from '../lib/orgRessourcen'

interface VereinMitgliedschaft {
  organisation_id: string
  slug: string
  name: string
  homepage: string | null
  meine_rolle: 'mitglied' | 'leitung' | 'admin'
  mein_status: 'angefragt' | 'mitglied' | 'abgelehnt'
}

interface VereinsMitglied {
  organisation_id: string
  profile_id: string
  rolle: 'mitglied' | 'leitung' | 'admin'
  status: 'angefragt' | 'mitglied' | 'abgelehnt'
  angefragt_am: string
  vorname?: string | null
  nachname?: string | null
  email?: string | null
  profiles?:
    | { vorname: string | null; nachname: string | null; email: string | null }
    | { vorname: string | null; nachname: string | null; email: string | null }[]
    | null
}

interface VereinsLeiterZeile {
  key: string
  typ: 'login' | 'manuell'
  vorname: string
  nachname: string
  email: string | null
  telefon: string | null
  rolle: string
  profile_id: string | null
  org_person_id: string | null
  verknuepft: boolean
}

interface VereinsPerson {
  id: string
  vorname: string
  nachname: string
  email: string | null
  telefon: string | null
  rolle_hinweis: string | null
  profile_id: string | null
}

interface VereinsLager {
  id: string
  jahr: number
  name: string
  ort: string | null
  start_datum: string | null
  end_datum: string | null
  status: string
  can_edit: boolean
}

interface OrgTodoVorlage {
  id: string
  titel: string
  ebene: string
  monate_vor_lager: number | null
  kategorie: string
}

const route = useRoute()
const router = useRouter()
const { session } = useAuth()
const { attachAutocomplete } = useGooglePlaces()

const laden = ref(true)
const fehler = ref('')
const info = ref('')

const vereine = ref<VereinMitgliedschaft[]>([])
const orgAuswahl = ref('')

const mitglieder = ref<VereinsMitglied[]>([])
const orgPersonen = ref<VereinsPerson[]>([])
const orgVorlagen = ref<OrgTodoVorlage[]>([])
const lager = ref<VereinsLager[]>([])
const vorLagerListe = ref<{ id: string; name: string; jahr: number }[]>([])

const personForm = ref({ vorname: '', nachname: '', email: '', telefon: '', rolle_hinweis: '' })
const personSpeichern = ref(false)
const personEdit = ref<Record<string, { vorname: string; nachname: string; email: string; telefon: string; rolle_hinweis: string }>>({})
const mitgliedEdit = ref<Record<string, { vorname: string; nachname: string; rolle: 'mitglied' | 'leitung' | 'admin' }>>({})
const personAktionLade = ref<Record<string, boolean>>({})
const mitgliedAktionLade = ref<Record<string, boolean>>({})
const verknuepfOrgPerson = ref<Record<string, string>>({})
const anfrageAktionLade = ref<Record<string, boolean>>({})

const lagerForm = ref({
  jahr: new Date().getFullYear() + 1,
  name: `Stöckli-Lager ${new Date().getFullYear() + 1}`,
  ort: '',
  ort_lat: null as number | null,
  ort_lng: null as number | null,
  ort_place_id: null as string | null,
  start_datum: '',
  end_datum: '',
  vor_lager_id: '',
})
const lagerPersonenPool = ref<{ id: string; profile_id: string | null; vorname: string; nachname: string; email: string | null }[]>([])
const lagerSpeichern = ref(false)
const laleiModalOffen = ref(false)
const laleiModal = ref({ modus: 'selbst' as 'selbst' | 'verein', personId: '' })

const orgRessourcen = ref<OrgRessource[]>([])
const orgKalenderToken = ref('')
const orgKalenderTitel = ref('')
const kalenderLinkKopiert = ref<'https' | 'webcal' | null>(null)
let kalenderKopiertTimer: ReturnType<typeof setTimeout> | null = null
const orgLinks = computed(() => orgRessourcen.value.filter((r) => r.typ === 'link'))
const orgLogindaten = computed(() => orgRessourcen.value.filter((r) => r.typ === 'zugang'))
const orgKalenderBereit = computed(() => Boolean(orgAuswahl.value && orgKalenderToken.value))
const orgKalenderHttps = computed(() =>
  orgKalenderBereit.value ? orgKalenderHttpsUrl(orgAuswahl.value, orgKalenderToken.value) : '',
)
const orgKalenderWebcal = computed(() =>
  orgKalenderBereit.value ? orgKalenderWebcalUrl(orgAuswahl.value, orgKalenderToken.value) : '',
)
const ressourceForm = ref<OrgRessourceForm>(leerRessourceForm())
const ressourceBearbeiten = ref(false)
const ressourceSpeichern = ref(false)
const sichtbarePasswoerter = ref<Record<string, boolean>>({})

const ortInput = ref<HTMLInputElement | null>(null)

const aktiveVereine = computed(() => vereine.value.filter((v) => v.mein_status === 'mitglied'))
const aktuellerVerein = computed(() => aktiveVereine.value.find((v) => v.organisation_id === orgAuswahl.value) ?? null)
const istVereinsleitung = computed(() =>
  !!aktuellerVerein.value && ['leitung', 'admin'].includes(aktuellerVerein.value.meine_rolle),
)
const istOrgAdmin = computed(() => aktuellerVerein.value?.meine_rolle === 'admin')

const anfragen = computed(() => mitglieder.value.filter((m) => m.status === 'angefragt'))
const mitgliederAktiv = computed(() => mitglieder.value.filter((m) => m.status === 'mitglied'))
const kommendeOderLaufendeLager = computed(() => {
  const heute = new Date().toISOString().slice(0, 10)
  return lager.value.filter((l) => !l.end_datum || l.end_datum >= heute).sort((a, b) => (a.start_datum ?? '').localeCompare(b.start_datum ?? ''))
})
const vergangeneLager = computed(() => {
  const heute = new Date().toISOString().slice(0, 10)
  return lager.value.filter((l) => !!l.end_datum && l.end_datum < heute).sort((a, b) => (b.start_datum ?? '').localeCompare(a.start_datum ?? ''))
})

/** Für den Jahresfahrplan-Tab: nächstes/laufendes Lager, sonst das zuletzt vergangene. */
const relevantesLager = computed(() => kommendeOderLaufendeLager.value[0] ?? vergangeneLager.value[0] ?? null)

type VereinBereich = 'lager' | 'team' | 'fahrplan' | 'ressourcen'
const aktivBereich = ref<VereinBereich>('lager')

function profilVon(m: VereinsMitglied) {
  if (m.vorname !== undefined || m.nachname !== undefined || m.email !== undefined) {
    return {
      vorname: m.vorname ?? null,
      nachname: m.nachname ?? null,
      email: m.email ?? null,
    }
  }
  if (!m.profiles) return null
  if (Array.isArray(m.profiles)) return m.profiles[0] ?? null
  return m.profiles
}

function zeilenName(vorname: string, nachname: string, email: string | null) {
  const name = `${vorname} ${nachname}`.trim()
  return name || email || 'Name nicht hinterlegt'
}

function profilName(m: VereinsMitglied): string {
  const p = profilVon(m)
  const name = `${p?.vorname ?? ''} ${p?.nachname ?? ''}`.trim()
  return name || p?.email || 'Unbekannt'
}

function profilEmail(m: VereinsMitglied): string {
  return profilVon(m)?.email ?? '–'
}

function rollenLabel(rolle: string): string {
  if (rolle === 'mitglied') return 'Mitglied'
  if (rolle === 'leitung') return 'Leitung'
  if (rolle === 'admin') return 'Admin'
  return rolle
}

const vereinsLeiterListe = computed((): VereinsLeiterZeile[] => {
  const zeilen: VereinsLeiterZeile[] = []
  const personByProfile = new Map(
    orgPersonen.value
      .filter((p) => p.profile_id)
      .map((p) => [p.profile_id!, p]),
  )
  const loginProfileIds = new Set(mitgliederAktiv.value.map((m) => m.profile_id))

  for (const m of mitgliederAktiv.value) {
    const p = profilVon(m)
    const verknuepftePerson = personByProfile.get(m.profile_id)
    zeilen.push({
      key: `login-${m.profile_id}`,
      typ: 'login',
      vorname: p?.vorname ?? '',
      nachname: p?.nachname ?? '',
      email: p?.email ?? null,
      telefon: verknuepftePerson?.telefon ?? null,
      rolle: m.rolle,
      profile_id: m.profile_id,
      org_person_id: verknuepftePerson?.id ?? null,
      verknuepft: true,
    })
  }

  for (const person of orgPersonen.value) {
    if (person.profile_id && loginProfileIds.has(person.profile_id)) continue
    zeilen.push({
      key: `person-${person.id}`,
      typ: person.profile_id ? 'login' : 'manuell',
      vorname: person.vorname,
      nachname: person.nachname,
      email: person.email,
      telefon: person.telefon,
      rolle: person.rolle_hinweis ?? 'Leiter',
      profile_id: person.profile_id,
      org_person_id: person.id,
      verknuepft: !!person.profile_id,
    })
  }

  return zeilen.sort((a, b) =>
    `${a.nachname} ${a.vorname}`.localeCompare(`${b.nachname} ${b.vorname}`, 'de'),
  )
})

const manuelleLeiterOhneLogin = computed(() =>
  orgPersonen.value.filter((p) => !p.profile_id),
)

async function ladeVereine() {
  const { data, error } = await supabase.rpc('list_meine_vereine')
  if (error) {
    fehler.value = error.message
    return
  }
  vereine.value = (data ?? []) as VereinMitgliedschaft[]

  if (!orgAuswahl.value) {
    const ausQuery = typeof route.query.org === 'string' ? route.query.org : ''
    const byId = aktiveVereine.value.find((v) => v.organisation_id === ausQuery)
    const bySlug = aktiveVereine.value.find((v) => v.slug === ausQuery)
    orgAuswahl.value = byId?.organisation_id ?? bySlug?.organisation_id ?? aktiveVereine.value[0]?.organisation_id ?? ''
  }
}

async function ladeVereinDaten() {
  if (!orgAuswahl.value) return
  const orgId = orgAuswahl.value

  const [{ data: m }, { data: p }, { data: v }, { data: l }, { data: vor }, { data: org }] = await Promise.all([
    supabase.rpc('list_verein_mitglieder_mit_profil', { p_organisation_id: orgId }),
    supabase
      .from('org_personen')
      .select('id, vorname, nachname, email, telefon, rolle_hinweis, profile_id')
      .eq('organisation_id', orgId)
      .eq('aktiv', true)
      .order('nachname'),
    supabase
      .from('org_todo_vorlagen')
      .select('id, titel, ebene, monate_vor_lager, kategorie')
      .eq('organisation_id', orgId)
      .eq('aktiv', true)
      .order('sortierung'),
    supabase.rpc('list_vereinslager', { p_organisation_id: orgId }),
    supabase
      .from('lager')
      .select('id, name, jahr')
      .eq('organisation_id', orgId)
      .order('jahr', { ascending: false }),
    supabase.from('organisation').select('name, kalender_token').eq('id', orgId).single(),
  ])

  orgKalenderToken.value = org?.kalender_token ?? ''
  orgKalenderTitel.value = org?.name ?? aktuellerVerein.value?.name ?? 'Vereinskalender'

  mitglieder.value = ((m ?? []) as Omit<VereinsMitglied, 'organisation_id'>[]).map((row) => ({
    ...row,
    organisation_id: orgId,
  }))
  orgPersonen.value = (p ?? []) as VereinsPerson[]
  personEdit.value = {}
  mitgliedEdit.value = {}
  for (const person of orgPersonen.value) {
    personEdit.value[person.id] = {
      vorname: person.vorname,
      nachname: person.nachname,
      email: person.email ?? '',
      telefon: person.telefon ?? '',
      rolle_hinweis: person.rolle_hinweis ?? '',
    }
  }
  for (const mitglied of mitglieder.value.filter((e) => e.status === 'mitglied')) {
    const profil = profilVon(mitglied)
    mitgliedEdit.value[mitglied.profile_id] = {
      vorname: profil?.vorname ?? '',
      nachname: profil?.nachname ?? '',
      rolle: mitglied.rolle,
    }
  }
  orgVorlagen.value = (v ?? []) as OrgTodoVorlage[]
  lager.value = (l ?? []) as VereinsLager[]
  vorLagerListe.value = (vor ?? []) as { id: string; name: string; jahr: number }[]

  await ladeLagerPersonenPool()
  await ladeOrgRessourcen()
}

async function ladeOrgRessourcen() {
  if (!orgAuswahl.value) {
    orgRessourcen.value = []
    return
  }
  const { data, error } = await supabase.rpc('list_org_ressourcen', { p_organisation_id: orgAuswahl.value })
  if (error) {
    fehler.value = error.message
    orgRessourcen.value = []
    return
  }
  orgRessourcen.value = (data ?? []) as OrgRessource[]
}

function ressourceNeu(typ: OrgRessourceTyp = 'link') {
  ressourceForm.value = { ...leerRessourceForm(), typ, sortierung: orgRessourcen.value.length }
  ressourceBearbeiten.value = true
}

function ressourceEditStart(r: OrgRessource) {
  ressourceForm.value = {
    id: r.id,
    typ: r.typ,
    titel: r.titel,
    url: r.url ?? '',
    benutzername: r.benutzername ?? '',
    passwort: '',
    notiz: r.notiz ?? '',
    sichtbarkeit: r.sichtbarkeit,
    sortierung: r.sortierung,
    zugewiesene_profile_ids: [...r.zugewiesene_profile_ids],
  }
  ressourceBearbeiten.value = true
}

function ressourceAbbrechen() {
  ressourceBearbeiten.value = false
  ressourceForm.value = leerRessourceForm()
}

async function ressourceSpeichernHandler() {
  if (!orgAuswahl.value || !istOrgAdmin.value) return
  ressourceSpeichern.value = true
  fehler.value = ''
  info.value = ''
  const f = ressourceForm.value
  const { error } = await supabase.rpc('org_ressource_speichern', {
    p_organisation_id: orgAuswahl.value,
    p_id: f.id,
    p_typ: f.typ,
    p_titel: f.titel,
    p_url: f.url || null,
    p_benutzername: f.typ === 'zugang' ? f.benutzername : null,
    p_passwort: f.typ === 'zugang' && f.passwort.trim() ? f.passwort : null,
    p_notiz: f.notiz || null,
    p_sichtbarkeit: f.sichtbarkeit,
    p_sortierung: f.sortierung,
    p_zugewiesene_profile_ids: f.sichtbarkeit === 'ausgewaehlt' ? f.zugewiesene_profile_ids : [],
  })
  ressourceSpeichern.value = false
  if (error) {
    fehler.value = error.message
    return
  }
  info.value = f.id ? 'Eintrag aktualisiert.' : 'Eintrag hinzugefügt.'
  ressourceAbbrechen()
  await ladeOrgRessourcen()
}

async function ressourceLoeschen(id: string) {
  if (!orgAuswahl.value || !istOrgAdmin.value) return
  if (!window.confirm('Eintrag wirklich löschen?')) return
  const { error } = await supabase.rpc('org_ressource_loeschen', {
    p_organisation_id: orgAuswahl.value,
    p_id: id,
  })
  if (error) {
    fehler.value = error.message
    return
  }
  info.value = 'Eintrag gelöscht.'
  await ladeOrgRessourcen()
}

function togglePasswortSichtbar(id: string) {
  sichtbarePasswoerter.value[id] = !sichtbarePasswoerter.value[id]
}

async function kalenderLinkKopieren(typ: 'https' | 'webcal') {
  const text = typ === 'https' ? orgKalenderHttps.value : orgKalenderWebcal.value
  if (!text) return
  try {
    await navigator.clipboard.writeText(text)
    kalenderLinkKopiert.value = typ
    if (kalenderKopiertTimer) clearTimeout(kalenderKopiertTimer)
    kalenderKopiertTimer = setTimeout(() => { kalenderLinkKopiert.value = null }, 2500)
  } catch {
    fehler.value = 'Link konnte nicht kopiert werden.'
  }
}

async function orgKalenderIcsDownload() {
  if (!orgAuswahl.value) return
  const { data, error } = await supabase.rpc('get_org_kalender_ics', { p_organisation_id: orgAuswahl.value })
  if (error || !data) {
    fehler.value = error?.message ?? 'ICS konnte nicht erzeugt werden.'
    return
  }
  downloadIcs(`${orgKalenderTitel.value.replace(/\s+/g, '_')}_kalender.ics`, data as string)
}

function toggleRessourceMitglied(profileId: string) {
  const ids = ressourceForm.value.zugewiesene_profile_ids
  const idx = ids.indexOf(profileId)
  if (idx >= 0) ids.splice(idx, 1)
  else ids.push(profileId)
}

async function ladeLagerPersonenPool() {
  if (!orgAuswahl.value) {
    lagerPersonenPool.value = []
    return
  }
  const orgId = orgAuswahl.value
  const { data } = await supabase.rpc('list_verein_personen_fuer_lager', { p_organisation_id: orgId })
  if (data?.length) {
    lagerPersonenPool.value = data as typeof lagerPersonenPool.value
    return
  }
  const { data: mitgliederData } = await supabase.rpc('list_verein_mitglieder_mit_profil', { p_organisation_id: orgId })
  lagerPersonenPool.value = (mitgliederData ?? []).map((m: { profile_id: string; vorname: string; nachname: string; email: string }) => ({
    id: `login-${m.profile_id}`,
    profile_id: m.profile_id,
    vorname: m.vorname ?? '',
    nachname: m.nachname ?? '',
    email: m.email ?? null,
  }))
}

async function datenLaden() {
  laden.value = true
  fehler.value = ''
  await ladeVereine()
  await ladeVereinDaten()
  laden.value = false
}

async function personHinzufuegen() {
  if (!orgAuswahl.value || !istVereinsleitung.value) return
  personSpeichern.value = true
  info.value = ''
  fehler.value = ''
  const { error } = await supabase.from('org_personen').insert({
    organisation_id: orgAuswahl.value,
    vorname: personForm.value.vorname.trim(),
    nachname: personForm.value.nachname.trim(),
    email: personForm.value.email || null,
    telefon: personForm.value.telefon || null,
    rolle_hinweis: personForm.value.rolle_hinweis || null,
  })
  personSpeichern.value = false
  if (error) {
    fehler.value = error.message
    return
  }
  personForm.value = { vorname: '', nachname: '', email: '', telefon: '', rolle_hinweis: '' }
  info.value = 'Person hinzugefügt.'
  await ladeVereinDaten()
}

async function mitgliedAktualisieren(profileId: string) {
  if (!orgAuswahl.value || !istOrgAdmin.value) return
  const edit = mitgliedEdit.value[profileId]
  if (!edit) return
  const vorname = edit.vorname.trim()
  const nachname = edit.nachname.trim()
  if (!vorname || !nachname) {
    fehler.value = 'Vorname und Nachname sind Pflicht.'
    return
  }
  info.value = ''
  fehler.value = ''
  mitgliedAktionLade.value[profileId] = true
  const { error } = await supabase.rpc('verein_leiter_bearbeiten', {
    p_organisation_id: orgAuswahl.value,
    p_profile_id: profileId,
    p_vorname: vorname,
    p_nachname: nachname,
    p_rolle: edit.rolle,
  })
  mitgliedAktionLade.value[profileId] = false
  if (error) {
    fehler.value = error.message
    return
  }
  info.value = 'Leiter aktualisiert.'
  await ladeVereinDaten()
}

async function mitgliedEntfernen(profileId: string, name: string) {
  if (!orgAuswahl.value || !istOrgAdmin.value) return
  const sicher = window.confirm(`«${name}» wirklich aus dem Verein entfernen?`)
  if (!sicher) return
  info.value = ''
  fehler.value = ''
  mitgliedAktionLade.value[profileId] = true
  const { error } = await supabase.rpc('verein_leiter_entfernen', {
    p_organisation_id: orgAuswahl.value,
    p_profile_id: profileId,
  })
  mitgliedAktionLade.value[profileId] = false
  if (error) {
    fehler.value = error.message
    return
  }
  info.value = 'Leiter aus dem Verein entfernt.'
  await ladeVereinDaten()
}

async function personAktualisieren(personId: string) {
  if (!orgAuswahl.value || !istVereinsleitung.value) return
  const edit = personEdit.value[personId]
  if (!edit) return
  const vorname = edit.vorname.trim()
  const nachname = edit.nachname.trim()
  if (!vorname || !nachname) {
    fehler.value = 'Vorname und Nachname sind Pflicht.'
    return
  }
  info.value = ''
  fehler.value = ''
  personAktionLade.value[personId] = true
  const { error } = await supabase
    .from('org_personen')
    .update({
      vorname,
      nachname,
      email: edit.email.trim() || null,
      telefon: edit.telefon.trim() || null,
      rolle_hinweis: edit.rolle_hinweis.trim() || null,
    })
    .eq('id', personId)
    .eq('organisation_id', orgAuswahl.value)
  personAktionLade.value[personId] = false
  if (error) {
    fehler.value = error.message
    return
  }
  info.value = 'Person aktualisiert.'
  await ladeVereinDaten()
}

async function personLoeschen(personId: string) {
  if (!orgAuswahl.value || !istVereinsleitung.value) return
  const sicher = window.confirm('Person wirklich aus dem Personen-Pool löschen?')
  if (!sicher) return
  info.value = ''
  fehler.value = ''
  personAktionLade.value[personId] = true
  const { error } = await supabase
    .from('org_personen')
    .update({ aktiv: false })
    .eq('id', personId)
    .eq('organisation_id', orgAuswahl.value)
  personAktionLade.value[personId] = false
  if (error) {
    fehler.value = error.message
    return
  }
  info.value = 'Person gelöscht.'
  await ladeVereinDaten()
}

async function beitrittEntscheiden(
  profileId: string,
  entscheidung: 'genehmigen' | 'ablehnen',
  orgPersonId: string | null = null,
) {
  if (!orgAuswahl.value || !istVereinsleitung.value) return
  info.value = ''
  fehler.value = ''
  anfrageAktionLade.value[profileId] = true
  const { error } = await supabase.rpc('verein_beitrittsanfrage_entscheiden', {
    p_organisation_id: orgAuswahl.value,
    p_profile_id: profileId,
    p_entscheidung: entscheidung,
    p_org_person_id: orgPersonId,
  })
  anfrageAktionLade.value[profileId] = false
  if (error) {
    fehler.value = error.message
    return
  }
  verknuepfOrgPerson.value[profileId] = ''
  if (entscheidung === 'genehmigen') {
    info.value = orgPersonId ? 'Beitritt genehmigt – Name und Kontakt vom manuellen Eintrag übernommen.' : 'Neuer Leiter aufgenommen.'
  } else {
    info.value = 'Beitritt abgelehnt.'
  }
  await ladeVereinDaten()
}

async function beitrittAnnehmen(profileId: string) {
  await beitrittEntscheiden(profileId, 'genehmigen', null)
}

async function beitrittVerknuepfen(profileId: string) {
  const orgPersonId = verknuepfOrgPerson.value[profileId]
  if (!orgPersonId) {
    fehler.value = 'Bitte einen manuell erfassten Leiter zum Verknüpfen wählen.'
    return
  }
  await beitrittEntscheiden(profileId, 'genehmigen', orgPersonId)
}

async function beitrittAblehnen(profileId: string) {
  await beitrittEntscheiden(profileId, 'ablehnen', null)
}

function lagerFormularAbsenden() {
  if (!session.value || !orgAuswahl.value) return
  fehler.value = ''
  laleiModal.value = { modus: 'selbst', personId: '' }
  laleiModalOffen.value = true
}

function laleiModalAbbrechen() {
  laleiModalOffen.value = false
}

async function lagerErstellen() {
  if (!session.value || !orgAuswahl.value) return
  info.value = ''
  fehler.value = ''
  lagerSpeichern.value = true

  const { data: neuesLager, error: insertError } = await supabase
    .from('lager')
    .insert({
      jahr: lagerForm.value.jahr,
      name: lagerForm.value.name,
      ort: lagerForm.value.ort || null,
      ort_lat: lagerForm.value.ort_lat,
      ort_lng: lagerForm.value.ort_lng,
      ort_place_id: lagerForm.value.ort_place_id,
      start_datum: lagerForm.value.start_datum || null,
      end_datum: lagerForm.value.end_datum || null,
      status: 'planung',
      created_by: session.value.user.id,
      organisation_id: orgAuswahl.value,
      vor_lager_id: lagerForm.value.vor_lager_id || null,
    })
    .select('id')
    .single()

  if (insertError || !neuesLager) {
    lagerSpeichern.value = false
    fehler.value = insertError?.message ?? 'Lager konnte nicht erstellt werden.'
    return
  }

  if (laleiModal.value.modus === 'selbst') {
    const { error: laleiErr } = await supabase.rpc('lager_leiter_aus_verein_hinzufuegen', {
      p_lager_id: neuesLager.id,
      p_profile_id: session.value.user.id,
      p_org_person_id: null,
      p_als_lalei: true,
      p_anwesend_von: lagerForm.value.start_datum || null,
      p_anwesend_bis: lagerForm.value.end_datum || null,
    })
    if (laleiErr) {
      lagerSpeichern.value = false
      fehler.value = laleiErr.message
      return
    }
  } else {
    const person = lagerPersonenPool.value.find((p) => p.id === laleiModal.value.personId)
    if (!person) {
      lagerSpeichern.value = false
      fehler.value = 'Bitte eine Person als Lagerleitung (Lalei) wählen.'
      return
    }
    let pProfileId: string | null = person.profile_id
    let pOrgPersonId: string | null = null
    if (person.id.startsWith('login-')) pProfileId = person.id.slice(6)
    else if (person.id.startsWith('person-')) {
      pOrgPersonId = person.id.slice(7)
      if (!pProfileId) pProfileId = null
    }
    const { error: laleiErr } = await supabase.rpc('lager_leiter_aus_verein_hinzufuegen', {
      p_lager_id: neuesLager.id,
      p_profile_id: pProfileId,
      p_org_person_id: pOrgPersonId,
      p_als_lalei: true,
      p_anwesend_von: lagerForm.value.start_datum || null,
      p_anwesend_bis: lagerForm.value.end_datum || null,
    })
    if (laleiErr) {
      lagerSpeichern.value = false
      fehler.value = laleiErr.message
      return
    }
    if (session.value.user.id !== pProfileId) {
      await supabase.from('lager_leiter').insert({
        lager_id: neuesLager.id,
        profile_id: session.value.user.id,
        rolle: 'leiter',
        status: 'bestaetigt',
      })
    }
  }

  if (lagerForm.value.start_datum) {
    await supabase.rpc('lager_todos_generieren', { p_lager_id: neuesLager.id })
  }

  lagerSpeichern.value = false
  laleiModalOffen.value = false
  await ladeVereinDaten()
  await router.push(`/lager/${neuesLager.id}/dashboard`)
}

function lagerOeffnen(l: VereinsLager) {
  if (l.can_edit) {
    router.push(`/lager/${l.id}/dashboard`)
    return
  }
  router.push(`/lager/${l.id}/willkommen`)
}

function leiterAnmeldung(l: VereinsLager) {
  router.push(`/lager/${l.id}/anmelden-leiter`)
}

watch(orgAuswahl, async (id) => {
  if (!id) return
  await router.replace({ query: { ...route.query, org: id } })
  await ladeVereinDaten()
})

onMounted(async () => {
  await datenLaden()
  if (ortInput.value) {
    attachAutocomplete(ortInput.value, (gewaehlt) => {
      lagerForm.value.ort = gewaehlt.adresse
      lagerForm.value.ort_lat = gewaehlt.lat
      lagerForm.value.ort_lng = gewaehlt.lng
      lagerForm.value.ort_place_id = gewaehlt.placeId
    })
  }
})
</script>

<template>
  <div class="org-page">
    <div class="top-full">
      <AppHeader :show-alle-lager="true" />
    </div>

    <main>
      <header class="kopf">
        <h1>Organisation</h1>
        <p class="hint">Verein, Mitglieder und Lager sind hier zentral verwaltet.</p>
      </header>

      <section class="karte">
        <h2>Verein auswählen</h2>
        <select v-model="orgAuswahl">
          <option value="">– Verein wählen –</option>
          <option v-for="v in aktiveVereine" :key="v.organisation_id" :value="v.organisation_id">
            {{ v.name }} ({{ v.meine_rolle }})
          </option>
        </select>
        <p v-if="!aktiveVereine.length" class="hint">
          Du bist noch in keinem Verein Mitglied. Auf der <router-link to="/">Startseite</router-link> kannst du beitreten oder einen Verein erstellen.
        </p>
      </section>

      <template v-if="orgAuswahl">
        <section v-if="istVereinsleitung && anfragen.length" class="karte anfragen-box">
          <h2>Beitrittsanfragen</h2>
          <article v-for="a in anfragen" :key="a.profile_id" class="anfrage-karte">
            <div class="anfrage-kopf">
              <strong>{{ profilName(a) }}</strong>
              <span class="anfrage-mail">{{ profilEmail(a) }}</span>
            </div>
            <div class="inline-aktionen anfrage-aktionen">
              <button
                :disabled="anfrageAktionLade[a.profile_id]"
                @click="beitrittAnnehmen(a.profile_id)"
              >
                Neuer Leiter annehmen
              </button>
              <div class="verknuepf-zeile">
                <select v-model="verknuepfOrgPerson[a.profile_id]">
                  <option value="">Manuellen Leiter wählen…</option>
                  <option
                    v-for="p in manuelleLeiterOhneLogin"
                    :key="p.id"
                    :value="p.id"
                  >
                    {{ p.vorname }} {{ p.nachname }}{{ p.email ? ` (${p.email})` : '' }}
                  </option>
                </select>
                <button
                  class="secondary"
                  :disabled="anfrageAktionLade[a.profile_id] || !verknuepfOrgPerson[a.profile_id]"
                  @click="beitrittVerknuepfen(a.profile_id)"
                >
                  Leiter verknüpfen
                </button>
              </div>
              <button
                class="secondary"
                :disabled="anfrageAktionLade[a.profile_id]"
                @click="beitrittAblehnen(a.profile_id)"
              >
                Leiter ablehnen
              </button>
            </div>
          </article>
        </section>

        <nav class="verein-tabs">
          <button type="button" :class="{ aktiv: aktivBereich === 'lager' }" @click="aktivBereich = 'lager'">Lager</button>
          <button type="button" :class="{ aktiv: aktivBereich === 'team' }" @click="aktivBereich = 'team'">Team</button>
          <button type="button" :class="{ aktiv: aktivBereich === 'fahrplan' }" @click="aktivBereich = 'fahrplan'">Jahresfahrplan</button>
          <button type="button" :class="{ aktiv: aktivBereich === 'ressourcen' }" @click="aktivBereich = 'ressourcen'">Ressourcen</button>
        </nav>

        <section v-if="aktivBereich === 'lager'" class="karte">
          <h2>Lager im Verein</h2>
          <p class="hint">
            Kommende/laufende Lager: als Leiter beitreten oder als Gast ansehen.
            <a :href="ECAMP_URL" target="_blank" rel="noopener">eCamp öffnen ↗</a>
          </p>

          <div v-if="kommendeOderLaufendeLager.length" class="lager-grid">
            <article v-for="l in kommendeOderLaufendeLager" :key="l.id" class="lager-karte">
              <strong>{{ l.name }}</strong>
              <span class="meta">{{ l.jahr }} · {{ l.status }}</span>
              <span v-if="l.start_datum" class="meta">{{ l.start_datum }} – {{ l.end_datum ?? '?' }}</span>
              <div class="inline-aktionen">
                <button @click="lagerOeffnen(l)">{{ l.can_edit ? 'Öffnen' : 'Als Gast ansehen' }}</button>
                <button v-if="!l.can_edit" class="secondary" @click="leiterAnmeldung(l)">Als Leiter anmelden</button>
              </div>
            </article>
          </div>
          <p v-else class="hint">Keine kommenden/laufenden Lager.</p>

          <details v-if="vergangeneLager.length" class="vergangen">
            <summary>Vergangene Lager ({{ vergangeneLager.length }})</summary>
            <ul>
              <li v-for="l in vergangeneLager" :key="l.id">
                <button class="link-like" @click="lagerOeffnen(l)">{{ l.name }} ({{ l.jahr }})</button>
              </li>
            </ul>
          </details>
        </section>

        <section v-if="aktivBereich === 'ressourcen'" class="karte">
          <h2>Links &amp; Zugänge</h2>
          <p class="hint">
            Wichtige <strong>Links</strong> (z.&nbsp;B. Google Drive) und geteilte <strong>Logindaten</strong> (Seite, E-Mail/Benutzername, Passwort).
            Nur über diese Seite sichtbar – nicht in der öffentlichen TN-Anmeldung.
            {{ istOrgAdmin ? 'Als Admin kannst du Einträge verwalten und die Sichtbarkeit festlegen.' : 'Du siehst nur Einträge, für die du berechtigt bist.' }}
          </p>

          <div class="ressourcen-gruppe">
            <h3>Links</h3>
            <div v-if="orgLinks.length" class="ressourcen-liste">
              <article v-for="r in orgLinks" :key="r.id" class="ressource-karte">
                <div class="ressource-kopf">
                  <strong>{{ r.titel }}</strong>
                  <span class="klein">{{ SICHTBARKEIT_LABELS[r.sichtbarkeit] }}</span>
                </div>
                <a v-if="r.url" :href="r.url" target="_blank" rel="noopener noreferrer">{{ r.url }}</a>
                <p v-if="r.notiz" class="klein">{{ r.notiz }}</p>
                <div v-if="istOrgAdmin" class="inline-aktionen">
                  <button type="button" class="secondary klein-btn" @click="ressourceEditStart(r)">Bearbeiten</button>
                  <button type="button" class="secondary klein-btn" @click="ressourceLoeschen(r.id)">Löschen</button>
                </div>
              </article>
            </div>
            <p v-else class="hint">Noch keine Links hinterlegt.</p>
            <button v-if="istOrgAdmin && !ressourceBearbeiten" type="button" class="secondary klein-btn" @click="ressourceNeu('link')">+ Link hinzufügen</button>
          </div>

          <div class="ressourcen-gruppe">
            <h3>Logindaten</h3>
            <div v-if="orgLogindaten.length" class="ressourcen-liste">
              <article v-for="r in orgLogindaten" :key="r.id" class="ressource-karte">
                <div class="ressource-kopf">
                  <strong>{{ r.titel }}</strong>
                  <span class="klein">{{ SICHTBARKEIT_LABELS[r.sichtbarkeit] }}</span>
                </div>
                <p v-if="r.url" class="zugang-zeile">
                  <span>Seite:</span>
                  <a :href="r.url" target="_blank" rel="noopener noreferrer">{{ r.url }}</a>
                </p>
                <p v-if="r.benutzername" class="zugang-zeile"><span>E-Mail / Benutzer:</span> {{ r.benutzername }}</p>
                <p v-if="r.passwort" class="zugang-zeile">
                  <span>Passwort:</span>
                  <code>{{ sichtbarePasswoerter[r.id] ? r.passwort : '••••••••' }}</code>
                  <button type="button" class="klein-btn" @click="togglePasswortSichtbar(r.id)">
                    {{ sichtbarePasswoerter[r.id] ? 'Verbergen' : 'Anzeigen' }}
                  </button>
                </p>
                <p v-if="r.notiz" class="klein">{{ r.notiz }}</p>
                <div v-if="istOrgAdmin" class="inline-aktionen">
                  <button type="button" class="secondary klein-btn" @click="ressourceEditStart(r)">Bearbeiten</button>
                  <button type="button" class="secondary klein-btn" @click="ressourceLoeschen(r.id)">Löschen</button>
                </div>
              </article>
            </div>
            <p v-else class="hint">Noch keine Logindaten hinterlegt.</p>
            <button v-if="istOrgAdmin && !ressourceBearbeiten" type="button" class="secondary klein-btn" @click="ressourceNeu('zugang')">+ Logindaten hinzufügen</button>
          </div>

          <div v-if="istOrgAdmin && ressourceBearbeiten" class="ressource-admin">
            <form class="ressource-form" @submit.prevent="ressourceSpeichernHandler">
              <h3>{{ ressourceForm.id ? 'Eintrag bearbeiten' : (ressourceForm.typ === 'link' ? 'Link hinzufügen' : 'Logindaten hinzufügen') }}</h3>
              <label>Typ
                <select v-model="ressourceForm.typ">
                  <option value="link">{{ RESSOURCE_TYP_LABELS.link }}</option>
                  <option value="zugang">{{ RESSOURCE_TYP_LABELS.zugang }}</option>
                </select>
              </label>
              <label>Titel <input v-model="ressourceForm.titel" required /></label>
              <label>{{ ressourceForm.typ === 'link' ? 'URL' : 'Link zur Seite' }}
                <input v-model="ressourceForm.url" type="url" required placeholder="https://..." />
              </label>
              <template v-if="ressourceForm.typ === 'zugang'">
                <label>E-Mail / Benutzername <input v-model="ressourceForm.benutzername" required autocomplete="off" /></label>
                <label>Passwort
                  <input v-model="ressourceForm.passwort" type="password" autocomplete="new-password" :required="!ressourceForm.id" :placeholder="ressourceForm.id ? 'Leer lassen = unverändert' : ''" />
                </label>
              </template>
              <label>Notiz <input v-model="ressourceForm.notiz" placeholder="Optional" /></label>
              <label>Sichtbarkeit
                <select v-model="ressourceForm.sichtbarkeit">
                  <option v-for="(label, key) in SICHTBARKEIT_LABELS" :key="key" :value="key">{{ label }}</option>
                </select>
              </label>
              <fieldset v-if="ressourceForm.sichtbarkeit === 'ausgewaehlt'" class="mitglieder-auswahl">
                <legend>Berechtigte Mitglieder</legend>
                <label v-for="m in mitgliederAktiv" :key="m.profile_id" class="checkbox-label">
                  <input
                    type="checkbox"
                    :checked="ressourceForm.zugewiesene_profile_ids.includes(m.profile_id)"
                    @change="toggleRessourceMitglied(m.profile_id)"
                  />
                  {{ profilName(m) }}
                </label>
              </fieldset>
              <div class="inline-aktionen">
                <button type="submit" :disabled="ressourceSpeichern">{{ ressourceSpeichern ? 'Speichere…' : 'Speichern' }}</button>
                <button type="button" class="secondary" @click="ressourceAbbrechen">Abbrechen</button>
              </div>
            </form>
          </div>
        </section>

        <section v-if="aktivBereich === 'ressourcen' && orgKalenderBereit" class="karte">
          <h2>Vereinskalender</h2>
          <p class="hint">
            Ein Kalender für alle Lager im Verein. Name beim Abonnieren: <strong>{{ orgKalenderTitel }}</strong>.
            Für Google/Outlook den <strong>HTTPS-Link</strong> verwenden, für Apple den <strong>webcal-Link</strong>.
            Im Browser öffnet der Link eine Kalenderdatei (.ics) – keine normale Webseite.
          </p>
          <p class="abo-hinweis">
            HTTPS (Google, Outlook):
            <code>{{ orgKalenderHttps }}</code>
            <button
              type="button"
              class="secondary klein-btn"
              :class="{ kopiert: kalenderLinkKopiert === 'https' }"
              @click="kalenderLinkKopieren('https')"
            >
              {{ kalenderLinkKopiert === 'https' ? '✓ Kopiert' : 'Kopieren' }}
            </button><br />
            webcal (Apple):
            <code>{{ orgKalenderWebcal }}</code>
            <button
              type="button"
              class="secondary klein-btn"
              :class="{ kopiert: kalenderLinkKopiert === 'webcal' }"
              @click="kalenderLinkKopieren('webcal')"
            >
              {{ kalenderLinkKopiert === 'webcal' ? '✓ Kopiert' : 'Kopieren' }}
            </button>
          </p>
          <button type="button" class="secondary klein-btn" @click="orgKalenderIcsDownload">ICS herunterladen</button>
        </section>

        <section v-if="aktivBereich === 'fahrplan'" class="karte">
          <h2>Jahresfahrplan</h2>
          <p class="hint">
            Fahrplan des nächsten/aktuellen Lagers – gilt vereinsweit als Vorlage für die Folgejahre (Aufgaben, die hier ergänzt oder bearbeitet werden, erscheinen automatisch auch nächstes Jahr wieder).
          </p>
          <LagerFahrplan
            v-if="relevantesLager"
            :lager-id="relevantesLager.id"
            :organisation-id="orgAuswahl"
            :start-datum="relevantesLager.start_datum"
            :is-leitung="istVereinsleitung"
          />
          <p v-else class="hint">Noch kein Lager erfasst.</p>
        </section>

        <section v-if="aktivBereich === 'team'" class="karte">
          <h2>Mitglieder / Leiter im Verein</h2>
          <p v-if="istOrgAdmin" class="hint">
            Alle Leiter mit Login sowie manuell erfasste Personen. Als Admin kannst du Login-Leiter bearbeiten und aus dem Verein entfernen.
          </p>
          <p v-else-if="istVereinsleitung" class="hint">
            Alle Leiter mit Login sowie manuell erfasste Personen. Beitrittsanfragen findest du ganz oben, neue manuelle Einträge verwaltest du unten.
          </p>
          <p v-else class="hint">
            Übersicht aller Leiter und Kontaktdaten im Verein.
          </p>
          <table v-if="vereinsLeiterListe.length" class="liste">
            <thead>
              <tr>
                <th>Name</th>
                <th>E-Mail</th>
                <th>Telefon</th>
                <th>Rolle</th>
                <th>Quelle</th>
                <th v-if="istOrgAdmin">Aktionen</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="z in vereinsLeiterListe" :key="z.key">
                <template v-if="istOrgAdmin && z.profile_id && mitgliedEdit[z.profile_id] && z.typ === 'login'">
                  <td class="cell-edit">
                    <input v-model="mitgliedEdit[z.profile_id].vorname" placeholder="Vorname" />
                    <input v-model="mitgliedEdit[z.profile_id].nachname" placeholder="Nachname" />
                  </td>
                  <td>{{ z.email ?? '–' }}</td>
                  <td>{{ z.telefon ?? '–' }}</td>
                  <td>
                    <select v-model="mitgliedEdit[z.profile_id].rolle">
                      <option value="mitglied">Mitglied</option>
                      <option value="leitung">Leitung</option>
                      <option value="admin">Admin</option>
                    </select>
                  </td>
                </template>
                <template v-else-if="istOrgAdmin && z.org_person_id && personEdit[z.org_person_id]">
                  <td class="cell-edit">
                    <input v-model="personEdit[z.org_person_id].vorname" placeholder="Vorname" />
                    <input v-model="personEdit[z.org_person_id].nachname" placeholder="Nachname" />
                  </td>
                  <td class="cell-edit">
                    <input v-model="personEdit[z.org_person_id].email" type="email" placeholder="E-Mail" />
                  </td>
                  <td class="cell-edit">
                    <input v-model="personEdit[z.org_person_id].telefon" placeholder="Telefon" />
                  </td>
                  <td>
                    <input v-model="personEdit[z.org_person_id].rolle_hinweis" placeholder="Rolle/Hinweis" />
                  </td>
                </template>
                <template v-else>
                  <td>{{ zeilenName(z.vorname, z.nachname, z.email) }}</td>
                  <td>{{ z.email ?? '–' }}</td>
                  <td>{{ z.telefon ?? '–' }}</td>
                  <td>{{ rollenLabel(z.rolle) }}</td>
                </template>
                <td>
                  <span v-if="z.typ === 'login' && z.verknuepft">Login</span>
                  <span v-else-if="z.verknuepft">Login (verknüpft)</span>
                  <span v-else>Manuell</span>
                </td>
                <td v-if="istOrgAdmin">
                  <div v-if="z.profile_id && mitgliedEdit[z.profile_id] && z.typ === 'login'" class="inline-aktionen">
                    <button
                      class="secondary klein-btn"
                      :disabled="mitgliedAktionLade[z.profile_id]"
                      @click="mitgliedAktualisieren(z.profile_id!)"
                    >
                      Speichern
                    </button>
                    <button
                      class="secondary klein-btn"
                      :disabled="mitgliedAktionLade[z.profile_id]"
                      @click="mitgliedEntfernen(z.profile_id!, `${z.vorname} ${z.nachname}`.trim() || z.email || 'Leiter')"
                    >
                      Entfernen
                    </button>
                  </div>
                  <div v-else-if="z.org_person_id" class="inline-aktionen">
                    <button
                      class="secondary klein-btn"
                      :disabled="personAktionLade[z.org_person_id]"
                      @click="personAktualisieren(z.org_person_id!)"
                    >
                      Speichern
                    </button>
                    <button
                      class="secondary klein-btn"
                      :disabled="personAktionLade[z.org_person_id]"
                      @click="personLoeschen(z.org_person_id!)"
                    >
                      Löschen
                    </button>
                  </div>
                  <span v-else class="hint klein">–</span>
                </td>
              </tr>
            </tbody>
          </table>
          <p v-else class="hint">Noch keine Leiter erfasst.</p>

          <details class="rollen-info">
            <summary>Rollen im Verein: Mitglied, Leitung, Admin</summary>
            <dl>
              <div class="rollen-eintrag">
                <dt>Mitglied</dt>
                <dd>
                  Siehst Vereinslager, die Leiterliste mit Kontaktdaten und kannst dich als Leiter/in für Lager bewerben.
                  Keine Verwaltungsrechte im Verein.
                </dd>
              </div>
              <div class="rollen-eintrag">
                <dt>Leitung</dt>
                <dd>
                  Alles wie Mitglied, plus: neue Lager erfassen, Beitrittsanfragen bearbeiten und Leiter ohne Login manuell hinzufügen.
                  Die Leiterliste ist schreibgeschützt – Bearbeiten nur durch Admins.
                </dd>
              </div>
              <div class="rollen-eintrag">
                <dt>Admin</dt>
                <dd>
                  Vollzugriff auf die Leiterliste: Namen, Rollen und Kontakte von Login-Leitern bearbeiten oder aus dem Verein entfernen.
                  Manuelle Einträge können ebenfalls bearbeitet werden. Mindestens ein Admin muss im Verein bleiben.
                </dd>
              </div>
            </dl>
          </details>

          <h3 v-if="istVereinsleitung">Leiter manuell erfassen</h3>
          <p v-if="istVereinsleitung" class="hint">
            Für Leiter ohne Login. Beim Beitritt kann ein Login später mit dem manuellen Eintrag verknüpft werden.
          </p>
          <form v-if="istVereinsleitung" class="inline-form" @submit.prevent="personHinzufuegen">
            <input v-model="personForm.vorname" placeholder="Vorname" required />
            <input v-model="personForm.nachname" placeholder="Nachname" required />
            <input v-model="personForm.email" type="email" placeholder="E-Mail (optional)" />
            <input v-model="personForm.telefon" placeholder="Telefon" />
            <input v-model="personForm.rolle_hinweis" placeholder="Rolle / Hinweis" />
            <button type="submit" :disabled="personSpeichern">{{ personSpeichern ? 'Speichere…' : 'Person hinzufügen' }}</button>
          </form>

          <template v-if="istVereinsleitung">
            <h3 class="unterabschnitt">Neues Lager erfassen</h3>
            <form class="lager-form" @submit.prevent="lagerFormularAbsenden">
              <label>Jahr <input v-model.number="lagerForm.jahr" type="number" required min="2020" /></label>
              <label>Name <input v-model="lagerForm.name" required /></label>
              <label>Ort <input ref="ortInput" v-model="lagerForm.ort" placeholder="Adresse eingeben..." /></label>
              <label>Start <input v-model="lagerForm.start_datum" type="date" /></label>
              <label>Ende <input v-model="lagerForm.end_datum" type="date" /></label>
              <label>Vorjahres-Lager
                <select v-model="lagerForm.vor_lager_id">
                  <option value="">– optional –</option>
                  <option v-for="l in vorLagerListe" :key="l.id" :value="l.id">{{ l.name }} ({{ l.jahr }})</option>
                </select>
              </label>
              <button type="submit" :disabled="lagerSpeichern">{{ lagerSpeichern ? 'Speichere...' : 'Lager erstellen' }}</button>
            </form>

            <div v-if="laleiModalOffen" class="modal-overlay" @click.self="laleiModalAbbrechen">
              <div class="modal-karte" role="dialog" aria-labelledby="lalei-modal-titel">
                <h3 id="lalei-modal-titel">Lagerleitung (Lalei) festlegen</h3>
                <p class="hint">Wer ist Lagerleitung für «{{ lagerForm.name }}»?</p>
                <fieldset class="lalei-feld">
                  <label class="radio-label">
                    <input v-model="laleiModal.modus" type="radio" value="selbst" />
                    Ich bin Lagerleitung (Lalei)
                  </label>
                  <label class="radio-label">
                    <input v-model="laleiModal.modus" type="radio" value="verein" />
                    Person aus dem Verein als Lalei wählen
                  </label>
                  <label v-if="laleiModal.modus === 'verein'">
                    Lalei
                    <select v-model="laleiModal.personId" required>
                      <option value="">– Person wählen –</option>
                      <option v-for="p in lagerPersonenPool" :key="p.id" :value="p.id">
                        {{ p.vorname }} {{ p.nachname }}{{ p.email ? ` (${p.email})` : '' }}
                      </option>
                    </select>
                  </label>
                  <p class="hint">Die Lalei ist standardmässig über die ganze Lagerzeit anwesend.</p>
                </fieldset>
                <div class="modal-aktionen">
                  <button type="button" class="secondary" @click="laleiModalAbbrechen">Abbrechen</button>
                  <button type="button" :disabled="lagerSpeichern" @click="lagerErstellen">
                    {{ lagerSpeichern ? 'Erstelle…' : 'Lager erstellen' }}
                  </button>
                </div>
              </div>
            </div>
          </template>
        </section>
      </template>

      <p v-if="info" class="ok">{{ info }}</p>
      <p v-if="fehler" class="error">{{ fehler }}</p>
      <p v-if="laden" class="hint">Lade…</p>
    </main>
  </div>
</template>

<style scoped>
.org-page { min-height: 100vh; }
.top-full {
  position: sticky;
  top: 0;
  z-index: 100;
  width: 100%;
  background: var(--color-surface);
  border-bottom: 1px solid var(--color-border);
}
main { max-width: 1000px; margin: 0 auto; padding: 1rem 1.25rem 2rem; }
.verein-tabs {
  display: flex; flex-wrap: wrap; gap: 0.3rem;
  margin-bottom: 1rem; padding-bottom: 0.5rem; border-bottom: 1px solid var(--color-border);
}
.verein-tabs button {
  padding: 0.45rem 0.9rem; font-size: 0.88rem; font-weight: 600;
  background: transparent; border: 1px solid transparent; border-radius: var(--radius-md);
  color: var(--color-text-muted); cursor: pointer;
}
.verein-tabs button:hover { background: var(--color-surface-muted); }
.verein-tabs button.aktiv { background: var(--color-accent); color: #fdfbf3; }
.kopf { margin-bottom: 1rem; }
.kopf h1 { margin: 0 0 0.35rem; }
.karte {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 1rem 1.15rem;
  margin-bottom: 0.9rem;
}
.karte h2 { margin: 0 0 0.4rem; font-size: 1.05rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.lager-grid { display: grid; gap: 0.65rem; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); }
.lager-karte { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.75rem 0.85rem; }
.meta { display: block; font-size: 0.8rem; color: var(--color-text-muted); margin-top: 0.15rem; }
.inline-aktionen { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 0.6rem; }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: end; margin-top: 0.75rem; }
.lager-form {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  gap: 0.65rem;
  align-items: end;
}
label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.84rem; color: var(--color-text-muted); }
.liste { width: 100%; border-collapse: collapse; margin-top: 0.6rem; font-size: 0.88rem; }
.liste th, .liste td { text-align: left; padding: 0.45rem 0.6rem; border-bottom: 1px solid var(--color-border); }
.cell-edit { min-width: 170px; }
.cell-edit input {
  display: block;
  width: 100%;
  margin-bottom: 0.3rem;
}
.cell-edit input:last-child { margin-bottom: 0; }
.klein { font-size: 0.78rem; color: var(--color-text-muted); }
.klein-btn { font-size: 0.78rem; padding: 0.2rem 0.5rem; }
.anfragen-box { margin-top: 0.8rem; }
.anfrage-karte {
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 0.65rem 0.8rem;
  margin-bottom: 0.45rem;
}
.anfrage-kopf { display: flex; flex-direction: column; gap: 0.15rem; margin-bottom: 0.5rem; }
.anfrage-mail { color: var(--color-text-muted); font-size: 0.88rem; }
.anfrage-aktionen { flex-direction: column; align-items: stretch; }
.verknuepf-zeile { display: flex; flex-wrap: wrap; gap: 0.45rem; align-items: center; }
.verknuepf-zeile select { min-width: 220px; flex: 1; }
.vergangen { margin-top: 0.75rem; }
.vergangen summary { cursor: pointer; font-weight: 600; }
.rollen-info { margin-top: 1rem; border-top: 1px solid var(--color-border); padding-top: 0.75rem; }
.rollen-info summary { cursor: pointer; font-weight: 600; }
.rollen-info dl { margin: 0.75rem 0 0; }
.rollen-eintrag { margin-bottom: 0.75rem; }
.rollen-eintrag dt { font-weight: 600; margin-bottom: 0.2rem; }
.rollen-eintrag dd { margin: 0; color: var(--color-text-muted); font-size: 0.88rem; line-height: 1.45; }
.link-like { border: none; background: transparent; color: var(--color-accent); padding: 0; cursor: pointer; }
.vorlagen-liste { list-style: none; padding: 0; margin: 0.5rem 0 0; }
.vorlagen-liste li { border-bottom: 1px solid var(--color-border); padding: 0.4rem 0; }
.ok { color: #2e7d32; }
.error { color: var(--color-danger); }
.lalei-feld { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.75rem; margin: 0.5rem 0; display: flex; flex-direction: column; gap: 0.5rem; }
.modal-overlay {
  position: fixed; inset: 0; background: rgba(0, 0, 0, 0.45); z-index: 200;
  display: flex; align-items: center; justify-content: center; padding: 1rem;
}
.modal-karte {
  background: var(--color-surface); border-radius: var(--radius-md); padding: 1.25rem;
  max-width: 420px; width: 100%; box-shadow: 0 8px 32px rgba(0, 0, 0, 0.2);
}
.modal-karte h3 { margin: 0 0 0.5rem; }
.modal-aktionen { display: flex; gap: 0.6rem; justify-content: flex-end; margin-top: 1rem; }
.radio-label { flex-direction: row !important; align-items: center; gap: 0.5rem; color: var(--color-text) !important; }
.ressourcen-gruppe { margin: 1.25rem 0; }
.ressourcen-gruppe h3 { margin: 0 0 0.5rem; font-size: 1rem; }
.ressourcen-liste { display: grid; gap: 0.65rem; margin: 0.75rem 0; }
.ressource-karte { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.75rem 0.85rem; }
.ressource-kopf { display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem; margin-bottom: 0.35rem; }
.badge { font-size: 0.72rem; background: var(--color-surface-muted); padding: 0.1rem 0.45rem; border-radius: 999px; }
.zugang-zeile { margin: 0.25rem 0; font-size: 0.88rem; }
.zugang-zeile span { color: var(--color-text-muted); margin-right: 0.35rem; }
.ressource-form { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 0.65rem; margin-top: 0.75rem; align-items: end; }
.mitglieder-auswahl { grid-column: 1 / -1; border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.65rem; display: flex; flex-wrap: wrap; gap: 0.5rem 1rem; }
.mitglieder-auswahl legend { font-weight: 600; width: 100%; }
.checkbox-label { flex-direction: row !important; align-items: center; gap: 0.4rem; color: var(--color-text) !important; font-size: 0.85rem !important; }
.unterabschnitt { margin: 1.5rem 0 0.65rem; font-size: 1rem; }
.abo-hinweis { font-size: 0.82rem; background: var(--color-surface-muted); padding: 0.5rem 0.65rem; border-radius: var(--radius-md); word-break: break-all; margin: 0.65rem 0; }
.kopiert { background: #e8f5e9 !important; color: #2e7d32 !important; border-color: #2e7d32 !important; }
.ressource-admin { margin-top: 0.5rem; }
</style>
