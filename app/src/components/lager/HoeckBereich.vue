<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { useAuth } from '../../composables/useAuth'

interface Leiter {
  id: string
  vorname: string
  nachname: string
  anwesend_von: string | null
  anwesend_bis: string | null
}

interface HoeckRolle {
  id: string
  rolle: string
  ist_eigene: boolean
  sortierung: number
  bedarf_anzahl: number | null
  uhrzeit: string | null
  programm_block_id: string | null
  leute: { id: string; leiter_id: string; vorname: string; nachname: string }[]
}

interface ProgrammBlock {
  id: string
  code: string
  titel: string
  start_zeit: string | null
  end_zeit: string | null
}

const ZEITABSCHNITTE = [
  { key: 'morgen', label: 'Morgen' },
  { key: 'nachmittag', label: 'Nachmittag' },
  { key: 'abend', label: 'Abend' },
  { key: 'sonstiges', label: 'Sonstiges' },
] as const
type ZeitabschnittKey = (typeof ZEITABSCHNITTE)[number]['key']

interface GruppenDienst {
  id: string
  tag: string
  dienst: string
  gruppen_name: string
}

interface Wiese {
  id: string
  name: string
}

interface Feedback {
  id: string
  autor_name: string
  text: string
  created_at: string
}

const FIXE_ROLLEN = ['Tagwach', 'Zmorge', 'Nachtruhe']

const props = defineProps<{
  lagerId: string
  startDatum: string | null
  endDatum: string | null
  isLeitung: boolean
}>()

const { session } = useAuth()

const alleLeiter = ref<Leiter[]>([])
const alleGruppen = ref<string[]>([])
const rollen = ref<HoeckRolle[]>([])
const gruppenDienste = ref<GruppenDienst[]>([])
const alleWiesen = ref<Wiese[]>([])
const tagWieseId = ref<string | null>(null)
const tagWieseZeilenId = ref<string | null>(null)
const laden = ref(true)
const aktiverTag = ref('')
const ansicht = ref<'tag' | 'feedback'>('tag')
const eigeneRolleNeu = ref('')
const neueRolleAbschnitt = ref<ZeitabschnittKey>('morgen')
const ABSCHNITT_STANDARDZEIT: Record<ZeitabschnittKey, string | null> = {
  morgen: '08:00',
  nachmittag: '14:00',
  abend: '19:00',
  sonstiges: null,
}
const rolleBearbeitenId = ref<string | null>(null)
const bearbeitenForm = ref({ bedarf_anzahl: '', uhrzeit: '', programm_block_id: '' })
const tagBloecke = ref<ProgrammBlock[]>([])
const feedback = ref<Feedback[]>([])
const neuesFeedback = ref('')
const feedbackSpeichern = ref(false)

const tage = computed(() => {
  if (!props.startDatum || !props.endDatum) return []
  const list: string[] = []
  const cur = new Date(props.startDatum + 'T00:00:00')
  const end = new Date(props.endDatum + 'T00:00:00')
  while (cur <= end) {
    list.push(cur.toISOString().slice(0, 10))
    cur.setDate(cur.getDate() + 1)
  }
  return list
})

const leiterImLagerAmTag = computed(() => {
  const tag = aktiverTag.value
  if (!tag) return alleLeiter.value
  return alleLeiter.value.filter((l) => {
    if (l.anwesend_von && tag < l.anwesend_von) return false
    if (l.anwesend_bis && tag > l.anwesend_bis) return false
    return true
  })
})

function blockVon(rolle: HoeckRolle): ProgrammBlock | null {
  if (!rolle.programm_block_id) return null
  return tagBloecke.value.find((b) => b.id === rolle.programm_block_id) ?? null
}

function zeitabschnitt(rolle: HoeckRolle): ZeitabschnittKey {
  const block = blockVon(rolle)
  const zeitStr = block?.start_zeit ?? (rolle.uhrzeit ? `${aktiverTag.value}T${rolle.uhrzeit}` : null)
  if (!zeitStr) return 'sonstiges'
  const stunde = new Date(zeitStr).getHours()
  if (stunde < 12) return 'morgen'
  if (stunde < 18) return 'nachmittag'
  if (stunde < 22) return 'abend'
  return 'sonstiges'
}

const rollenNachAbschnitt = computed(() => {
  const gruppen: Record<ZeitabschnittKey, HoeckRolle[]> = { morgen: [], nachmittag: [], abend: [], sonstiges: [] }
  for (const r of rollen.value) {
    gruppen[zeitabschnitt(r)].push(r)
  }
  return gruppen
})

function formatBlockZeit(block: ProgrammBlock) {
  if (!block.start_zeit) return ''
  const zeit = new Intl.DateTimeFormat('de-CH', { hour: '2-digit', minute: '2-digit' }).format(new Date(block.start_zeit))
  return zeit
}

function formatTag(tag: string) {
  return new Intl.DateTimeFormat('de-CH', { weekday: 'short', day: 'numeric', month: 'numeric' }).format(new Date(tag + 'T00:00:00'))
}

function formatDatum(iso: string) {
  return new Intl.DateTimeFormat('de-CH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(iso))
}

/** Vor 21 Uhr: heutiger Tag. Ab 21 Uhr: nächster Tag. Vor Lagerbeginn: erster Tag.
 *  Nach Lagerende (bzw. wenn der berechnete Zieltag nach dem Lager liegt): Feedback-Höck. */
function autoAnsichtBestimmen(): { ansicht: 'tag' | 'feedback'; tag: string } {
  if (!props.startDatum || !props.endDatum || !tage.value.length) {
    return { ansicht: 'tag', tag: tage.value[0] ?? '' }
  }
  const jetzt = new Date()
  const heuteIso = jetzt.toISOString().slice(0, 10)

  if (heuteIso < props.startDatum) {
    return { ansicht: 'tag', tag: tage.value[0] }
  }

  let zielIso = heuteIso
  if (jetzt.getHours() >= 21) {
    const naechster = new Date(heuteIso + 'T00:00:00')
    naechster.setDate(naechster.getDate() + 1)
    zielIso = naechster.toISOString().slice(0, 10)
  }

  if (zielIso > props.endDatum) {
    return { ansicht: 'feedback', tag: tage.value[tage.value.length - 1] }
  }
  if (zielIso < props.startDatum) {
    return { ansicht: 'tag', tag: tage.value[0] }
  }
  return { ansicht: 'tag', tag: zielIso }
}

async function ladeDaten() {
  laden.value = true

  const { data: leiterData } = await supabase
    .from('anmeldungen_leiter')
    .select('id, vorname, nachname, anwesend_von, anwesend_bis')
    .eq('lager_id', props.lagerId)
    .eq('status', 'bestaetigt')
    .order('nachname')
  alleLeiter.value = leiterData ?? []

  const { data: gruppenData } = await supabase
    .from('lagergruppen')
    .select('name')
    .eq('lager_id', props.lagerId)
    .order('name')
  alleGruppen.value = gruppenData?.map((g: any) => g.name) ?? []

  const { data: wiesenData } = await supabase
    .from('gelaendespielwiesen')
    .select('id, name')
    .eq('lager_id', props.lagerId)
    .order('name')
  alleWiesen.value = wiesenData ?? []

  if (!aktiverTag.value) {
    const auto = autoAnsichtBestimmen()
    ansicht.value = auto.ansicht
    aktiverTag.value = auto.tag
  }

  if (ansicht.value === 'tag' && aktiverTag.value) {
    await ladeFuerTag(aktiverTag.value)
  } else if (ansicht.value === 'feedback') {
    await ladeFeedback()
  }

  laden.value = false
}

async function ladeFuerTag(tag: string) {
  aktiverTag.value = tag
  ansicht.value = 'tag'

  const { data: rollenData } = await supabase
    .rpc('get_hoeck_rollen_fuer_tag', { p_lager_id: props.lagerId, p_tag: tag })
  rollen.value = (rollenData as HoeckRolle[]) ?? []

  const { data: bloeckeData } = await supabase
    .from('programmbloecke')
    .select('id, code, titel, start_zeit, end_zeit')
    .eq('lager_id', props.lagerId)
    .eq('tag', tag)
    .order('start_zeit')
  tagBloecke.value = (bloeckeData as ProgrammBlock[]) ?? []

  const { data: diensteData } = await supabase
    .from('hoeck_gruppen_dienste')
    .select('*')
    .eq('lager_id', props.lagerId)
    .eq('tag', tag)
  gruppenDienste.value = diensteData ?? []

  const { data: wieseTag } = await supabase
    .from('hoeck_tag_wiese')
    .select('id, wiese_id')
    .eq('lager_id', props.lagerId)
    .eq('tag', tag)
    .maybeSingle()
  tagWieseZeilenId.value = wieseTag?.id ?? null
  tagWieseId.value = wieseTag?.wiese_id ?? null
}

async function ladeFeedback() {
  ansicht.value = 'feedback'
  const { data } = await supabase
    .from('hoeck_feedback')
    .select('id, autor_name, text, created_at')
    .eq('lager_id', props.lagerId)
    .order('created_at')
  feedback.value = data ?? []
}

async function feedbackSenden() {
  const text = neuesFeedback.value.trim()
  if (!text || !session.value) return
  feedbackSpeichern.value = true
  const { data: profil } = await supabase
    .from('profiles')
    .select('vorname, nachname')
    .eq('id', session.value.user.id)
    .maybeSingle()
  const autorName = profil?.vorname
    ? `${profil.vorname} ${profil.nachname ?? ''}`.trim()
    : session.value.user.email?.split('@')[0] ?? 'Unbekannt'
  const { data } = await supabase
    .from('hoeck_feedback')
    .insert({ lager_id: props.lagerId, profile_id: session.value.user.id, autor_name: autorName, text })
    .select('id, autor_name, text, created_at')
    .single()
  if (data) feedback.value.push(data as Feedback)
  neuesFeedback.value = ''
  feedbackSpeichern.value = false
}

async function setWiese(wieseId: string) {
  if (!aktiverTag.value) return
  if (!wieseId) {
    if (tagWieseZeilenId.value) {
      await supabase.from('hoeck_tag_wiese').delete().eq('id', tagWieseZeilenId.value)
      tagWieseZeilenId.value = null
    }
    tagWieseId.value = null
    return
  }
  const { data } = await supabase
    .from('hoeck_tag_wiese')
    .upsert(
      { lager_id: props.lagerId, tag: aktiverTag.value, wiese_id: wieseId },
      { onConflict: 'lager_id,tag' },
    )
    .select('id')
    .single()
  tagWieseZeilenId.value = data?.id ?? tagWieseZeilenId.value
  tagWieseId.value = wieseId
}

function leiterName(leiterId: string): string {
  const l = alleLeiter.value.find((l) => l.id === leiterId)
  return l ? `${l.vorname} ${l.nachname}` : leiterId
}

async function toggleLeiterRolle(rolleId: string, leiterId: string) {
  const rolle = rollen.value.find((r) => r.id === rolleId)
  if (!rolle) return

  const existing = rolle.leute.find((l) => l.leiter_id === leiterId)
  if (existing) {
    await supabase.from('hoeck_zuweisungen').delete().eq('id', existing.id)
    rolle.leute = rolle.leute.filter((l) => l.leiter_id !== leiterId)
  } else {
    const { data } = await supabase
      .from('hoeck_zuweisungen')
      .insert({ hoeck_rolle_id: rolleId, leiter_id: leiterId })
      .select()
      .single()
    if (data) {
      const l = alleLeiter.value.find((l) => l.id === leiterId)
      rolle.leute.push({ id: data.id, leiter_id: leiterId, vorname: l?.vorname ?? '', nachname: l?.nachname ?? '' })
    }
  }
}

async function eigeneRolleHinzufuegen() {
  if (!eigeneRolleNeu.value.trim() || !aktiverTag.value) return
  const uhrzeit = ABSCHNITT_STANDARDZEIT[neueRolleAbschnitt.value]
  const { data } = await supabase
    .from('hoeck_rollen')
    .insert({
      lager_id: props.lagerId,
      tag: aktiverTag.value,
      rolle: eigeneRolleNeu.value.trim(),
      ist_eigene: true,
      sortierung: 10 + rollen.value.length,
      uhrzeit,
    })
    .select()
    .single()
  if (data) {
    rollen.value.push({
      id: data.id,
      rolle: data.rolle,
      ist_eigene: true,
      sortierung: data.sortierung,
      bedarf_anzahl: null,
      uhrzeit: data.uhrzeit ?? uhrzeit,
      programm_block_id: null,
      leute: [],
    })
  }
  eigeneRolleNeu.value = ''
}

async function eigeneRolleLoeschen(rolleId: string) {
  await supabase.from('hoeck_rollen').delete().eq('id', rolleId)
  rollen.value = rollen.value.filter((r) => r.id !== rolleId)
}

function bearbeitenStarten(rolle: HoeckRolle) {
  rolleBearbeitenId.value = rolle.id
  bearbeitenForm.value = {
    bedarf_anzahl: rolle.bedarf_anzahl != null ? String(rolle.bedarf_anzahl) : '',
    uhrzeit: rolle.uhrzeit ?? '',
    programm_block_id: rolle.programm_block_id ?? '',
  }
}

async function bearbeitenSpeichern(rolle: HoeckRolle) {
  const bedarf = bearbeitenForm.value.bedarf_anzahl ? Number(bearbeitenForm.value.bedarf_anzahl) : null
  const uhrzeit = bearbeitenForm.value.uhrzeit || null
  const blockId = bearbeitenForm.value.programm_block_id || null
  await supabase.from('hoeck_rollen').update({ bedarf_anzahl: bedarf, uhrzeit, programm_block_id: blockId }).eq('id', rolle.id)
  rolle.bedarf_anzahl = bedarf
  rolle.uhrzeit = uhrzeit
  rolle.programm_block_id = blockId
  rolleBearbeitenId.value = null
}

function getDienst(dienst: string): string {
  return gruppenDienste.value.find((d) => d.dienst === dienst)?.gruppen_name ?? ''
}

async function setDienst(dienst: string, gruppenName: string) {
  if (!aktiverTag.value) return
  const existing = gruppenDienste.value.find((d) => d.dienst === dienst)
  if (existing) {
    if (gruppenName) {
      await supabase.from('hoeck_gruppen_dienste').update({ gruppen_name: gruppenName }).eq('id', existing.id)
      existing.gruppen_name = gruppenName
    } else {
      await supabase.from('hoeck_gruppen_dienste').delete().eq('id', existing.id)
      gruppenDienste.value = gruppenDienste.value.filter((d) => d.id !== existing.id)
    }
  } else if (gruppenName) {
    const { data } = await supabase
      .from('hoeck_gruppen_dienste')
      .insert({ lager_id: props.lagerId, tag: aktiverTag.value, dienst, gruppen_name: gruppenName })
      .select()
      .single()
    if (data) gruppenDienste.value.push(data as GruppenDienst)
  }
}

onMounted(ladeDaten)
</script>

<template>
  <section class="hoeck-bereich">
    <h3>Höck – Tages-Rollen &amp; Dienste</h3>
    <p class="hint">Pro Tag Leiter für Rollen einteilen und Gruppen für Kiosk/Telefon zuweisen.</p>

    <nav v-if="tage.length" class="tage-nav">
      <button
        v-for="t in tage"
        :key="t"
        type="button"
        :class="{ aktiv: ansicht === 'tag' && t === aktiverTag }"
        @click="ladeFuerTag(t)"
      >
        {{ formatTag(t) }}
      </button>
      <button type="button" class="feedback-btn" :class="{ aktiv: ansicht === 'feedback' }" @click="ladeFeedback">
        Feedback-Höck
      </button>
    </nav>

    <div v-if="laden" class="hint">Lade...</div>

    <!-- Tages-Höck -->
    <template v-if="!laden && ansicht === 'tag' && aktiverTag">
      <div class="rollen-section">
        <h4>Rollen</h4>
        <div class="abschnitte-raster">
          <div v-for="abschnitt in ZEITABSCHNITTE" :key="abschnitt.key" class="abschnitt-spalte">
            <span class="abschnitt-label">{{ abschnitt.label }}</span>

            <div v-for="rolle in rollenNachAbschnitt[abschnitt.key]" :key="rolle.id" class="rolle-card">
              <div class="rolle-kopf">
                <div class="rolle-titel">
                  <strong>{{ rolle.rolle }}</strong>
                  <span v-if="blockVon(rolle)" class="rolle-block">{{ blockVon(rolle)!.code }} {{ blockVon(rolle)!.titel }} · {{ formatBlockZeit(blockVon(rolle)!) }}</span>
                  <span v-if="rolle.uhrzeit || rolle.bedarf_anzahl" class="rolle-meta">
                    <span v-if="rolle.uhrzeit && !blockVon(rolle)">🕐 {{ rolle.uhrzeit.slice(0, 5) }}</span>
                    <span v-if="rolle.bedarf_anzahl">{{ rolle.leute.length }}/{{ rolle.bedarf_anzahl }} Personen</span>
                  </span>
                </div>
                <div class="rolle-aktionen">
                  <button type="button" class="stift-btn" title="Bedarf, Uhrzeit & Programmblock bearbeiten" @click="bearbeitenStarten(rolle)">✏️</button>
                  <button v-if="rolle.ist_eigene" type="button" class="klein sekundaer" @click="eigeneRolleLoeschen(rolle.id)">✕</button>
                </div>
              </div>

              <div v-if="rolleBearbeitenId === rolle.id" class="bearbeiten-zeile">
                <label>Personen gesucht <input v-model="bearbeitenForm.bedarf_anzahl" type="number" min="0" class="klein-inp" /></label>
                <label>Uhrzeit <input v-model="bearbeitenForm.uhrzeit" type="time" class="klein-inp" :disabled="!!bearbeitenForm.programm_block_id" /></label>
                <label>Programmblock (optional)
                  <select v-model="bearbeitenForm.programm_block_id" class="klein-inp breit">
                    <option value="">– Kein –</option>
                    <option v-for="b in tagBloecke" :key="b.id" :value="b.id">{{ b.code }} {{ b.titel }} ({{ formatBlockZeit(b) }})</option>
                  </select>
                </label>
                <button type="button" class="klein" @click="bearbeitenSpeichern(rolle)">Speichern</button>
                <button type="button" class="klein sekundaer" @click="rolleBearbeitenId = null">Abbrechen</button>
              </div>

              <div class="rolle-leute">
                <button
                  v-for="l in leiterImLagerAmTag"
                  :key="l.id"
                  type="button"
                  class="leiter-chip"
                  :class="{ aktiv: rolle.leute.some((r) => r.leiter_id === l.id) }"
                  @click="toggleLeiterRolle(rolle.id, l.id)"
                >
                  {{ l.vorname }}
                </button>
                <span v-if="!leiterImLagerAmTag.length" class="hint klein">Niemand an diesem Tag im Lager erfasst.</span>
              </div>
            </div>

            <p v-if="!rollenNachAbschnitt[abschnitt.key].length" class="hint klein leer-hinweis">Keine Rollen.</p>
          </div>
        </div>

        <div v-if="isLeitung" class="eigene-rolle-form">
          <select v-model="neueRolleAbschnitt" class="abschnitt-select">
            <option v-for="a in ZEITABSCHNITTE" :key="a.key" :value="a.key">{{ a.label }}</option>
          </select>
          <input v-model="eigeneRolleNeu" placeholder="Neue Rolle..." @keyup.enter="eigeneRolleHinzufuegen" />
          <button type="button" class="sekundaer klein" @click="eigeneRolleHinzufuegen">+</button>
        </div>
      </div>

      <div class="dienste-section">
        <h4>Gruppen-Dienste</h4>
        <div class="dienst-row">
          <label>Kiosk:</label>
          <select :value="getDienst('kiosk')" @change="setDienst('kiosk', ($event.target as HTMLSelectElement).value)">
            <option value="">– Keine –</option>
            <option v-for="g in alleGruppen" :key="g" :value="g">{{ g }}</option>
          </select>
        </div>
        <div class="dienst-row">
          <label>Telefon:</label>
          <select :value="getDienst('telefon')" @change="setDienst('telefon', ($event.target as HTMLSelectElement).value)">
            <option value="">– Keine –</option>
            <option v-for="g in alleGruppen" :key="g" :value="g">{{ g }}</option>
          </select>
        </div>
        <div v-if="alleWiesen.length" class="dienst-row">
          <label>Spielwiese:</label>
          <select :value="tagWieseId ?? ''" @change="setWiese(($event.target as HTMLSelectElement).value)">
            <option value="">– Keine –</option>
            <option v-for="w in alleWiesen" :key="w.id" :value="w.id">{{ w.name }}</option>
          </select>
        </div>
      </div>
    </template>

    <!-- Feedback-Höck (nach dem Lager) -->
    <template v-if="!laden && ansicht === 'feedback'">
      <div class="feedback-section">
        <h4>Feedback-Höck</h4>
        <p class="hint">Rückblick: Was war gut, was können wir nächstes Jahr besser machen?</p>

        <div class="feedback-liste">
          <div v-for="f in feedback" :key="f.id" class="feedback-eintrag">
            <span class="feedback-meta">{{ f.autor_name }} · {{ formatDatum(f.created_at) }}</span>
            <p>{{ f.text }}</p>
          </div>
          <p v-if="!feedback.length" class="hint">Noch kein Feedback erfasst.</p>
        </div>

        <form class="feedback-form" @submit.prevent="feedbackSenden">
          <textarea v-model="neuesFeedback" rows="3" placeholder="Dein Feedback zum Lager..." :disabled="feedbackSpeichern"></textarea>
          <button type="submit" :disabled="feedbackSpeichern || !neuesFeedback.trim()">Feedback abschicken</button>
        </form>
      </div>
    </template>
  </section>
</template>

<style scoped>
.hoeck-bereich { margin-bottom: 1.5rem; }
.hoeck-bereich h3 { margin: 0 0 0.25rem; }
.hoeck-bereich h4 { margin: 1rem 0 0.5rem; font-size: 0.95rem; }
.tage-nav { display: flex; flex-wrap: wrap; gap: 0.35rem; margin: 0.75rem 0; }
.tage-nav button { font-size: 0.8rem; padding: 0.35rem 0.6rem; background: var(--color-surface); border: 1px solid var(--color-border); color: var(--color-text); border-radius: var(--radius-md); }
.tage-nav button.aktiv { background: var(--color-accent); color: #fdfbf3; border-color: var(--color-accent); }
.feedback-btn { margin-left: 0.35rem; border-style: dashed; }

.rollen-section { margin-bottom: 1.5rem; }
.abschnitte-raster { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 0.85rem; }
.abschnitt-spalte { display: flex; flex-direction: column; gap: 0.5rem; }
.abschnitt-label { font-size: 0.72rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.03em; color: var(--color-text-muted); }
.leer-hinweis { margin: 0; padding: 0.5rem 0.6rem; border: 1px dashed var(--color-border); border-radius: var(--radius-sm); }
.rolle-block { font-size: 0.75rem; color: var(--color-accent); }
.rolle-card {
  background: var(--color-surface); border: 1px solid var(--color-border);
  border-radius: var(--radius-md); padding: 0.6rem 0.75rem; margin-bottom: 0.5rem;
}
.rolle-kopf { display: flex; justify-content: space-between; align-items: flex-start; gap: 0.5rem; margin-bottom: 0.4rem; }
.rolle-titel { display: flex; flex-direction: column; gap: 0.15rem; }
.rolle-meta { font-size: 0.78rem; color: var(--color-text-muted); display: flex; gap: 0.3rem; flex-wrap: wrap; }
.rolle-aktionen { display: flex; gap: 0.3rem; align-items: center; }
.stift-btn { background: none; border: none; cursor: pointer; font-size: 0.9rem; padding: 0.1rem 0.2rem; }
.bearbeiten-zeile { display: flex; flex-wrap: wrap; gap: 0.6rem; align-items: end; margin-bottom: 0.5rem; padding: 0.5rem; background: var(--color-surface-muted); border-radius: var(--radius-sm); }
.bearbeiten-zeile label { display: flex; flex-direction: column; gap: 0.2rem; font-size: 0.78rem; color: var(--color-text-muted); }
.klein-inp { width: 6rem; padding: 0.2rem 0.35rem; font-size: 0.82rem; border: 1px solid var(--color-border); border-radius: var(--radius-sm); }
.klein-inp.breit { width: 100%; min-width: 12rem; }
.rolle-leute { display: flex; flex-wrap: wrap; gap: 0.3rem; }
.leiter-chip {
  padding: 0.2rem 0.5rem; font-size: 0.78rem; border: 1px solid var(--color-border);
  border-radius: var(--radius-pill); background: transparent; color: var(--color-text); cursor: pointer;
}
.leiter-chip.aktiv { background: var(--color-accent); color: #fdfbf3; border-color: var(--color-accent); }
.eigene-rolle-form { display: flex; gap: 0.4rem; margin-top: 0.5rem; }
.eigene-rolle-form input { flex: 1; padding: 0.35rem 0.5rem; border: 1px solid var(--color-border); border-radius: var(--radius-md); font-size: 0.85rem; }
.abschnitt-select { padding: 0.35rem 0.5rem; border: 1px solid var(--color-border); border-radius: var(--radius-md); font-size: 0.85rem; }

.dienst-row { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.4rem; }
.dienst-row label { font-size: 0.85rem; font-weight: 600; min-width: 60px; }
.dienst-row select { flex: 1; padding: 0.35rem 0.5rem; border: 1px solid var(--color-border); border-radius: var(--radius-md); font-size: 0.85rem; max-width: 200px; }

.feedback-section { margin-top: 0.5rem; }
.feedback-liste { display: flex; flex-direction: column; gap: 0.5rem; margin-bottom: 0.75rem; }
.feedback-eintrag { border-left: 2px solid var(--color-border); padding-left: 0.6rem; }
.feedback-eintrag p { margin: 0.1rem 0 0; font-size: 0.9rem; }
.feedback-meta { font-size: 0.75rem; color: var(--color-text-muted); }
.feedback-form { display: flex; flex-direction: column; gap: 0.5rem; }
.feedback-form textarea { width: 100%; padding: 0.5rem; border: 1px solid var(--color-border); border-radius: var(--radius-md); font-family: inherit; font-size: 0.88rem; }
.feedback-form button { align-self: flex-end; }

.klein { font-size: 0.75rem; padding: 0.15rem 0.4rem; }
.sekundaer { background: transparent; border: 1px solid var(--color-border); color: var(--color-text); border-radius: var(--radius-md); cursor: pointer; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.hint.klein { font-size: 0.78rem; }
</style>
