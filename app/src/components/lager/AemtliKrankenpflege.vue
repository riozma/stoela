<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import JSZip from 'jszip'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()

interface TnGesundheit {
  id: string
  vorname: string
  nachname: string
  status: string
  allergien: string | null
  medikamente: string | null
  gesundheit_bemerkungen: string | null
  essensgewohnheiten: string | null
  essensgewohnheiten_sonstiges: string | null
  sonstige_info: string | null
}

interface TnDokument {
  id: string
  anmeldung_tn_id: string
  typ: string
  storage_path: string
  dateiname: string
  url: string | null
}

const DOKUMENT_TYP_LABEL: Record<string, string> = {
  krankenkasse_vorne: 'Krankenkasse-Vorderseite',
  krankenkasse_hinten: 'Krankenkasse-Rückseite',
  impfung: 'Impfausweis',
}

const tnListe = ref<TnGesundheit[]>([])
const dokumente = ref<TnDokument[]>([])
const nurMitAngaben = ref(false)
const zipLaden = ref(false)

async function laden() {
  const { data } = await supabase
    .from('anmeldungen_tn')
    .select(
      'id, vorname, nachname, status, allergien, medikamente, gesundheit_bemerkungen, essensgewohnheiten, essensgewohnheiten_sonstiges, sonstige_info',
    )
    .eq('lager_id', props.lagerId)
    .order('nachname')
  tnListe.value = (data ?? []) as TnGesundheit[]

  const tnIds = tnListe.value.map((t) => t.id)
  if (!tnIds.length) {
    dokumente.value = []
    return
  }
  const { data: dok } = await supabase
    .from('tn_anmeldung_dokumente')
    .select('id, anmeldung_tn_id, typ, storage_path, dateiname')
    .in('anmeldung_tn_id', tnIds)

  const rows = (dok ?? []) as Omit<TnDokument, 'url'>[]
  const mitUrl: TnDokument[] = []
  for (const row of rows) {
    const { data: signed } = await supabase.storage.from('tn-anmeldungen').createSignedUrl(row.storage_path, 3600)
    mitUrl.push({ ...row, url: signed?.signedUrl ?? null })
  }
  dokumente.value = mitUrl
}

onMounted(laden)

function dokumenteFuer(tnId: string) {
  return dokumente.value.filter((d) => d.anmeldung_tn_id === tnId)
}

function impfungenFuer(tnId: string) {
  return dokumenteFuer(tnId).filter((d) => d.typ === 'impfung')
}

function dokFuer(tnId: string, typ: string) {
  return dokumenteFuer(tnId).find((d) => d.typ === typ) ?? null
}

async function zipHerunterladen() {
  if (!dokumente.value.length) return
  zipLaden.value = true
  const zip = new JSZip()
  const tnById = new Map(tnListe.value.map((t) => [t.id, t]))
  const impfCounter: Record<string, number> = {}

  for (const dok of dokumente.value) {
    const tn = tnById.get(dok.anmeldung_tn_id)
    if (!tn || !dok.url) continue
    const name = `${tn.nachname}_${tn.vorname}`.replace(/[^\w-]+/g, '_')
    const ext = dok.dateiname.includes('.') ? dok.dateiname.slice(dok.dateiname.lastIndexOf('.')) : ''
    let label = DOKUMENT_TYP_LABEL[dok.typ] ?? dok.typ
    if (dok.typ === 'impfung') {
      impfCounter[tn.id] = (impfCounter[tn.id] ?? 0) + 1
      label = `${label}_${impfCounter[tn.id]}`
    }
    try {
      const resp = await fetch(dok.url)
      const blob = await resp.blob()
      zip.file(`${name}_${label}${ext}`, blob)
    } catch {
      /* einzelne Datei überspringen bei Fehler */
    }
  }

  const inhalt = await zip.generateAsync({ type: 'blob' })
  const url = URL.createObjectURL(inhalt)
  const a = document.createElement('a')
  a.href = url
  a.download = `Krankenpflege_Dokumente_${props.aemtliName}.zip`
  a.click()
  URL.revokeObjectURL(url)
  zipLaden.value = false
}

function hatGesundheitsangaben(t: TnGesundheit) {
  return Boolean(
    t.allergien?.trim()
    || t.medikamente?.trim()
    || t.gesundheit_bemerkungen?.trim()
    || t.essensgewohnheiten?.trim()
    || t.essensgewohnheiten_sonstiges?.trim()
    || t.sonstige_info?.trim(),
  )
}

const angezeigt = computed(() =>
  nurMitAngaben.value ? tnListe.value.filter(hatGesundheitsangaben) : tnListe.value,
)

const mitMedikamenten = computed(() => tnListe.value.filter((t) => t.medikamente?.trim()))
const mitAllergien = computed(() => tnListe.value.filter((t) => t.allergien?.trim()))
const mitBemerkungen = computed(() => tnListe.value.filter((t) => t.gesundheit_bemerkungen?.trim()))
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <div class="stats">
      <span>{{ tnListe.length }} TN angemeldet</span>
      <span>{{ mitMedikamenten.length }} mit Medikamenten</span>
      <span>{{ mitAllergien.length }} mit Allergien</span>
      <span>{{ mitBemerkungen.length }} mit Gesundheitsbemerkungen</span>
    </div>
    <p class="hint hinweis-oben">Apotheke/Arzt vor Lager informieren. Impfausweise am Elternabend einsammeln.</p>
    <div class="filter-zeile">
      <label class="filter">
        <input v-model="nurMitAngaben" type="checkbox" />
        Nur TN mit Gesundheitsangaben anzeigen
      </label>
      <button type="button" class="secondary" :disabled="!dokumente.length || zipLaden" @click="zipHerunterladen">
        {{ zipLaden ? 'Erstelle ZIP…' : `Alle Dokumente als ZIP (${dokumente.length})` }}
      </button>
    </div>
    <table v-if="angezeigt.length" class="liste">
      <thead>
        <tr>
          <th>Name</th>
          <th>Status</th>
          <th>Allergien</th>
          <th>Medikamente</th>
          <th>Gesundheit</th>
          <th>Essen</th>
          <th>Sonstiges</th>
          <th>Dokumente</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="t in angezeigt" :key="t.id" :class="{ warn: hatGesundheitsangaben(t) }">
          <td>{{ t.vorname }} {{ t.nachname }}</td>
          <td>{{ t.status }}</td>
          <td>{{ t.allergien?.trim() || '–' }}</td>
          <td>{{ t.medikamente?.trim() || '–' }}</td>
          <td>{{ t.gesundheit_bemerkungen?.trim() || '–' }}</td>
          <td>
            {{ t.essensgewohnheiten?.trim() || '–' }}
            <span v-if="t.essensgewohnheiten_sonstiges?.trim()" class="klein">({{ t.essensgewohnheiten_sonstiges }})</span>
          </td>
          <td>{{ t.sonstige_info?.trim() || '–' }}</td>
          <td>
            <div v-if="dokumenteFuer(t.id).length" class="dok-thumbs">
              <a v-if="dokFuer(t.id, 'krankenkasse_vorne')" :href="dokFuer(t.id, 'krankenkasse_vorne')!.url!" target="_blank" rel="noopener" title="Krankenkasse Vorderseite">
                <img :src="dokFuer(t.id, 'krankenkasse_vorne')!.url!" alt="KK vorne" />
              </a>
              <a v-if="dokFuer(t.id, 'krankenkasse_hinten')" :href="dokFuer(t.id, 'krankenkasse_hinten')!.url!" target="_blank" rel="noopener" title="Krankenkasse Rückseite">
                <img :src="dokFuer(t.id, 'krankenkasse_hinten')!.url!" alt="KK hinten" />
              </a>
              <a v-for="(imp, i) in impfungenFuer(t.id)" :key="imp.id" :href="imp.url!" target="_blank" rel="noopener" :title="`Impfausweis ${i + 1}`">
                <img :src="imp.url!" alt="Impfausweis" />
              </a>
            </div>
            <span v-else class="hint klein">–</span>
          </td>
        </tr>
      </tbody>
    </table>
    <p v-else class="hint">Noch keine Gesundheitsangaben aus der TN-Anmeldung.</p>
    <p class="hint">Daten stammen aus der TN-Anmeldung.</p>
  </AemtliShell>
</template>

<style scoped>
.stats { display: flex; flex-wrap: wrap; gap: 0.75rem 1rem; margin-bottom: 0.65rem; font-size: 0.88rem; color: var(--color-text-muted); }
.filter { display: flex; align-items: center; gap: 0.4rem; font-size: 0.85rem; }
.filter-zeile { display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 0.6rem; margin-bottom: 0.65rem; }
.dok-thumbs { display: flex; flex-wrap: wrap; gap: 0.3rem; }
.dok-thumbs img { width: 2.5rem; height: 2.5rem; object-fit: cover; border-radius: var(--radius-sm); border: 1px solid var(--color-border); }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
.liste th, .liste td { padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--color-border); text-align: left; vertical-align: top; }
tr.warn { background: #fdf8f0; }
.klein { color: var(--color-text-muted); font-size: 0.78rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin-top: 0.75rem; }
.hinweis-oben { background: var(--color-surface-muted); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.5rem 0.75rem; margin-top: 0; }
</style>
