<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'

interface Iban {
  id: string
  iban: string
  bezeichnung: string | null
}

interface QuittungDatei {
  id: string
  storage_path: string
  dateiname: string | null
}

interface Quittung {
  id: string
  betrag: number
  zweck: string
  status: 'pending' | 'bezahlt' | 'abgelehnt'
  ablehnungsgrund: string | null
  bearbeitet_am: string | null
  created_at: string
  einreicher_id: string
  iban_id: string
  profile_ibans: Iban | null
  profiles: { vorname: string | null; nachname: string | null; email: string } | null
  quittung_dateien: QuittungDatei[]
}

const props = defineProps<{
  lagerId: string
  userId: string
  istKassier: boolean
}>()

const quittungen = ref<Quittung[]>([])
const ibans = ref<Iban[]>([])
const fehler = ref('')
const nachricht = ref('')
const speichern = ref(false)
const ansicht = ref<'meine' | 'kassier'>(props.istKassier ? 'kassier' : 'meine')

const form = ref({
  betrag: '',
  zweck: '',
  ibanId: '',
  neueIban: '',
  neueIbanBezeichnung: '',
})

const bearbeitung = ref<{ id: string; betrag: string; zweck: string } | null>(null)
const ablehnung = ref<{ id: string; grund: string } | null>(null)
const dateiInput = ref<HTMLInputElement | null>(null)
const ausgewaehlteDateien = ref<File[]>([])

const meineQuittungen = computed(() => quittungen.value.filter((q) => q.einreicher_id === props.userId))

const statusIcon: Record<Quittung['status'], string> = {
  pending: '🟡',
  bezahlt: '✅',
  abgelehnt: '🔴',
}

const statusLabel: Record<Quittung['status'], string> = {
  pending: 'Ausstehend',
  bezahlt: 'Bezahlt',
  abgelehnt: 'Abgelehnt',
}

function formatBetrag(b: number) {
  return new Intl.NumberFormat('de-CH', { style: 'currency', currency: 'CHF' }).format(b)
}

function formatDatum(iso: string) {
  return new Intl.DateTimeFormat('de-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(iso))
}

function einreicherName(q: Quittung) {
  const p = q.profiles
  if (p?.vorname) return `${p.vorname} ${p.nachname ?? ''}`.trim()
  return p?.email ?? 'Unbekannt'
}

async function laden() {
  const [{ data: ibanData }, { data: qData }] = await Promise.all([
    supabase.from('profile_ibans').select('id, iban, bezeichnung').eq('profile_id', props.userId).order('created_at'),
    supabase
      .from('quittungen')
      .select(`
        id, betrag, zweck, status, ablehnungsgrund, bearbeitet_am, created_at, einreicher_id, iban_id,
        profile_ibans ( id, iban, bezeichnung ),
        profiles:einreicher_id ( vorname, nachname, email ),
        quittung_dateien ( id, storage_path, dateiname )
      `)
      .eq('lager_id', props.lagerId)
      .order('created_at', { ascending: false }),
  ])
  ibans.value = ibanData ?? []
  quittungen.value = (qData ?? []).map((row: any) => ({
    ...row,
    profile_ibans: Array.isArray(row.profile_ibans) ? row.profile_ibans[0] : row.profile_ibans,
    profiles: Array.isArray(row.profiles) ? row.profiles[0] : row.profiles,
    quittung_dateien: row.quittung_dateien ?? [],
  }))
  if (ibans.value.length && !form.value.ibanId) form.value.ibanId = ibans.value[0].id
}

onMounted(laden)

async function ibanHinzufuegen() {
  fehler.value = ''
  const iban = form.value.neueIban.replace(/\s/g, '').toUpperCase()
  if (!iban) { fehler.value = 'IBAN eingeben.'; return }
  const { data, error } = await supabase
    .from('profile_ibans')
    .insert({ profile_id: props.userId, iban, bezeichnung: form.value.neueIbanBezeichnung || null })
    .select('id, iban, bezeichnung')
    .single()
  if (error) { fehler.value = error.message; return }
  ibans.value.push(data)
  form.value.ibanId = data.id
  form.value.neueIban = ''
  form.value.neueIbanBezeichnung = ''
}

async function ibanLoeschen(id: string) {
  if (!confirm('IBAN wirklich löschen?')) return
  await supabase.from('profile_ibans').delete().eq('id', id)
  ibans.value = ibans.value.filter((i) => i.id !== id)
  if (form.value.ibanId === id) form.value.ibanId = ibans.value[0]?.id ?? ''
}

function dateienAuswaehlen(e: Event) {
  const input = e.target as HTMLInputElement
  ausgewaehlteDateien.value = input.files ? [...input.files] : []
}

async function uploadDateien(quittungId: string, files: File[]) {
  for (const file of files) {
    const path = `${props.userId}/${quittungId}/${Date.now()}-${file.name}`
    const { error: upErr } = await supabase.storage.from('quittungen').upload(path, file)
    if (upErr) throw upErr
    await supabase.from('quittung_dateien').insert({
      quittung_id: quittungId,
      storage_path: path,
      dateiname: file.name,
    })
  }
}

async function einreichen() {
  fehler.value = ''
  nachricht.value = ''
  speichern.value = true

  let ibanId = form.value.ibanId
  if (!ibanId && form.value.neueIban) {
    await ibanHinzufuegen()
    ibanId = form.value.ibanId
  }
  if (!ibanId) {
    fehler.value = 'Bitte IBAN angeben oder auswählen.'
    speichern.value = false
    return
  }
  if (!ausgewaehlteDateien.value.length) {
    fehler.value = 'Mindestens ein Bild der Quittung hochladen.'
    speichern.value = false
    return
  }

  const { data: q, error } = await supabase
    .from('quittungen')
    .insert({
      lager_id: props.lagerId,
      einreicher_id: props.userId,
      iban_id: ibanId,
      betrag: Number(form.value.betrag),
      zweck: form.value.zweck,
    })
    .select('id')
    .single()

  if (error || !q) {
    fehler.value = error?.message ?? 'Fehler beim Speichern'
    speichern.value = false
    return
  }

  try {
    await uploadDateien(q.id, ausgewaehlteDateien.value)
  } catch (e: any) {
    fehler.value = e.message ?? 'Upload fehlgeschlagen'
    await supabase.from('quittungen').delete().eq('id', q.id)
    speichern.value = false
    return
  }

  form.value.betrag = ''
  form.value.zweck = ''
  ausgewaehlteDateien.value = []
  if (dateiInput.value) dateiInput.value.value = ''
  nachricht.value = 'Quittung eingereicht.'
  speichern.value = false
  await laden()
}

async function speichereBearbeitung() {
  if (!bearbeitung.value) return
  fehler.value = ''
  const { error } = await supabase
    .from('quittungen')
    .update({ betrag: Number(bearbeitung.value.betrag), zweck: bearbeitung.value.zweck })
    .eq('id', bearbeitung.value.id)
    .eq('status', 'pending')
  if (error) { fehler.value = error.message; return }
  bearbeitung.value = null
  await laden()
}

async function statusZuruecksetzen(id: string) {
  if (!props.istKassier) return
  if (!confirm('Status auf «ausstehend» zurücksetzen?')) return
  const { error } = await supabase.from('quittungen').update({
    status: 'pending',
    ablehnungsgrund: null,
    bearbeitet_von: null,
    bearbeitet_am: null,
  }).eq('id', id)
  if (error) { fehler.value = error.message; return }
  await laden()
}

async function statusSetzen(id: string, status: 'bezahlt' | 'abgelehnt', grund?: string) {
  const payload: Record<string, unknown> = {
    status,
    bearbeitet_von: props.userId,
    bearbeitet_am: new Date().toISOString(),
    ablehnungsgrund: status === 'abgelehnt' ? grund ?? null : null,
  }
  const { error } = await supabase.from('quittungen').update(payload).eq('id', id)
  if (error) { fehler.value = error.message; return }
  ablehnung.value = null
  await laden()
}

async function dateiUrl(path: string) {
  const { data } = await supabase.storage.from('quittungen').createSignedUrl(path, 3600)
  return data?.signedUrl ?? '#'
}

async function oeffneDatei(path: string) {
  const url = await dateiUrl(path)
  if (url !== '#') window.open(url, '_blank')
}

async function downloadAlle(q: Quittung) {
  for (const d of q.quittung_dateien) {
    await oeffneDatei(d.storage_path)
  }
}

async function loeschen(id: string) {
  if (!confirm('Quittung wirklich löschen?')) return
  await supabase.from('quittungen').delete().eq('id', id).eq('status', 'pending')
  await laden()
}
</script>

<template>
  <section class="quittungen">
    <header>
      <h2>Quittungen</h2>
      <nav v-if="istKassier" class="sub-tabs">
        <button :class="{ aktiv: ansicht === 'meine' }" @click="ansicht = 'meine'">Meine Einreichungen</button>
        <button :class="{ aktiv: ansicht === 'kassier' }" @click="ansicht = 'kassier'">Kassier-Übersicht</button>
      </nav>
    </header>

    <p v-if="fehler" class="error">{{ fehler }}</p>
    <p v-if="nachricht" class="hint ok">{{ nachricht }}</p>

    <!-- Einreichen -->
    <div v-if="ansicht === 'meine'" class="einreichen-box">
      <h3>Quittung einreichen</h3>
      <p class="hint">Beim ersten Mal IBAN angeben – danach kannst du gespeicherte IBANs wählen.</p>

      <div v-if="ibans.length" class="iban-liste">
        <label v-for="i in ibans" :key="i.id" class="iban-option">
          <input v-model="form.ibanId" type="radio" :value="i.id" />
          {{ i.bezeichnung ? `${i.bezeichnung}: ` : '' }}{{ i.iban }}
          <button type="button" class="secondary klein" @click.stop="ibanLoeschen(i.id)">Löschen</button>
        </label>
      </div>

      <details class="neue-iban">
        <summary>Neue IBAN erfassen</summary>
        <div class="inline-form">
          <input v-model="form.neueIban" placeholder="CH..." />
          <input v-model="form.neueIbanBezeichnung" placeholder="Bezeichnung (optional)" />
          <button type="button" class="secondary" @click="ibanHinzufuegen">IBAN speichern</button>
        </div>
      </details>

      <form class="form-grid" @submit.prevent="einreichen">
        <label>Betrag (CHF) <input v-model="form.betrag" type="number" step="0.05" min="0" required /></label>
        <label class="full">Verwendungszweck <input v-model="form.zweck" required placeholder="Wofür wurde es verwendet?" /></label>
        <label class="full">
          Bilder (Quittung)
          <input ref="dateiInput" type="file" accept="image/*" multiple @change="dateienAuswaehlen" />
        </label>
        <p v-if="ausgewaehlteDateien.length" class="hint">{{ ausgewaehlteDateien.length }} Datei(en) ausgewählt</p>
        <button type="submit" :disabled="speichern">{{ speichern ? 'Reiche ein...' : 'Quittung einreichen' }}</button>
      </form>

      <h3>Meine Quittungen</h3>
      <div v-if="meineQuittungen.length" class="q-liste">
        <article v-for="q in meineQuittungen" :key="q.id" class="q-karte" :class="'status-' + q.status">
          <div class="q-kopf">
            <span class="status">{{ statusIcon[q.status] }} {{ statusLabel[q.status] }}</span>
            <strong>{{ formatBetrag(q.betrag) }}</strong>
          </div>
          <p>{{ q.zweck }}</p>
          <p class="meta">Eingereicht: {{ formatDatum(q.created_at) }}</p>
          <p v-if="q.bearbeitet_am" class="meta">Bearbeitet: {{ formatDatum(q.bearbeitet_am) }}</p>
          <p v-if="q.status === 'abgelehnt' && q.ablehnungsgrund" class="ablehnung">Grund: {{ q.ablehnungsgrund }}</p>

          <div v-if="bearbeitung?.id === q.id" class="bearbeitung">
            <input v-model="bearbeitung.betrag" type="number" step="0.05" />
            <input v-model="bearbeitung.zweck" />
            <button @click="speichereBearbeitung">Speichern</button>
            <button class="secondary" @click="bearbeitung = null">Abbrechen</button>
          </div>
          <div v-else class="aktionen">
            <button
              v-for="d in q.quittung_dateien"
              :key="d.id"
              class="secondary klein"
              @click="oeffneDatei(d.storage_path)"
            >
              📎 {{ d.dateiname ?? 'Anhang' }}
            </button>
            <button v-if="q.status === 'pending'" class="secondary klein" @click="bearbeitung = { id: q.id, betrag: String(q.betrag), zweck: q.zweck }">
              Bearbeiten
            </button>
            <button v-if="q.status === 'pending'" class="secondary klein" @click="loeschen(q.id)">Löschen</button>
          </div>
        </article>
      </div>
      <p v-else class="hint">Noch keine Quittungen eingereicht.</p>
    </div>

    <!-- Kassier -->
    <div v-if="ansicht === 'kassier' && istKassier" class="kassier-box">
      <h3>Alle Quittungen ({{ quittungen.length }})</h3>
      <div v-if="quittungen.length" class="q-liste">
        <article v-for="q in quittungen" :key="q.id" class="q-karte" :class="'status-' + q.status">
          <div class="q-kopf">
            <span class="status">{{ statusIcon[q.status] }} {{ statusLabel[q.status] }}</span>
            <strong>{{ formatBetrag(q.betrag) }}</strong>
          </div>
          <p><strong>{{ einreicherName(q) }}</strong> · {{ q.zweck }}</p>
          <p class="meta">IBAN: {{ q.profile_ibans?.iban ?? '–' }}</p>
          <p v-if="q.status === 'abgelehnt' && q.ablehnungsgrund" class="ablehnung">Abgelehnt: {{ q.ablehnungsgrund }}</p>

          <div class="aktionen">
            <button class="secondary klein" @click="downloadAlle(q)">Download</button>
            <template v-if="q.status === 'pending'">
              <button class="klein" @click="statusSetzen(q.id, 'bezahlt')">Als bezahlt markieren</button>
              <button class="secondary klein" @click="ablehnung = { id: q.id, grund: '' }">Ablehnen</button>
            </template>
            <button
              v-else
              class="secondary klein"
              @click="statusZuruecksetzen(q.id)"
            >
              Rückgängig (ausstehend)
            </button>
          </div>

          <div v-if="ablehnung?.id === q.id" class="ablehnung-form">
            <input v-model="ablehnung.grund" placeholder="Begründung..." required />
            <button @click="statusSetzen(q.id, 'abgelehnt', ablehnung.grund)">Ablehnung bestätigen</button>
            <button class="secondary" @click="ablehnung = null">Abbrechen</button>
          </div>
        </article>
      </div>
      <p v-else class="hint">Keine Quittungen vorhanden.</p>
    </div>
  </section>
</template>

<style scoped>
header { margin-bottom: 1rem; }
header h2 { margin: 0 0 0.5rem; }
.sub-tabs { display: flex; gap: 0.4rem; }
.sub-tabs button { font-size: 0.85rem; background: var(--color-surface); border: 1px solid var(--color-border); }
.sub-tabs button.aktiv { background: var(--color-accent); color: #fdfbf3; border-color: var(--color-accent); }
.einreichen-box, .kassier-box { margin-top: 1rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.hint.ok { color: var(--color-accent); }
.error { color: var(--color-danger); }
.iban-liste { margin: 0.75rem 0; }
.iban-option { display: flex; align-items: center; gap: 0.5rem; margin: 0.35rem 0; font-size: 0.9rem; }
.neue-iban { margin: 0.75rem 0; font-size: 0.9rem; }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 0.5rem; }
.form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 0.65rem; margin: 1rem 0; }
.form-grid label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.82rem; color: var(--color-text-muted); }
.form-grid .full { grid-column: 1 / -1; }
.q-liste { display: grid; gap: 0.75rem; margin-top: 1rem; }
.q-karte { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.85rem 1rem; }
.q-karte.status-pending { border-left: 4px solid #c98a3f; }
.q-karte.status-bezahlt { border-left: 4px solid #5a9a5a; }
.q-karte.status-abgelehnt { border-left: 4px solid var(--color-danger); }
.q-kopf { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.35rem; }
.meta { font-size: 0.8rem; color: var(--color-text-muted); margin: 0.2rem 0; }
.ablehnung { color: var(--color-danger); font-size: 0.88rem; }
.aktionen { display: flex; flex-wrap: wrap; gap: 0.4rem; margin-top: 0.5rem; }
.bearbeitung, .ablehnung-form { display: flex; flex-wrap: wrap; gap: 0.4rem; margin-top: 0.5rem; }
button.klein { font-size: 0.75rem; padding: 0.25rem 0.55rem; }
</style>
