<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
import { useGooglePlaces } from '../composables/useGooglePlaces'
import AppHeader from '../components/AppHeader.vue'
import { ECAMP_URL } from '../lib/constants'

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
  profiles:
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
const personAktionLade = ref<Record<string, boolean>>({})
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
const lagerSpeichern = ref(false)

const ortInput = ref<HTMLInputElement | null>(null)

const aktiveVereine = computed(() => vereine.value.filter((v) => v.mein_status === 'mitglied'))
const aktuellerVerein = computed(() => aktiveVereine.value.find((v) => v.organisation_id === orgAuswahl.value) ?? null)
const istVereinsleitung = computed(() =>
  !!aktuellerVerein.value && ['leitung', 'admin'].includes(aktuellerVerein.value.meine_rolle),
)

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

function profilVon(m: VereinsMitglied) {
  if (!m.profiles) return null
  if (Array.isArray(m.profiles)) return m.profiles[0] ?? null
  return m.profiles
}

function profilName(m: VereinsMitglied): string {
  const p = profilVon(m)
  const name = `${p?.vorname ?? ''} ${p?.nachname ?? ''}`.trim()
  return name || p?.email || 'Unbekannt'
}

function profilEmail(m: VereinsMitglied): string {
  return profilVon(m)?.email ?? '–'
}

const vereinsLeiterListe = computed((): VereinsLeiterZeile[] => {
  const zeilen: VereinsLeiterZeile[] = []
  const verknuepfteProfile = new Set<string>()

  for (const person of orgPersonen.value) {
    if (person.profile_id) verknuepfteProfile.add(person.profile_id)
  }

  for (const m of mitgliederAktiv.value) {
    const p = profilVon(m)
    zeilen.push({
      key: `login-${m.profile_id}`,
      typ: 'login',
      vorname: p?.vorname ?? '',
      nachname: p?.nachname ?? '',
      email: p?.email ?? null,
      rolle: m.rolle,
      profile_id: m.profile_id,
      org_person_id: null,
      verknuepft: true,
    })
  }

  for (const person of orgPersonen.value) {
    if (person.profile_id && verknuepfteProfile.has(person.profile_id)) {
      const schonAlsLogin = zeilen.some((z) => z.profile_id === person.profile_id)
      if (schonAlsLogin) continue
    }
    zeilen.push({
      key: `person-${person.id}`,
      typ: person.profile_id ? 'login' : 'manuell',
      vorname: person.vorname,
      nachname: person.nachname,
      email: person.email,
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

  const [{ data: m }, { data: p }, { data: v }, { data: l }, { data: vor }] = await Promise.all([
    supabase
      .from('organisation_mitglieder')
      .select('organisation_id, profile_id, rolle, status, angefragt_am, profiles:profile_id(vorname, nachname, email)')
      .eq('organisation_id', orgId)
      .order('angefragt_am', { ascending: false }),
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
  ])

  mitglieder.value = (m ?? []) as VereinsMitglied[]
  orgPersonen.value = (p ?? []) as VereinsPerson[]
  personEdit.value = {}
  for (const person of orgPersonen.value) {
    personEdit.value[person.id] = {
      vorname: person.vorname,
      nachname: person.nachname,
      email: person.email ?? '',
      telefon: person.telefon ?? '',
      rolle_hinweis: person.rolle_hinweis ?? '',
    }
  }
  orgVorlagen.value = (v ?? []) as OrgTodoVorlage[]
  lager.value = (l ?? []) as VereinsLager[]
  vorLagerListe.value = (vor ?? []) as { id: string; name: string; jahr: number }[]
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
    info.value = orgPersonId ? 'Beitritt genehmigt und mit manuellem Leiter verknüpft.' : 'Neuer Leiter aufgenommen.'
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

  await supabase.from('lager_leiter').insert({
    lager_id: neuesLager.id,
    profile_id: session.value.user.id,
    rolle: 'lagerleitung',
    status: 'bestaetigt',
  })

  if (lagerForm.value.start_datum) {
    await supabase.rpc('lager_todos_generieren', { p_lager_id: neuesLager.id })
  }

  lagerSpeichern.value = false
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
        <section class="karte">
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

        <section v-if="istVereinsleitung" class="karte">
          <h2>Neues Lager erfassen</h2>
          <form class="lager-form" @submit.prevent="lagerErstellen">
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
        </section>

        <section class="karte">
          <h2>Mitglieder / Leiter im Verein</h2>
          <p class="hint">
            Alle Leiter mit Login sowie manuell erfasste Personen. Nur Vereinsleitung entscheidet Beitrittsanfragen.
          </p>
          <table v-if="vereinsLeiterListe.length" class="liste">
            <thead>
              <tr>
                <th>Name</th>
                <th>E-Mail</th>
                <th>Rolle</th>
                <th>Quelle</th>
                <th v-if="istVereinsleitung">Aktionen</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="z in vereinsLeiterListe" :key="z.key">
                <template v-if="istVereinsleitung && z.org_person_id && personEdit[z.org_person_id]">
                  <td class="cell-edit">
                    <input v-model="personEdit[z.org_person_id].vorname" placeholder="Vorname" />
                    <input v-model="personEdit[z.org_person_id].nachname" placeholder="Nachname" />
                  </td>
                  <td class="cell-edit">
                    <input v-model="personEdit[z.org_person_id].email" type="email" placeholder="E-Mail" />
                    <input v-model="personEdit[z.org_person_id].telefon" placeholder="Telefon" />
                  </td>
                  <td>
                    <input v-model="personEdit[z.org_person_id].rolle_hinweis" placeholder="Rolle/Hinweis" />
                  </td>
                </template>
                <template v-else>
                  <td>{{ z.vorname }} {{ z.nachname }}</td>
                  <td>{{ z.email ?? '–' }}</td>
                  <td>{{ z.rolle }}</td>
                </template>
                <td>
                  <span v-if="z.typ === 'login' && z.verknuepft">Login</span>
                  <span v-else-if="z.verknuepft">Login (verknüpft)</span>
                  <span v-else>Manuell</span>
                </td>
                <td v-if="istVereinsleitung">
                  <div v-if="z.org_person_id" class="inline-aktionen">
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

          <div v-if="istVereinsleitung && anfragen.length" class="anfragen-box">
            <h3>Beitrittsanfragen</h3>
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
          </div>

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
.link-like { border: none; background: transparent; color: var(--color-accent); padding: 0; cursor: pointer; }
.vorlagen-liste { list-style: none; padding: 0; margin: 0.5rem 0 0; }
.vorlagen-liste li { border-bottom: 1px solid var(--color-border); padding: 0.4rem 0; }
.ok { color: #2e7d32; }
.error { color: var(--color-danger); }
</style>
