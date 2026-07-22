<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { useAuth } from '../../composables/useAuth'
import AppDialog from '../AppDialog.vue'

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
  ort_typ: OrtTyp
  ort_text: string | null
  wiese_id: string | null
  leute: { id: string; leiter_id: string; vorname: string; nachname: string }[]
}

const ORT_TYPEN = [
  { key: 'lagerhaus_drinnen', label: 'Lagerhaus drinnen' },
  { key: 'lagerhaus_draussen', label: 'Lagerhaus draussen' },
  { key: 'sonstiges', label: 'Sonstiges' },
  { key: 'wiese', label: 'Spielwiese' },
] as const
type OrtTyp = (typeof ORT_TYPEN)[number]['key']

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
  organisationId?: string | null
}>()

interface HoeckTyp {
  id: string
  name: string
  ist_standard: boolean
  uebernehmen_naechstes_jahr: boolean
}
interface Traktandum {
  id: string
  text: string
  sortierung: number
}

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
const bearbeitenForm = ref({
  bedarf_anzahl: '',
  uhrzeit: '',
  programm_block_id: '',
  ort_typ: 'lagerhaus_draussen' as OrtTyp,
  ort_text: '',
  wiese_id: '',
})
const tagBloecke = ref<ProgrammBlock[]>([])
const feedback = ref<Feedback[]>([])
const neuesFeedback = ref('')
const feedbackSpeichern = ref(false)

const alleTage = computed(() => {
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
/** Erster Lagertag = Starthöck, eigener Button; restliche Tage sind normale Lagerhöcks. */
const starthoeckTag = computed(() => alleTage.value[0] ?? '')
const tage = computed(() => alleTage.value.slice(1))

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
  if (!props.startDatum || !props.endDatum || !alleTage.value.length) {
    return { ansicht: 'tag', tag: alleTage.value[0] ?? '' }
  }
  const jetzt = new Date()
  const heuteIso = jetzt.toISOString().slice(0, 10)

  if (heuteIso < props.startDatum) {
    return { ansicht: 'tag', tag: alleTage.value[0] }
  }

  let zielIso = heuteIso
  if (jetzt.getHours() >= 21) {
    const naechster = new Date(heuteIso + 'T00:00:00')
    naechster.setDate(naechster.getDate() + 1)
    zielIso = naechster.toISOString().slice(0, 10)
  }

  if (zielIso > props.endDatum) {
    return { ansicht: 'feedback', tag: alleTage.value[alleTage.value.length - 1] }
  }
  if (zielIso < props.startDatum) {
    return { ansicht: 'tag', tag: alleTage.value[0] }
  }
  return { ansicht: 'tag', tag: zielIso }
}

const hoeckTypen = ref<HoeckTyp[]>([])
const ausgewaehlterTypId = ref('')
const traktanden = ref<Traktandum[]>([])
const traktandenErledigt = ref<Set<string>>(new Set())
const neuTraktandumText = ref('')
const neuerHoeckTypOffen = ref(false)
const neuerHoeckTypForm = ref({ name: '', uebernehmen: true })

async function ladeHoeckTypen() {
  if (!props.organisationId) return
  await supabase.rpc('hoeck_typen_sicherstellen', { p_organisation_id: props.organisationId })
  const { data } = await supabase
    .from('hoeck_typen')
    .select('id, name, ist_standard, uebernehmen_naechstes_jahr')
    .eq('organisation_id', props.organisationId)
    .order('sortierung')
  hoeckTypen.value = (data ?? []) as HoeckTyp[]
  if (!ausgewaehlterTypId.value) {
    const standard = hoeckTypen.value.find((t) => t.name === 'Lagerhöck')
    ausgewaehlterTypId.value = standard?.id ?? hoeckTypen.value[0]?.id ?? ''
  }
  await ladeTraktanden()
}

async function ladeTraktanden() {
  if (!ausgewaehlterTypId.value) { traktanden.value = []; return }
  const { data } = await supabase
    .from('hoeck_traktanden')
    .select('id, text, sortierung')
    .eq('hoeck_typ_id', ausgewaehlterTypId.value)
    .order('sortierung')
  traktanden.value = (data ?? []) as Traktandum[]
  await ladeTraktandenErledigt()
}

async function ladeTraktandenErledigt() {
  if (!aktiverTag.value) { traktandenErledigt.value = new Set(); return }
  const { data } = await supabase
    .from('hoeck_traktanden_erledigt')
    .select('traktandum_id')
    .eq('lager_id', props.lagerId)
    .eq('tag', aktiverTag.value)
  traktandenErledigt.value = new Set((data ?? []).map((r) => r.traktandum_id))
}

async function traktandumToggeln(traktandumId: string) {
  if (!aktiverTag.value) return
  if (traktandenErledigt.value.has(traktandumId)) {
    await supabase.from('hoeck_traktanden_erledigt').delete()
      .eq('lager_id', props.lagerId).eq('tag', aktiverTag.value).eq('traktandum_id', traktandumId)
    traktandenErledigt.value.delete(traktandumId)
  } else {
    await supabase.from('hoeck_traktanden_erledigt').insert({
      lager_id: props.lagerId, tag: aktiverTag.value, traktandum_id: traktandumId,
    })
    traktandenErledigt.value.add(traktandumId)
  }
  traktandenErledigt.value = new Set(traktandenErledigt.value)
}

async function traktandumHinzufuegen() {
  if (!neuTraktandumText.value.trim() || !ausgewaehlterTypId.value) return
  await supabase.from('hoeck_traktanden').insert({
    hoeck_typ_id: ausgewaehlterTypId.value,
    text: neuTraktandumText.value.trim(),
    sortierung: traktanden.value.length,
  })
  neuTraktandumText.value = ''
  await ladeTraktanden()
}

async function traktandumLoeschen(id: string) {
  await supabase.from('hoeck_traktanden').delete().eq('id', id)
  await ladeTraktanden()
}

async function eigenerHoeckTypErstellen() {
  if (!neuerHoeckTypForm.value.name.trim() || !props.organisationId) return
  const { data, error } = await supabase.from('hoeck_typen').insert({
    organisation_id: props.organisationId,
    name: neuerHoeckTypForm.value.name.trim(),
    ist_standard: false,
    uebernehmen_naechstes_jahr: neuerHoeckTypForm.value.uebernehmen,
    sortierung: hoeckTypen.value.length,
  }).select('id, name, ist_standard, uebernehmen_naechstes_jahr').single()
  if (error || !data) return
  hoeckTypen.value.push(data as HoeckTyp)
  ausgewaehlterTypId.value = data.id
  neuerHoeckTypForm.value = { name: '', uebernehmen: true }
  neuerHoeckTypOffen.value = false
  await ladeTraktanden()
}

async function typWechseln(typId: string) {
  ausgewaehlterTypId.value = typId
  await ladeTraktanden()
}

async function ladeDaten() {
  laden.value = true
  await ladeHoeckTypen()

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

  if (hoeckTypen.value.length) {
    const zielName = tag === starthoeckTag.value ? 'Starthöck' : 'Lagerhöck'
    const ziel = hoeckTypen.value.find((t) => t.name === zielName)
    if (ziel) {
      ausgewaehlterTypId.value = ziel.id
      await ladeTraktanden()
    }
  }
  await ladeTraktandenErledigt()

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
      ort_typ: (data.ort_typ as OrtTyp) ?? 'lagerhaus_draussen',
      ort_text: data.ort_text ?? null,
      wiese_id: data.wiese_id ?? null,
      leute: [],
    })
  }
  eigeneRolleNeu.value = ''
  neueRolleOffen.value = false
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
    ort_typ: rolle.ort_typ ?? 'lagerhaus_draussen',
    ort_text: rolle.ort_text ?? '',
    wiese_id: rolle.wiese_id ?? '',
  }
}

async function bearbeitenSpeichern(rolle: HoeckRolle) {
  const bedarf = bearbeitenForm.value.bedarf_anzahl ? Number(bearbeitenForm.value.bedarf_anzahl) : null
  const uhrzeit = bearbeitenForm.value.uhrzeit || null
  const blockId = bearbeitenForm.value.programm_block_id || null
  const ortTyp = bearbeitenForm.value.ort_typ
  const ortText = ortTyp === 'sonstiges' ? (bearbeitenForm.value.ort_text.trim() || null) : null
  const wieseId = ortTyp === 'wiese' ? (bearbeitenForm.value.wiese_id || null) : null
  await supabase.from('hoeck_rollen').update({
    bedarf_anzahl: bedarf,
    uhrzeit,
    programm_block_id: blockId,
    ort_typ: ortTyp,
    ort_text: ortText,
    wiese_id: wieseId,
  }).eq('id', rolle.id)
  rolle.bedarf_anzahl = bedarf
  rolle.uhrzeit = uhrzeit
  rolle.programm_block_id = blockId
  rolle.ort_typ = ortTyp
  rolle.ort_text = ortText
  rolle.wiese_id = wieseId
  rolleBearbeitenId.value = null
}

function ortLabel(rolle: HoeckRolle): string {
  if (rolle.ort_typ === 'sonstiges') return rolle.ort_text || 'Sonstiges'
  if (rolle.ort_typ === 'wiese') return alleWiesen.value.find((w) => w.id === rolle.wiese_id)?.name ?? 'Spielwiese'
  return ORT_TYPEN.find((o) => o.key === rolle.ort_typ)?.label ?? rolle.ort_typ
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

const hoeckErfassenForm = ref({
  titel: '', start_datum: '', end_datum: '', start_zeit: '', end_zeit: '', ort: '', beschreibung: '',
})
const hoeckErfassenLaden = ref(false)
const hoeckErfassenErfolg = ref(false)
const hoeckErfassenOffen = ref(false)
const neueRolleOffen = ref(false)

async function hoeckErfassen() {
  if (!hoeckErfassenForm.value.start_datum) return
  hoeckErfassenLaden.value = true
  hoeckErfassenErfolg.value = false
  const f = hoeckErfassenForm.value
  const { error } = await supabase.from('lager_termine').insert({
    lager_id: props.lagerId,
    typ: 'hoeck',
    titel: f.titel.trim() || 'Höck',
    start_datum: f.start_datum,
    end_datum: f.end_datum || f.start_datum,
    start_zeit: f.start_zeit || null,
    end_zeit: f.end_zeit || null,
    ort: f.ort.trim() || null,
    beschreibung: f.beschreibung.trim() || null,
  })
  hoeckErfassenLaden.value = false
  if (!error) {
    hoeckErfassenErfolg.value = true
    hoeckErfassenForm.value = { titel: '', start_datum: '', end_datum: '', start_zeit: '', end_zeit: '', ort: '', beschreibung: '' }
  }
}

onMounted(ladeDaten)
</script>

<template>
  <section class="hoeck-bereich">
    <h3>Höck – Tages-Rollen &amp; Dienste</h3>
    <p class="hint">Pro Tag Leiter für Rollen einteilen und Gruppen für Kiosk/Telefon zuweisen.</p>

    <nav v-if="alleTage.length" class="tage-nav">
      <button
        v-if="starthoeckTag"
        type="button"
        class="starthoeck-btn"
        :class="{ aktiv: ansicht === 'tag' && aktiverTag === starthoeckTag }"
        @click="ladeFuerTag(starthoeckTag)"
      >
        Starthöck
      </button>
      <router-link :to="`/lager/${lagerId}/vorweekend`" class="feedback-btn vorweekend-btn">
        Vorweekend →
      </router-link>
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

    <div v-if="isLeitung" class="hoeck-erfassen-trigger">
      <button type="button" class="sekundaer klein" @click="hoeckErfassenOffen = true">+ Weiteren Höck erfassen</button>
    </div>

    <AppDialog :open="hoeckErfassenOffen" titel="Weiteren Höck erfassen" @close="hoeckErfassenOffen = false">
      <p class="hint klein">z.B. Planungshöck vor dem Lager – erscheint auch im Kalender.</p>
      <form class="hoeck-erfassen-form" @submit.prevent="hoeckErfassen">
        <label>Titel <input v-model="hoeckErfassenForm.titel" placeholder="Höck" /></label>
        <label>Start <input v-model="hoeckErfassenForm.start_datum" type="date" required /></label>
        <label>Ende <input v-model="hoeckErfassenForm.end_datum" type="date" /></label>
        <label>Von <input v-model="hoeckErfassenForm.start_zeit" type="time" /></label>
        <label>Bis <input v-model="hoeckErfassenForm.end_zeit" type="time" /></label>
        <label>Ort <input v-model="hoeckErfassenForm.ort" /></label>
        <label>Beschreibung <input v-model="hoeckErfassenForm.beschreibung" /></label>
        <button type="submit" :disabled="hoeckErfassenLaden">{{ hoeckErfassenLaden ? 'Speichere…' : 'Speichern' }}</button>
        <span v-if="hoeckErfassenErfolg" class="hint klein ok">✓ Im Kalender erfasst.</span>
      </form>
    </AppDialog>

    <div v-if="laden" class="hint">Lade...</div>

    <!-- Tages-Höck -->
    <template v-if="!laden && ansicht === 'tag' && aktiverTag">
      <div class="traktanden-section">
        <div class="traktanden-kopf">
          <h4>Traktanden</h4>
          <select :value="ausgewaehlterTypId" @change="typWechseln(($event.target as HTMLSelectElement).value)">
            <option v-for="t in hoeckTypen" :key="t.id" :value="t.id">{{ t.name }}</option>
          </select>
        </div>
        <ul v-if="traktanden.length" class="traktanden-liste">
          <li v-for="tr in traktanden" :key="tr.id" :class="{ erledigt: traktandenErledigt.has(tr.id) }">
            <label>
              <input type="checkbox" :checked="traktandenErledigt.has(tr.id)" @change="traktandumToggeln(tr.id)" />
              {{ tr.text }}
            </label>
            <router-link
              v-if="tr.text.toLowerCase().includes('ämtli verteilen')"
              :to="`/lager/${lagerId}/leiter`"
              class="link-klein"
            >
              Ämtli zuteilen →
            </router-link>
            <button v-if="isLeitung" type="button" class="stift-btn" title="Löschen" @click="traktandumLoeschen(tr.id)">✕</button>
          </li>
        </ul>
        <p v-else class="hint klein">Keine Traktanden für diesen Höck-Typ.</p>
        <form v-if="isLeitung" class="traktandum-form" @submit.prevent="traktandumHinzufuegen">
          <input v-model="neuTraktandumText" placeholder="Neues Traktandum..." />
          <button type="submit" class="sekundaer klein">+</button>
        </form>
        <button v-if="isLeitung && !neuerHoeckTypOffen" type="button" class="sekundaer klein" @click="neuerHoeckTypOffen = true">
          + Eigenen Höck-Typ erstellen
        </button>
        <form v-if="neuerHoeckTypOffen" class="neuer-hoeck-typ-form" @submit.prevent="eigenerHoeckTypErstellen">
          <input v-model="neuerHoeckTypForm.name" placeholder="Name des Höcks" required />
          <label class="checkbox-label">
            <input type="checkbox" v-model="neuerHoeckTypForm.uebernehmen" />
            Ins Folgejahr übernehmen
          </label>
          <button type="submit" class="klein">Erstellen</button>
          <button type="button" class="sekundaer klein" @click="neuerHoeckTypOffen = false">Abbrechen</button>
        </form>
      </div>

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
                  <span class="rolle-meta">
                    <span v-if="rolle.uhrzeit && !blockVon(rolle)">🕐 {{ rolle.uhrzeit.slice(0, 5) }}</span>
                    <span v-if="rolle.bedarf_anzahl">{{ rolle.leute.length }}/{{ rolle.bedarf_anzahl }} Personen</span>
                    <span>📍 {{ ortLabel(rolle) }}</span>
                  </span>
                </div>
                <div class="rolle-aktionen">
                  <button type="button" class="stift-btn" title="Bedarf, Uhrzeit, Ort & Programmblock bearbeiten" @click="bearbeitenStarten(rolle)">✏️</button>
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
                <label>Ort
                  <select v-model="bearbeitenForm.ort_typ" class="klein-inp breit">
                    <option v-for="o in ORT_TYPEN" :key="o.key" :value="o.key" :disabled="o.key === 'wiese' && !alleWiesen.length">
                      {{ o.label }}
                    </option>
                  </select>
                </label>
                <label v-if="bearbeitenForm.ort_typ === 'sonstiges'">Ort-Bezeichnung
                  <input v-model="bearbeitenForm.ort_text" placeholder="z.B. Waldrand hinter dem Haus" class="klein-inp breit" />
                </label>
                <label v-if="bearbeitenForm.ort_typ === 'wiese'">Welche Wiese
                  <select v-model="bearbeitenForm.wiese_id" class="klein-inp breit">
                    <option value="">– wählen –</option>
                    <option v-for="w in alleWiesen" :key="w.id" :value="w.id">{{ w.name }}</option>
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

        <button type="button" class="sekundaer klein" @click="neueRolleOffen = true">+ Neue Rolle</button>
        <AppDialog :open="neueRolleOffen" titel="Neue Rolle" @close="neueRolleOffen = false">
          <div class="eigene-rolle-form">
            <select v-model="neueRolleAbschnitt" class="abschnitt-select">
              <option v-for="a in ZEITABSCHNITTE" :key="a.key" :value="a.key">{{ a.label }}</option>
            </select>
            <input v-model="eigeneRolleNeu" placeholder="Name der Rolle..." @keyup.enter="eigeneRolleHinzufuegen" />
            <button type="button" @click="eigeneRolleHinzufuegen">Erstellen</button>
          </div>
        </AppDialog>
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
.vorweekend-btn { display: inline-flex; align-items: center; text-decoration: none; }
.starthoeck-btn { font-weight: 700; }
.hoeck-erfassen-box {
  border: 1px solid var(--color-border); border-radius: var(--radius-md);
  padding: 0.85rem 1rem; margin: 0.75rem 0 1.25rem; background: var(--color-surface-muted);
}
.hoeck-erfassen-box h4 { margin: 0 0 0.15rem; }
.hoeck-erfassen-form {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 0.6rem; align-items: end; margin-top: 0.5rem; font-size: 0.85rem;
}
.hoeck-erfassen-form label { display: flex; flex-direction: column; gap: 0.2rem; color: var(--color-text-muted); font-size: 0.82rem; }
.hoeck-erfassen-form .ok { color: #2e7d32; grid-column: 1 / -1; }
.traktanden-section { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.85rem 1rem; margin-bottom: 1.25rem; }
.traktanden-kopf { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem; }
.traktanden-kopf h4 { margin: 0; }
.traktanden-liste { list-style: none; padding: 0; margin: 0; }
.traktanden-liste li { display: flex; align-items: center; gap: 0.5rem; padding: 0.3rem 0; border-bottom: 1px solid var(--color-border); font-size: 0.9rem; }
.traktanden-liste li.erledigt label { opacity: 0.55; text-decoration: line-through; }
.traktanden-liste label { display: flex; align-items: center; gap: 0.4rem; flex: 1; cursor: pointer; }
.traktandum-form { display: flex; gap: 0.4rem; margin-top: 0.6rem; }
.traktandum-form input { flex: 1; }
.neuer-hoeck-typ-form { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: center; margin-top: 0.5rem; }

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
.link-klein { font-size: 0.8rem; color: var(--color-accent); white-space: nowrap; }
.checkbox-label { display: flex; align-items: center; gap: 0.35rem; font-size: 0.85rem; }
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
