<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { supabase } from '../supabaseClient'
import { useAuth } from '../composables/useAuth'
import AppHeader from '../components/AppHeader.vue'
import WiesenKarte from '../components/lager/WiesenKarte.vue'

const props = defineProps<{ lagerId: string }>()

const router = useRouter()
const { session } = useAuth()

interface Kommentar {
  id: string
  autor_name: string
  text: string
  created_at: string
}

interface Wiese {
  id: string
  name: string
  lat: number | null
  lng: number | null
  status: string
  kommentare: Kommentar[]
  neuerKommentar: string
}

const wiesen = ref<Wiese[]>([])
const laden = ref(true)
const speichern = ref<string | null>(null)

const STATUS_LABELS: Record<string, string> = {
  offen: 'Noch angefragt',
  zusage: '✓ Zusage',
  abgelehnt: '✗ Abgelehnt',
  bedankt: '🍷 Bedankt',
}

function formatDatum(iso: string) {
  return new Intl.DateTimeFormat('de-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(iso))
}

async function laden_() {
  laden.value = true
  const { data: w } = await supabase
    .from('gelaendespielwiesen')
    .select('id, name, lat, lng, status')
    .eq('lager_id', props.lagerId)
    .order('created_at')

  const basis = w ?? []
  if (!basis.length) {
    wiesen.value = []
    laden.value = false
    return
  }

  const { data: kommentare } = await supabase
    .from('gelaendespielwiesen_kommentare')
    .select('id, wiese_id, autor_name, text, created_at')
    .in('wiese_id', basis.map((x) => x.id))
    .order('created_at')

  wiesen.value = basis.map((x) => ({
    ...x,
    kommentare: (kommentare ?? []).filter((k: any) => k.wiese_id === x.id),
    neuerKommentar: '',
  }))
  laden.value = false
}

onMounted(laden_)

async function kommentarSenden(wiese: Wiese) {
  const text = wiese.neuerKommentar.trim()
  if (!text || !session.value) return
  speichern.value = wiese.id

  const { data: profil } = await supabase
    .from('profiles')
    .select('vorname, nachname')
    .eq('id', session.value.user.id)
    .maybeSingle()
  const autorName = profil?.vorname
    ? `${profil.vorname} ${profil.nachname ?? ''}`.trim()
    : session.value.user.email?.split('@')[0] ?? 'Unbekannt'

  const { data } = await supabase
    .from('gelaendespielwiesen_kommentare')
    .insert({ wiese_id: wiese.id, profile_id: session.value.user.id, autor_name: autorName, text })
    .select('id, autor_name, text, created_at')
    .single()

  if (data) wiese.kommentare.push(data as Kommentar)
  wiese.neuerKommentar = ''
  speichern.value = null
}
</script>

<template>
  <div>
    <AppHeader />
    <main class="page">
      <button class="secondary klein" @click="router.push(`/lager/${lagerId}/dashboard`)">← Zum Dashboard</button>
      <h2>Spielwiesen</h2>
      <p class="hint">Vom Geländespielwiese-Ämtli erfasste Wiesen – hier nur zum Ansehen und Kommentieren.</p>

      <p v-if="laden" class="hint">Lade...</p>

      <template v-else>
        <WiesenKarte v-if="wiesen.length" :wiesen="wiesen" />

        <article v-for="w in wiesen" :key="w.id" class="wiese-karte">
          <header>
            <strong>{{ w.name }}</strong>
            <span class="status-pill" :class="'s-' + w.status">{{ STATUS_LABELS[w.status] ?? w.status }}</span>
          </header>

          <div class="kommentare">
            <div v-for="k in w.kommentare" :key="k.id" class="kommentar">
              <span class="kommentar-meta">{{ k.autor_name }} · {{ formatDatum(k.created_at) }}</span>
              <p>{{ k.text }}</p>
            </div>
            <p v-if="!w.kommentare.length" class="hint klein">Noch keine Kommentare.</p>
          </div>

          <form class="kommentar-form" @submit.prevent="kommentarSenden(w)">
            <input v-model="w.neuerKommentar" placeholder="Kommentar hinzufügen..." :disabled="speichern === w.id" />
            <button type="submit" :disabled="speichern === w.id || !w.neuerKommentar.trim()">Senden</button>
          </form>
        </article>

        <p v-if="!wiesen.length" class="hint">Noch keine Wiesen erfasst.</p>
      </template>
    </main>
  </div>
</template>

<style scoped>
.page { max-width: 720px; margin: 0 auto; padding: 1.25rem; }
.page h2 { margin: 0.75rem 0 0.25rem; }
.hint { color: var(--color-text-muted); font-size: 0.9rem; }
.hint.klein { font-size: 0.82rem; }
.wiese-karte {
  background: var(--color-surface); border: 1px solid var(--color-border);
  border-radius: var(--radius-md); padding: 0.85rem 1rem; margin-bottom: 1rem;
}
.wiese-karte header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.6rem; }
.status-pill { font-size: 0.75rem; padding: 0.2rem 0.5rem; border-radius: var(--radius-pill); font-weight: 600; white-space: nowrap; }
.s-offen { background: var(--color-surface-muted); color: var(--color-text-muted); }
.s-zusage { background: #e8f5e9; color: #2e7d32; }
.s-abgelehnt { background: #fdf6f4; color: var(--color-danger); }
.s-bedankt { background: #fdf8f0; color: #c98a3f; }
.kommentare { display: flex; flex-direction: column; gap: 0.5rem; margin-bottom: 0.6rem; }
.kommentar { border-left: 2px solid var(--color-border); padding-left: 0.6rem; }
.kommentar p { margin: 0.1rem 0 0; font-size: 0.9rem; }
.kommentar-meta { font-size: 0.75rem; color: var(--color-text-muted); }
.kommentar-form { display: flex; gap: 0.5rem; }
.kommentar-form input { flex: 1; }
button.klein { font-size: 0.75rem; padding: 0.2rem 0.5rem; }
</style>
