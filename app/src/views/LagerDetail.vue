<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabaseClient'

interface Programmabschnitt {
  zeit: string | null
  programm: string
  verantwortlich: string | null
}
interface MaterialItem {
  name: string
  wer: string | null
}
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
}
interface Lager {
  id: string
  name: string
  jahr: number
  ort: string | null
}

const route = useRoute()
const lagerId = route.params.id as string

const lager = ref<Lager | null>(null)
const bloecke = ref<Block[]>([])
const loading = ref(true)
const error = ref('')

const ausgewaehlterTag = ref<string | null>(null)
const offenerBlock = ref<string | null>(null)

const tage = computed(() => {
  const einzigartig = new Set(bloecke.value.map((b) => b.tag).filter((t): t is string => !!t))
  return [...einzigartig].sort()
})

const blocksFuerTag = computed(() =>
  bloecke.value
    .filter((b) => b.tag === ausgewaehlterTag.value)
    .sort((a, b) => (a.start_zeit ?? '').localeCompare(b.start_zeit ?? '')),
)

const codeLabel: Record<Block['code'], string> = {
  LP: 'Lagerprogramm',
  LS: 'Lagersport',
  LA: 'Lageraktivität',
  ES: 'Essen',
}

function formatTag(tag: string) {
  const datum = new Date(tag + 'T00:00:00')
  return new Intl.DateTimeFormat('de-CH', { weekday: 'short', day: 'numeric', month: 'numeric' }).format(datum)
}

function formatZeit(zeit: string | null) {
  if (!zeit) return '–'
  const datum = new Date(zeit)
  if (Number.isNaN(datum.getTime())) return zeit
  return new Intl.DateTimeFormat('de-CH', { hour: '2-digit', minute: '2-digit' }).format(datum)
}

function toggleBlock(id: string) {
  offenerBlock.value = offenerBlock.value === id ? null : id
}

onMounted(async () => {
  loading.value = true

  const [{ data: lagerData, error: lagerError }, { data: bloeckeData, error: bloeckeError }] = await Promise.all([
    supabase.from('lager').select('id, name, jahr, ort').eq('id', lagerId).single(),
    supabase
      .from('programmbloecke')
      .select(
        'id, code, nummer, titel, tag, start_zeit, end_zeit, ort, verantwortlich, geschichte, sicherheitsueberlegungen, programmabschnitt, material, notizen',
      )
      .eq('lager_id', lagerId),
  ])

  if (lagerError || bloeckeError) {
    error.value = lagerError?.message ?? bloeckeError?.message ?? 'Lager konnte nicht geladen werden.'
    loading.value = false
    return
  }

  lager.value = lagerData
  bloecke.value = bloeckeData ?? []
  ausgewaehlterTag.value = tage.value[0] ?? null
  loading.value = false
})
</script>

<template>
  <main>
    <p><router-link to="/lager">← Zurück zur Übersicht</router-link></p>

    <p v-if="loading">Lade...</p>
    <p v-else-if="error" class="error">{{ error }}</p>

    <template v-else-if="lager">
      <h1>{{ lager.name }}</h1>
      <p class="hint" v-if="lager.ort">{{ lager.ort }}</p>

      <p v-if="!bloecke.length" class="hint">
        Noch keine Programmblöcke erfasst. Über den eCamp-PDF-Import lassen sich alle Blöcke auf einmal einlesen.
      </p>

      <nav v-else class="tage">
        <button
          v-for="tag in tage"
          :key="tag"
          :class="{ aktiv: tag === ausgewaehlterTag }"
          @click="ausgewaehlterTag = tag; offenerBlock = null"
        >
          {{ formatTag(tag) }}
        </button>
      </nav>

      <div v-if="blocksFuerTag.length" class="timetable">
        <template v-for="b in blocksFuerTag" :key="b.id">
          <div class="block-zeile" @click="toggleBlock(b.id)">
            <span class="zeit">{{ formatZeit(b.start_zeit) }}–{{ formatZeit(b.end_zeit) }}</span>
            <span class="code" :class="'code-' + b.code" :title="codeLabel[b.code]">{{ b.code }}</span>
            <span class="titel">{{ b.nummer ? b.nummer + ' ' : '' }}{{ b.titel }}</span>
            <span class="verantwortlich">{{ b.verantwortlich }}</span>
          </div>
          <div v-if="offenerBlock === b.id" class="block-detail">
            <p v-if="b.ort"><strong>Ort:</strong> {{ b.ort }}</p>
            <p v-if="b.geschichte"><strong>Geschichte:</strong> {{ b.geschichte }}</p>
            <p v-if="b.sicherheitsueberlegungen">
              <strong>Sicherheitsüberlegungen:</strong> {{ b.sicherheitsueberlegungen }}
            </p>

            <div v-if="b.programmabschnitt?.length">
              <strong>Programmabschnitt</strong>
              <table class="abschnitt-tabelle">
                <tbody>
                  <tr v-for="(a, i) in b.programmabschnitt" :key="i">
                    <td class="abschnitt-zeit">{{ a.zeit }}</td>
                    <td>{{ a.programm }}</td>
                    <td class="abschnitt-verantwortlich">{{ a.verantwortlich }}</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div v-if="b.material?.length">
              <strong>Material</strong>
              <ul class="material-liste">
                <li v-for="(m, i) in b.material" :key="i">{{ m.name }} <span v-if="m.wer">– {{ m.wer }}</span></li>
              </ul>
            </div>

            <p v-if="b.notizen"><strong>Notizen:</strong> {{ b.notizen }}</p>
          </div>
        </template>
      </div>
    </template>
  </main>
</template>

<style scoped>
main {
  max-width: 800px;
  margin: 2rem auto;
  padding: 0 1rem;
}
.hint {
  color: var(--color-text-muted);
  font-size: 0.9rem;
}
.tage {
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem;
  margin: 1rem 0;
}
.tage button {
  background: var(--color-surface);
  color: var(--color-text);
  border: 1px solid var(--color-border);
}
.tage button.aktiv {
  background: var(--color-accent);
  color: #fdfbf3;
  border-color: var(--color-accent);
}
.timetable {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  overflow: hidden;
}
.block-zeile {
  display: grid;
  grid-template-columns: 100px 40px 1fr 160px;
  gap: 0.75rem;
  align-items: center;
  padding: 0.6rem 0.9rem;
  border-bottom: 1px solid var(--color-border);
  cursor: pointer;
}
.block-zeile:hover {
  background: var(--color-surface-muted);
}
.zeit {
  font-size: 0.85rem;
  color: var(--color-text-muted);
  font-variant-numeric: tabular-nums;
}
.code {
  font-size: 0.7rem;
  font-weight: 700;
  text-align: center;
  padding: 0.2rem 0;
  border-radius: var(--radius-pill);
  color: #fdfbf3;
}
.code-LP {
  background: #6b7fa8;
}
.code-LS {
  background: var(--color-accent);
}
.code-LA {
  background: #c98a3f;
}
.code-ES {
  background: #8a7f68;
}
.titel {
  font-size: 0.95rem;
}
.verantwortlich {
  font-size: 0.8rem;
  color: var(--color-text-muted);
  text-align: right;
}
.block-detail {
  padding: 0.85rem 1.25rem 1.1rem;
  background: var(--color-surface-muted);
  border-bottom: 1px solid var(--color-border);
  font-size: 0.9rem;
}
.block-detail p {
  margin: 0.4rem 0;
}
.abschnitt-tabelle {
  width: 100%;
  border-collapse: collapse;
  margin: 0.4rem 0 0.8rem;
  font-size: 0.85rem;
}
.abschnitt-tabelle td {
  padding: 0.3rem 0.5rem 0.3rem 0;
  border-bottom: 1px solid var(--color-border);
  vertical-align: top;
}
.abschnitt-zeit {
  white-space: nowrap;
  color: var(--color-text-muted);
}
.abschnitt-verantwortlich {
  color: var(--color-text-muted);
  white-space: nowrap;
}
.material-liste {
  margin: 0.4rem 0 0.8rem;
  padding-left: 1.2rem;
}
.error {
  color: var(--color-danger);
}
</style>
