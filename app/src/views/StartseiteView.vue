<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { supabase } from '../supabaseClient'
import AppHeader from '../components/AppHeader.vue'

interface VereinMitgliedschaft {
  organisation_id: string
  slug: string
  name: string
  homepage: string | null
  meine_rolle: 'mitglied' | 'leitung' | 'admin'
  mein_status: 'angefragt' | 'mitglied' | 'abgelehnt'
  offene_beitrittsanfragen: number
}

interface LagerShortcut {
  id: string
  organisation_id: string
  name: string
  jahr: number
  ort: string | null
  start_datum: string | null
  end_datum: string | null
  status: string
  can_edit: boolean
}

interface OrganisationTreffer {
  id: string
  name: string
  slug: string
}

const router = useRouter()
const { session } = useAuth()

const laden = ref(true)
const fehler = ref('')
const info = ref('')

const vereine = ref<VereinMitgliedschaft[]>([])
const lagerShortcuts = ref<LagerShortcut[]>([])

const vereinForm = ref({ name: '' })
const vereinSaving = ref(false)

const suche = ref('')
const treffer = ref<OrganisationTreffer[]>([])
const joinOrgId = ref('')
const joinSaving = ref(false)

const mitgliedVereine = computed(() => vereine.value.filter((v) => v.mein_status === 'mitglied'))
const offeneAnfragen = computed(() => vereine.value.filter((v) => v.mein_status === 'angefragt'))
const wartendeAnfragenBeiMir = computed(() => vereine.value.filter((v) => v.offene_beitrittsanfragen > 0))

function slugify(text: string) {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
}

function datumPlusTage(datum: string, tage: number) {
  const d = new Date(`${datum}T00:00:00Z`)
  d.setUTCDate(d.getUTCDate() + tage)
  return d.toISOString().slice(0, 10)
}

function istSichtbar(l: LagerShortcut, diashowDatum: string | null) {
  if (l.status === 'archiviert') return false
  const heute = new Date().toISOString().slice(0, 10)
  if (!l.end_datum || l.end_datum >= heute) return true
  // Vergangenes Lager: bis eine Woche nach der Diashow (Fallback: Lagerende) weiterhin sichtbar.
  const referenz = diashowDatum ?? l.end_datum
  return datumPlusTage(referenz, 7) >= heute
}

async function ladeDaten() {
  laden.value = true
  fehler.value = ''

  const { data: meine, error: meineErr } = await supabase.rpc('list_meine_vereine')
  if (meineErr) {
    fehler.value = meineErr.message
    laden.value = false
    return
  }
  vereine.value = (meine ?? []) as VereinMitgliedschaft[]

  const alleLager: LagerShortcut[] = []
  for (const v of vereine.value.filter((x) => x.mein_status === 'mitglied')) {
    const { data: lager, error: lagerErr } = await supabase.rpc('list_vereinslager', { p_organisation_id: v.organisation_id })
    if (lagerErr) continue
    for (const row of (lager ?? [])) alleLager.push(row as LagerShortcut)
  }

  const heute = new Date().toISOString().slice(0, 10)
  const vergangeneIds = alleLager.filter((l) => l.end_datum && l.end_datum < heute).map((l) => l.id)
  const diashowMap = new Map<string, string>()
  if (vergangeneIds.length) {
    const { data: termine } = await supabase
      .from('lager_termine')
      .select('lager_id, start_datum')
      .eq('typ', 'diashow')
      .in('lager_id', vergangeneIds)
    for (const t of termine ?? []) {
      if (t.start_datum) diashowMap.set(t.lager_id as string, t.start_datum as string)
    }
  }

  const shortcuts = alleLager.filter((l) => istSichtbar(l, diashowMap.get(l.id) ?? null))
  shortcuts.sort((a, b) => (a.start_datum ?? '9999-12-31').localeCompare(b.start_datum ?? '9999-12-31'))
  lagerShortcuts.value = shortcuts
  laden.value = false
}

async function sucheVereine() {
  joinOrgId.value = ''
  if (suche.value.trim().length < 1) {
    treffer.value = []
    return
  }
  const { data } = await supabase
    .from('organisation')
    .select('id, name, slug')
    .ilike('name', `%${suche.value.trim()}%`)
    .order('name')
    .limit(8)
  treffer.value = (data ?? []) as OrganisationTreffer[]
}

async function vereinErstellen() {
  if (!session.value) return
  info.value = ''
  fehler.value = ''
  vereinSaving.value = true
  const name = vereinForm.value.name.trim()
  const slug = slugify(name)
  const { data: org, error: orgErr } = await supabase
    .from('organisation')
    .insert({ name, slug })
    .select('id')
    .single()
  if (orgErr || !org) {
    vereinSaving.value = false
    fehler.value = orgErr?.message ?? 'Verein konnte nicht erstellt werden.'
    return
  }

  const { error: memErr } = await supabase.from('organisation_mitglieder').upsert({
    organisation_id: org.id,
    profile_id: session.value.user.id,
    rolle: 'admin',
    status: 'mitglied',
    bestaetigt_am: new Date().toISOString(),
    bestaetigt_von: session.value.user.id,
  }, { onConflict: 'organisation_id,profile_id' })

  if (memErr) {
    vereinSaving.value = false
    fehler.value = memErr.message
    return
  }

  vereinForm.value.name = ''
  vereinSaving.value = false
  await ladeDaten()
  await router.push(`/organisation?org=${org.id}`)
}

async function beitrittAnfragen() {
  const orgId = joinOrgId.value
  if (!orgId) return
  info.value = ''
  fehler.value = ''
  joinSaving.value = true
  const { error } = await supabase.rpc('verein_beitrittsanfrage_stellen', { p_organisation_id: orgId })
  joinSaving.value = false
  if (error) {
    fehler.value = error.message
    return
  }
  info.value = 'Beitrittsanfrage gesendet.'
  suche.value = ''
  treffer.value = []
  joinOrgId.value = ''
  await ladeDaten()
}

function zuOrganisation(v: VereinMitgliedschaft) {
  router.push(`/organisation?org=${v.organisation_id}`)
}

function zuLager(l: LagerShortcut) {
  if (l.can_edit) {
    router.push(`/lager/${l.id}/dashboard`)
    return
  }
  router.push(`/lager/${l.id}/willkommen`)
}

function zuLeiterAnmeldung(l: LagerShortcut) {
  router.push(`/lager/${l.id}/anmelden-leiter`)
}

onMounted(async () => {
  if (!session.value) return
  await ladeDaten()
})
</script>

<template>
  <div class="startseite">
    <div class="top-full">
      <AppHeader :show-alle-lager="false" />
    </div>

    <main>
      <!-- Noch in keinem Verein: Beitreten/Erstellen ganz prominent zuoberst -->
      <template v-if="!laden && !mitgliedVereine.length">
        <section class="karte einstieg-karte">
          <h2>Willkommen! Zuerst: einem Verein beitreten</h2>
          <p class="hint">Suche deinen Verein und sende eine Beitrittsanfrage – danach siehst du dessen Lager.</p>
          <input v-model="suche" placeholder="Verein suchen…" @input="sucheVereine" />
          <div v-if="treffer.length" class="treffer">
            <button
              v-for="t in treffer"
              :key="t.id"
              type="button"
              class="treffer-item"
              :class="{ aktiv: joinOrgId === t.id }"
              @click="joinOrgId = t.id"
            >
              {{ t.name }}
            </button>
          </div>
          <div class="inline-aktionen">
            <button type="button" :disabled="!joinOrgId || joinSaving" @click="beitrittAnfragen">
              {{ joinSaving ? 'Sende…' : 'Beitrittsanfrage senden' }}
            </button>
          </div>
          <p v-if="offeneAnfragen.length" class="hint">
            Offene Anfragen: {{ offeneAnfragen.map((v) => v.name).join(', ') }}
          </p>
          <h3>Oder: eigenen Verein erstellen</h3>
          <form class="inline-form" @submit.prevent="vereinErstellen">
            <input v-model="vereinForm.name" placeholder="Vereinsname" required />
            <button type="submit" :disabled="vereinSaving">{{ vereinSaving ? 'Erstelle…' : 'Verein erstellen' }}</button>
          </form>
        </section>
      </template>

      <!-- Beitrittsanfragen, die auf DEINE Entscheidung warten (nicht die eigenen gesendeten) -->
      <section v-if="wartendeAnfragenBeiMir.length" class="karte anfragen-karte">
        <h2>Beitrittsanfragen warten auf dich</h2>
        <ul class="anfragen-liste">
          <li v-for="v in wartendeAnfragenBeiMir" :key="v.organisation_id">
            <span>{{ v.name }}</span>
            <span class="badge warn">{{ v.offene_beitrittsanfragen }} offen</span>
            <button type="button" class="klein" @click="zuOrganisation(v)">Bearbeiten</button>
          </li>
        </ul>
      </section>

      <section v-if="mitgliedVereine.length || laden" class="karte">
        <h2>Deine Vereine</h2>
        <p class="hint">Wähle einen Verein, um zu Organisation, Mitgliedern und Lagern zu gelangen.</p>
        <p v-if="laden">Lade…</p>
        <div v-else-if="vereine.length" class="karten-grid">
          <button
            v-for="v in vereine"
            :key="`${v.organisation_id}-${v.mein_status}`"
            class="verein-karte"
            @click="zuOrganisation(v)"
          >
            <strong>{{ v.name }}</strong>
            <span class="meta">
              {{ v.mein_status === 'mitglied' ? `Rolle: ${v.meine_rolle}` : `Status: ${v.mein_status}` }}
            </span>
          </button>
        </div>
      </section>

      <section v-if="mitgliedVereine.length" class="karte">
        <h2>Laufende & kommende Lager</h2>
        <p class="hint">Shortcuts für Lager aus deinen Vereinen.</p>
        <div v-if="lagerShortcuts.length" class="karten-grid">
          <article v-for="l in lagerShortcuts" :key="l.id" class="lager-karte">
            <strong>{{ l.name }}</strong>
            <span class="meta">{{ l.jahr }} · {{ l.status }}</span>
            <span v-if="l.start_datum" class="meta">{{ l.start_datum }} – {{ l.end_datum ?? '?' }}</span>
            <div class="inline-aktionen">
              <button @click="zuLager(l)">{{ l.can_edit ? 'Lager öffnen' : 'Als Gast ansehen' }}</button>
              <button v-if="!l.can_edit" class="secondary" @click="zuLeiterAnmeldung(l)">Als Leiter anmelden</button>
            </div>
          </article>
        </div>
        <p v-else class="hint">Keine laufenden oder kommenden Lager gefunden.</p>
      </section>

      <!-- Bereits in einem Verein: Beitreten/Erstellen dezenter weiter unten -->
      <template v-if="mitgliedVereine.length">
        <section class="karte">
          <h2>Verein erstellen</h2>
          <form class="inline-form" @submit.prevent="vereinErstellen">
            <input v-model="vereinForm.name" placeholder="Vereinsname" required />
            <button type="submit" :disabled="vereinSaving">{{ vereinSaving ? 'Erstelle…' : 'Verein erstellen' }}</button>
          </form>
        </section>

        <section class="karte">
          <h2>Weiterem Verein beitreten</h2>
          <p class="hint">Suche bestehende Vereine und sende eine Beitrittsanfrage.</p>
          <input v-model="suche" placeholder="Verein suchen…" @input="sucheVereine" />
          <div v-if="treffer.length" class="treffer">
            <button
              v-for="t in treffer"
              :key="t.id"
              type="button"
              class="treffer-item"
              :class="{ aktiv: joinOrgId === t.id }"
              @click="joinOrgId = t.id"
            >
              {{ t.name }}
            </button>
          </div>
          <div class="inline-aktionen">
            <button type="button" :disabled="!joinOrgId || joinSaving" @click="beitrittAnfragen">
              {{ joinSaving ? 'Sende…' : 'Beitrittsanfrage senden' }}
            </button>
          </div>
          <p v-if="offeneAnfragen.length" class="hint">
            Offene Anfragen:
            {{ offeneAnfragen.map((v) => v.name).join(', ') }}
          </p>
        </section>
      </template>

      <p v-if="info" class="ok">{{ info }}</p>
      <p v-if="fehler" class="error">{{ fehler }}</p>
    </main>
  </div>
</template>

<style scoped>
.startseite { min-height: 100vh; }
.top-full {
  position: sticky;
  top: 0;
  z-index: 100;
  width: 100%;
  background: var(--color-surface);
  border-bottom: 1px solid var(--color-border);
}
main { max-width: 1000px; margin: 0 auto; padding: 1rem 1.25rem 2rem; }
.karte {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 1rem 1.15rem;
  margin-bottom: 0.9rem;
}
.karte h2 { margin: 0 0 0.45rem; font-size: 1.05rem; }
.anfragen-karte { border-color: #c98a3f; border-width: 2px; }
.anfragen-liste { list-style: none; padding: 0; margin: 0.5rem 0 0; display: flex; flex-direction: column; gap: 0.5rem; }
.anfragen-liste li { display: flex; align-items: center; gap: 0.6rem; }
.anfragen-liste .badge.warn { background: #c98a3f; color: #fff; padding: 0.15rem 0.5rem; border-radius: var(--radius-pill); font-size: 0.78rem; }
button.klein { font-size: 0.8rem; padding: 0.3rem 0.7rem; }
.einstieg-karte { border-color: var(--color-accent); border-width: 2px; padding: 1.25rem 1.4rem; }
.einstieg-karte h2 { font-size: 1.3rem; }
.einstieg-karte h3 { margin: 1.25rem 0 0.5rem; font-size: 1rem; }
.karten-grid { display: grid; gap: 0.65rem; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); }
.verein-karte, .lager-karte {
  text-align: left;
  border: 1px solid var(--color-border);
  background: var(--color-surface);
  color: var(--color-text);
  border-radius: var(--radius-md);
  padding: 0.75rem 0.85rem;
}
.verein-karte:hover { background: var(--color-surface-muted); }
.meta { display: block; font-size: 0.8rem; color: var(--color-text-muted); margin-top: 0.2rem; }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: end; }
.inline-aktionen { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 0.65rem; }
.treffer { display: grid; gap: 0.35rem; margin-top: 0.55rem; }
.treffer-item {
  text-align: left;
  border: 1px solid var(--color-border);
  background: var(--color-surface);
  color: var(--color-text);
  border-radius: var(--radius-sm);
  padding: 0.45rem 0.6rem;
}
.treffer-item.aktiv { border-color: var(--color-accent); }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.ok { color: #2e7d32; }
.error { color: var(--color-danger); }
</style>
