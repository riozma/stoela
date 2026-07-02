<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
import { useGooglePlaces } from '../composables/useGooglePlaces'
import AppHeader from '../components/AppHeader.vue'

interface Lager {
  id: string
  jahr: number
  name: string
  ort: string | null
  start_datum: string | null
  end_datum: string | null
  status: string
}

const { session, setPassword } = useAuth()
const router = useRouter()

const kontoOffen = ref(false)
const neuesPasswort = ref('')
const kontoNachricht = ref('')
const kontoError = ref('')
const kontoSaving = ref(false)

async function passwortSetzen() {
  kontoError.value = ''
  kontoNachricht.value = ''
  kontoSaving.value = true
  try {
    await setPassword(neuesPasswort.value)
    kontoNachricht.value = 'Passwort gesetzt. Du kannst dich künftig damit einloggen.'
    neuesPasswort.value = ''
  } catch (e) {
    kontoError.value = e instanceof Error ? e.message : 'Passwort konnte nicht gesetzt werden.'
  } finally {
    kontoSaving.value = false
  }
}

const lager = ref<Lager[]>([])
const loading = ref(true)
const error = ref('')

const naechstesJahr = new Date().getFullYear() + 1
const form = ref({
  jahr: naechstesJahr,
  name: `Stöckli-Lager ${naechstesJahr}`,
  ort: '',
  ort_lat: null as number | null,
  ort_lng: null as number | null,
  ort_place_id: null as string | null,
  start_datum: '',
  end_datum: '',
})
const saving = ref(false)

const { attachAutocomplete } = useGooglePlaces()
const ortInput = ref<HTMLInputElement | null>(null)

onMounted(() => {
  if (ortInput.value) {
    attachAutocomplete(ortInput.value, (gewaehlt) => {
      form.value.ort = gewaehlt.adresse
      form.value.ort_lat = gewaehlt.lat
      form.value.ort_lng = gewaehlt.lng
      form.value.ort_place_id = gewaehlt.placeId
    })
  }
})

async function ladeLager() {
  loading.value = true
  error.value = ''

  if (!session.value?.user.id) {
    lager.value = []
    loading.value = false
    return
  }

  const uid = session.value.user.id

  const { data, error: fetchError } = await supabase.rpc('list_meine_lager')

  if (!fetchError) {
    lager.value = data ?? []
  } else {
    // Fallback falls RPC noch nicht migriert: nur eigene Team-Lager laden
    const { data: teamRows, error: teamError } = await supabase
      .from('lager_leiter')
      .select('lager_id')
      .eq('profile_id', uid)
      .eq('status', 'bestaetigt')

    if (teamError) {
      error.value = teamError.message
      loading.value = false
      return
    }

    const ids = new Set(teamRows?.map((r) => r.lager_id) ?? [])
    const { data: owned } = await supabase.from('lager').select('id').eq('created_by', uid)
    for (const row of owned ?? []) ids.add(row.id)

    if (!ids.size) {
      lager.value = []
      loading.value = false
      return
    }

    const { data: fallback, error: fbError } = await supabase
      .from('lager')
      .select('id, jahr, name, ort, start_datum, end_datum, status')
      .in('id', [...ids])
      .order('jahr', { ascending: false })

    if (fbError) error.value = fbError.message
    else lager.value = fallback ?? []
  }

  loading.value = false

  // Einziges kommendes Lager → direkt zum Dashboard
  const heute = new Date().toISOString().slice(0, 10)
  const kommende = lager.value.filter((l) => {
    if (l.status === 'archiviert' || l.status === 'abgeschlossen') return false
    if (l.end_datum && l.end_datum < heute) return false
    return true
  })
  if (kommende.length === 1) {
    await router.replace(`/lager/${kommende[0].id}/dashboard`)
  }
}

async function erstellen() {
  error.value = ''
  saving.value = true
  const { data: neuesLager, error: insertError } = await supabase
    .from('lager')
    .insert({
      jahr: form.value.jahr,
      name: form.value.name,
      ort: form.value.ort || null,
      ort_lat: form.value.ort_lat,
      ort_lng: form.value.ort_lng,
      ort_place_id: form.value.ort_place_id,
      start_datum: form.value.start_datum || null,
      end_datum: form.value.end_datum || null,
      status: 'anmeldung_offen',
      created_by: session.value?.user.id ?? null,
    })
    .select('id')
    .single()

  if (insertError) {
    error.value = insertError.message
    saving.value = false
    return
  }

  // Ersteller/in wird automatisch bestätigtes Teammitglied dieses Lagers
  if (session.value) {
    await supabase.from('lager_leiter').insert({
      lager_id: neuesLager.id,
      profile_id: session.value.user.id,
      rolle: 'lagerleitung',
      status: 'bestaetigt',
    })
  }

  saving.value = false
  form.value.name = `Stöckli-Lager ${form.value.jahr + 1}`
  form.value.jahr += 1
  form.value.ort = ''
  form.value.ort_lat = null
  form.value.ort_lng = null
  form.value.ort_place_id = null
  form.value.start_datum = ''
  form.value.end_datum = ''
  await ladeLager()
}

onMounted(ladeLager)
</script>

<template>
  <div class="uebersicht-page">
    <div class="top-full">
      <AppHeader :show-alle-lager="false" />
    </div>
    <main>

    <section v-if="kontoOffen">
      <h2>Konto</h2>
      <form @submit.prevent="passwortSetzen">
        <label>
          Neues Passwort
          <input v-model="neuesPasswort" type="password" required minlength="6" autocomplete="new-password" />
        </label>
        <button type="submit" :disabled="kontoSaving">
          {{ kontoSaving ? 'Speichere...' : 'Passwort setzen' }}
        </button>
      </form>
      <p v-if="kontoNachricht">{{ kontoNachricht }}</p>
      <p v-if="kontoError" class="error">{{ kontoError }}</p>
    </section>

    <section>
      <div class="section-kopf">
        <h2>Deine Lager</h2>
        <button class="secondary" @click="kontoOffen = !kontoOffen">Konto</button>
      </div>
      <p class="hint">Klicke auf ein Lager, um Programm, Leiter, Gruppen und Ämtli zu verwalten.</p>
      <p v-if="loading">Lade...</p>
      <div v-else-if="lager.length" class="lager-karten">
        <article
          v-for="l in lager"
          :key="l.id"
          class="lager-karte"
          @click="router.push(`/lager/${l.id}/dashboard`)"
        >
          <strong>{{ l.name }}</strong>
          <span class="meta">{{ l.jahr }} · {{ l.status.replace('_', ' ') }}</span>
          <span v-if="l.ort" class="meta">{{ l.ort }}</span>
          <span v-if="l.start_datum" class="meta">{{ l.start_datum }} – {{ l.end_datum ?? '?' }}</span>
        </article>
      </div>
      <p v-else class="leer">Noch kein Lager – unten erstellen oder aus eCamp importieren.</p>
    </section>

    <section>
      <h2>Neues Lager</h2>
      <p class="hint">
        Oder <router-link to="/lager/import">aus eCamp-PDF importieren</router-link> (Blöcke werden automatisch übernommen).
      </p>
      <form @submit.prevent="erstellen">
        <label>
          Jahr
          <input v-model.number="form.jahr" type="number" required min="2020" />
        </label>
        <label>
          Name
          <input v-model="form.name" type="text" required />
        </label>
        <label>
          Ort
          <input ref="ortInput" v-model="form.ort" type="text" placeholder="Adresse eingeben..." />
        </label>
        <label>
          Start
          <input v-model="form.start_datum" type="date" />
        </label>
        <label>
          Ende
          <input v-model="form.end_datum" type="date" />
        </label>
        <button type="submit" :disabled="saving">
          {{ saving ? 'Speichere...' : 'Lager erstellen' }}
        </button>
      </form>
      <p v-if="error" class="error">{{ error }}</p>
    </section>
    </main>
  </div>
</template>

<style scoped>
.uebersicht-page { min-height: 100vh; }
.top-full {
  position: sticky;
  top: 0;
  z-index: 100;
  width: 100%;
  background: var(--color-surface);
  border-bottom: 1px solid var(--color-border);
  margin-bottom: 1rem;
  box-shadow: 0 1px 0 rgba(0, 0, 0, 0.04);
}
main {
  max-width: 960px;
  margin: 0 auto;
  padding: 0 1rem 2rem;
}
.section-kopf {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  margin-bottom: 0.25rem;
}
.section-kopf h2 { margin: 0; }
form {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 0.75rem;
  align-items: end;
  margin-bottom: 1rem;
}
label {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  font-size: 0.85rem;
  color: var(--color-text-muted);
}
table {
  width: 100%;
  border-collapse: collapse;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  overflow: hidden;
}
th,
td {
  text-align: left;
  padding: 0.5rem 0.75rem;
  border-bottom: 1px solid var(--color-border);
}
th {
  color: var(--color-text-muted);
  font-weight: 700;
  font-size: 0.85rem;
}
.lager-karten { display: grid; gap: 0.65rem; margin-bottom: 2rem; }
.lager-karte {
  padding: 1rem 1.1rem;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  cursor: pointer;
}
.lager-karte:hover { background: var(--color-surface-muted); }
.lager-karte strong { display: block; font-size: 1.05rem; margin-bottom: 0.35rem; }
.lager-karte .meta { display: block; font-size: 0.85rem; color: var(--color-text-muted); }
.leer { color: var(--color-text-muted); margin-bottom: 2rem; }
.error {
  color: var(--color-danger);
}
.hint {
  font-size: 0.85rem;
  color: var(--color-text-muted);
  margin-top: -0.5rem;
  margin-bottom: 1rem;
}
</style>
