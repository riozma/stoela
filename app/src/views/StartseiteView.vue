<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { supabase } from '../supabaseClient'
import AppHeader from '../components/AppHeader.vue'

interface VereinMitgliedschaft {
  organisation_id: string
  mein_status: 'angefragt' | 'mitglied' | 'abgelehnt'
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

const hatVerein = ref(false)
const offeneAnfragen = ref<string[]>([])

const vereinForm = ref({ name: '' })
const vereinSaving = ref(false)

const suche = ref('')
const treffer = ref<OrganisationTreffer[]>([])
const joinOrgId = ref('')
const joinSaving = ref(false)

function slugify(text: string) {
  return text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '')
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
  const vereine = (meine ?? []) as VereinMitgliedschaft[]

  if (vereine.some((v) => v.mein_status === 'mitglied')) {
    await router.replace('/organisation')
    return
  }

  hatVerein.value = false
  offeneAnfragen.value = vereine.filter((v) => v.mein_status === 'angefragt').map((v) => v.organisation_id)
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
  await router.push(`/organisation?org=${org.id}&neu=lager`)
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

    <main v-if="!laden">
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
        <p v-if="offeneAnfragen.length" class="hint">Du hast bereits eine offene Beitrittsanfrage gesendet.</p>

        <h3>Oder: eigenen Verein erstellen</h3>
        <form class="inline-form" @submit.prevent="vereinErstellen">
          <input v-model="vereinForm.name" placeholder="Vereinsname" required />
          <button type="submit" :disabled="vereinSaving">{{ vereinSaving ? 'Erstelle…' : 'Verein erstellen' }}</button>
        </form>
      </section>

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
main { max-width: 640px; margin: 0 auto; padding: 1rem 1.25rem 2rem; }
.karte {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 1rem 1.15rem;
  margin-bottom: 0.9rem;
}
.einstieg-karte { border-color: var(--color-accent); border-width: 2px; padding: 1.25rem 1.4rem; margin-top: 2rem; }
.einstieg-karte h2 { font-size: 1.3rem; margin: 0 0 0.45rem; }
.einstieg-karte h3 { margin: 1.25rem 0 0.5rem; font-size: 1rem; }
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
