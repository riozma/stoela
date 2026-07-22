<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { supabase } from '../supabaseClient'
import FeedbackButton from './FeedbackButton.vue'
import AppDialog from './AppDialog.vue'

const props = withDefaults(
  defineProps<{
    lagerName?: string
    organisationId?: string
    organisationName?: string
    showAlleLager?: boolean
    showNavToggle?: boolean
    navOpen?: boolean
  }>(),
  { showAlleLager: true },
)

defineEmits<{ toggleNav: [] }>()

const { session, signOut } = useAuth()
const router = useRouter()
const profil = ref<{ vorname: string | null; nachname: string | null; telefon: string | null } | null>(null)

interface VereinEintrag {
  organisation_id: string
  name: string
  mein_status: 'angefragt' | 'mitglied' | 'abgelehnt'
  meine_rolle: 'mitglied' | 'leitung' | 'admin'
}

const wechslerOffen = ref(false)
const vereine = ref<VereinEintrag[]>([])
const vereineGeladen = ref(false)
const meineVereine = computed(() => vereine.value.filter((v) => v.mein_status === 'mitglied'))

const neuVereinOffen = ref(false)
const neuVereinForm = ref({ name: '' })
const neuVereinSpeichern = ref(false)

const beitretenOffen = ref(false)
const suche = ref('')
const treffer = ref<{ id: string; name: string }[]>([])
const joinOrgId = ref('')
const joinSaving = ref(false)

const wechslerInfo = ref('')
const wechslerFehler = ref('')

function slugify(text: string) {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
}

async function ladeVereine() {
  if (!session.value) return
  vereineGeladen.value = false
  const { data } = await supabase.rpc('list_meine_vereine')
  vereine.value = (data ?? []) as VereinEintrag[]
  vereineGeladen.value = true
}

function wechslerOeffnen() {
  wechslerOffen.value = true
  neuVereinOffen.value = false
  beitretenOffen.value = false
  wechslerInfo.value = ''
  wechslerFehler.value = ''
  suche.value = ''
  treffer.value = []
  void ladeVereine()
}

function zuVerein(orgId: string) {
  wechslerOffen.value = false
  router.push(`/organisation?org=${orgId}`)
}

function neuesLagerBei(orgId: string) {
  wechslerOffen.value = false
  router.push(`/organisation?org=${orgId}&neu=lager`)
}

async function vereinErstellen() {
  if (!session.value) return
  const name = neuVereinForm.value.name.trim()
  if (!name) return
  neuVereinSpeichern.value = true
  wechslerFehler.value = ''
  const slug = slugify(name)
  const { data: org, error: orgErr } = await supabase
    .from('organisation')
    .insert({ name, slug })
    .select('id')
    .single()
  if (orgErr || !org) {
    neuVereinSpeichern.value = false
    wechslerFehler.value = orgErr?.message ?? 'Verein konnte nicht erstellt werden.'
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
  neuVereinSpeichern.value = false
  if (memErr) {
    wechslerFehler.value = memErr.message
    return
  }
  neuVereinForm.value.name = ''
  wechslerOffen.value = false
  await router.push(`/organisation?org=${org.id}&neu=lager`)
}

async function sucheVereine() {
  joinOrgId.value = ''
  if (suche.value.trim().length < 1) {
    treffer.value = []
    return
  }
  const { data } = await supabase
    .from('organisation')
    .select('id, name')
    .ilike('name', `%${suche.value.trim()}%`)
    .order('name')
    .limit(8)
  treffer.value = (data ?? []) as { id: string; name: string }[]
}

async function beitrittAnfragen() {
  if (!joinOrgId.value) return
  joinSaving.value = true
  wechslerFehler.value = ''
  const { error } = await supabase.rpc('verein_beitrittsanfrage_stellen', { p_organisation_id: joinOrgId.value })
  joinSaving.value = false
  if (error) {
    wechslerFehler.value = error.message
    return
  }
  wechslerInfo.value = 'Beitrittsanfrage gesendet.'
  suche.value = ''
  treffer.value = []
  joinOrgId.value = ''
  beitretenOffen.value = false
}

const kontextLabel = computed(() => {
  if (props.lagerName && props.organisationName) return `${props.organisationName} · ${props.lagerName}`
  if (props.organisationName) return props.organisationName
  if (props.lagerName) return props.lagerName
  return 'Vereine'
})

const SNOOZE_KEY = 'stoela_profil_hinweis_snooze'
const hinweisSichtbar = ref(false)
const hinweisForm = ref({ vorname: '', nachname: '', telefon: '' })
const hinweisSpeichern = ref(false)

function snoozeBisAbgelaufen(): boolean {
  const bis = localStorage.getItem(SNOOZE_KEY)
  if (!bis) return true
  return new Date(bis) < new Date()
}

async function ladeProfil() {
  if (!session.value) {
    profil.value = null
    hinweisSichtbar.value = false
    return
  }
  const { data } = await supabase
    .from('profiles')
    .select('vorname, nachname, telefon')
    .eq('id', session.value.user.id)
    .single()
  profil.value = data
  const fehlt = !data?.vorname?.trim() || !data?.nachname?.trim() || !data?.telefon?.trim()
  hinweisSichtbar.value = fehlt && snoozeBisAbgelaufen()
  if (hinweisSichtbar.value) {
    hinweisForm.value = {
      vorname: data?.vorname ?? '',
      nachname: data?.nachname ?? '',
      telefon: data?.telefon ?? '',
    }
  }
}

async function hinweisSpeichernHandler() {
  if (!session.value) return
  hinweisSpeichern.value = true
  const { error } = await supabase
    .from('profiles')
    .update({
      vorname: hinweisForm.value.vorname.trim() || null,
      nachname: hinweisForm.value.nachname.trim() || null,
      telefon: hinweisForm.value.telefon.trim() || null,
    })
    .eq('id', session.value.user.id)
  hinweisSpeichern.value = false
  if (error) return
  hinweisSichtbar.value = false
  await ladeProfil()
}

function hinweisSpaeter() {
  const bis = new Date()
  bis.setMonth(bis.getMonth() + 1)
  localStorage.setItem(SNOOZE_KEY, bis.toISOString())
  hinweisSichtbar.value = false
}

onMounted(ladeProfil)
watch(session, ladeProfil)

const kuerzel = computed(() => {
  const p = profil.value
  if (p?.vorname && p?.nachname) return `${p.vorname[0]}${p.nachname[0]}`.toUpperCase()
  if (p?.vorname) return p.vorname.slice(0, 2).toUpperCase()
  const email = session.value?.user.email ?? ''
  return email.slice(0, 2).toUpperCase()
})

async function logout() {
  await signOut()
  await router.push('/login')
}
</script>

<template>
  <header class="app-header">
    <div class="app-header-left">
      <button
        v-if="showNavToggle"
        type="button"
        class="burger-btn"
        aria-label="Navigation"
        :aria-expanded="navOpen"
        @click="$emit('toggleNav')"
      >
        <span class="burger-line" />
        <span class="burger-line" />
        <span class="burger-line" />
      </button>
      <h1 v-if="!showAlleLager" class="app-titel">Stöckli Lager</h1>
      <button v-if="session && showAlleLager" type="button" class="kontext-btn" @click="wechslerOeffnen">
        {{ kontextLabel }}
      </button>
      <button v-if="session" type="button" class="neu-btn" title="Verein oder Lager erstellen/beitreten" @click="wechslerOeffnen">+</button>
    </div>
    <div class="app-header-right">
      <FeedbackButton v-if="session" />
      <router-link v-if="session?.user.email?.toLowerCase() === 'manuelzeltner@gmail.com'" to="/feedback" class="feedback-export-link" title="Feedback-Übersicht / Export">📋</router-link>
      <span class="profil-kuerzel" :title="session?.user.email ?? ''">{{ kuerzel }}</span>
      <button type="button" class="secondary logout-btn" @click="logout">Logout</button>
    </div>
  </header>
  <div v-if="hinweisSichtbar" class="profil-hinweis">
    <div class="profil-hinweis-inner">
      <div class="profil-hinweis-text">
        <strong>Dein Profil ist unvollständig.</strong>
        <span>Vorname, Nachname und Telefon werden für Leiter-/Ämtli-Zuweisungen benötigt.</span>
      </div>
      <form class="profil-hinweis-form" @submit.prevent="hinweisSpeichernHandler">
        <input v-model="hinweisForm.vorname" placeholder="Vorname" required />
        <input v-model="hinweisForm.nachname" placeholder="Nachname" required />
        <input v-model="hinweisForm.telefon" placeholder="Telefon" required />
        <button type="submit" :disabled="hinweisSpeichern">{{ hinweisSpeichern ? 'Speichere…' : 'Speichern' }}</button>
        <button type="button" class="secondary" @click="hinweisSpaeter">Diesen Monat nicht mehr anzeigen</button>
      </form>
    </div>
  </div>

  <AppDialog :open="wechslerOffen" titel="Verein &amp; Lager" @close="wechslerOffen = false">
    <p v-if="!vereineGeladen" class="hint">Lade…</p>
    <template v-else>
      <template v-if="meineVereine.length">
        <h3>Meine Vereine</h3>
        <ul class="wechsler-liste">
          <li v-for="v in meineVereine" :key="v.organisation_id">
            <button type="button" class="wechsler-item" @click="zuVerein(v.organisation_id)">
              {{ v.name }}
              <span class="hint klein">{{ v.meine_rolle }}</span>
            </button>
            <button
              v-if="v.meine_rolle === 'leitung' || v.meine_rolle === 'admin'"
              type="button"
              class="secondary klein-btn"
              @click="neuesLagerBei(v.organisation_id)"
            >
              + Lager
            </button>
          </li>
        </ul>
      </template>

      <div class="wechsler-aktionen">
        <button type="button" class="secondary" @click="neuVereinOffen = !neuVereinOffen; beitretenOffen = false">
          Neuen Verein erstellen
        </button>
        <button type="button" class="secondary" @click="beitretenOffen = !beitretenOffen; neuVereinOffen = false">
          Verein beitreten
        </button>
      </div>

      <form v-if="neuVereinOffen" class="inline-form" @submit.prevent="vereinErstellen">
        <input v-model="neuVereinForm.name" placeholder="Vereinsname" required />
        <button type="submit" :disabled="neuVereinSpeichern">{{ neuVereinSpeichern ? 'Erstelle…' : 'Erstellen' }}</button>
      </form>

      <div v-if="beitretenOffen" class="inline-form">
        <input v-model="suche" placeholder="Verein suchen…" @input="sucheVereine" />
        <div v-if="treffer.length" class="wechsler-treffer">
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
        <button type="button" :disabled="!joinOrgId || joinSaving" @click="beitrittAnfragen">
          {{ joinSaving ? 'Sende…' : 'Beitrittsanfrage senden' }}
        </button>
      </div>

      <p v-if="wechslerInfo" class="ok">{{ wechslerInfo }}</p>
      <p v-if="wechslerFehler" class="error">{{ wechslerFehler }}</p>
    </template>
  </AppDialog>
</template>

<style scoped>
.app-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  width: 100%;
  padding: 0.65rem 1.25rem;
  box-sizing: border-box;
}
.app-header-left {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  min-width: 0;
}
.burger-btn {
  display: none;
  flex-direction: column;
  justify-content: center;
  gap: 4px;
  width: 2.25rem;
  height: 2.25rem;
  padding: 0.4rem;
  border-radius: var(--radius-md);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  color: var(--color-text);
}
.burger-line {
  display: block;
  height: 2px;
  width: 100%;
  background: currentColor;
  border-radius: 1px;
}
.app-titel {
  margin: 0;
  font-size: 1.15rem;
  font-weight: 700;
}
.kontext-btn {
  display: inline-flex;
  align-items: center;
  min-width: 0;
  max-width: 40vw;
  flex-shrink: 1;
  font-weight: 700;
  font-size: 0.9rem;
  color: var(--color-text);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 0.45rem 0.75rem;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.kontext-btn:hover { background: var(--color-surface-muted); }
.neu-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  width: 2.1rem;
  height: 2.1rem;
  font-size: 1.2rem;
  font-weight: 700;
  line-height: 1;
  color: #fdfbf3;
  background: var(--color-accent);
  border: 2px solid var(--color-accent);
  border-radius: var(--radius-md);
}
.neu-btn:hover { background: var(--color-accent-hover); border-color: var(--color-accent-hover); }
.wechsler-liste { list-style: none; margin: 0.4rem 0 1rem; padding: 0; display: flex; flex-direction: column; gap: 0.4rem; }
.wechsler-liste li { display: flex; align-items: center; gap: 0.5rem; }
.wechsler-item {
  flex: 1;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 0.5rem;
  text-align: left;
  border: 1px solid var(--color-border);
  background: var(--color-surface);
  color: var(--color-text);
  border-radius: var(--radius-sm);
  padding: 0.5rem 0.7rem;
}
.wechsler-item:hover { background: var(--color-surface-muted); }
.wechsler-aktionen { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 0.5rem; }
.wechsler-treffer { display: grid; gap: 0.3rem; margin: 0.4rem 0; }
.treffer-item {
  text-align: left;
  border: 1px solid var(--color-border);
  background: var(--color-surface);
  color: var(--color-text);
  border-radius: var(--radius-sm);
  padding: 0.4rem 0.6rem;
}
.treffer-item.aktiv { border-color: var(--color-accent); }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: center; margin-top: 0.6rem; }
.klein-btn { font-size: 0.78rem; padding: 0.3rem 0.6rem; }
.ok { color: #2e7d32; }
.error { color: var(--color-danger); }
.hint { color: var(--color-text-muted); font-size: 0.85rem; }
.hint.klein { font-size: 0.78rem; }
.app-header-right {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  flex-shrink: 0;
}
.profil-kuerzel {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2rem;
  height: 2rem;
  border-radius: 50%;
  background: var(--color-accent);
  color: #fdfbf3;
  font-size: 0.78rem;
  font-weight: 700;
  letter-spacing: 0.02em;
}
.logout-btn {
  font-size: 0.82rem;
  padding: 0.35rem 0.65rem;
}
.feedback-export-link {
  display: inline-flex; align-items: center; justify-content: center;
  width: 2rem; height: 2rem; border-radius: 50%; border: 1px solid var(--color-border);
  text-decoration: none; font-size: 1rem;
}
.feedback-export-link:hover { background: var(--color-surface-muted); }
@media (max-width: 768px) {
  .burger-btn { display: flex; }
  .kontext-btn { max-width: 45vw; font-size: 0.82rem; padding: 0.4rem 0.6rem; }
}
.profil-hinweis {
  width: 100%;
  background: #fdf3e0;
  border-bottom: 1px solid #c98a3f;
  box-sizing: border-box;
}
.profil-hinweis-inner {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.6rem 1rem;
  padding: 0.55rem 1.25rem;
}
.profil-hinweis-text {
  display: flex;
  flex-direction: column;
  gap: 0.1rem;
  font-size: 0.85rem;
  min-width: 200px;
}
.profil-hinweis-text span { color: var(--color-text-muted); }
.profil-hinweis-form {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  align-items: center;
  flex: 1;
}
.profil-hinweis-form input {
  min-width: 130px;
  flex: 1;
  font-size: 0.85rem;
  padding: 0.35rem 0.5rem;
}
.profil-hinweis-form button {
  font-size: 0.8rem;
  padding: 0.35rem 0.65rem;
  white-space: nowrap;
}
</style>
