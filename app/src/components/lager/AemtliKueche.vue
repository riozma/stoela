<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import LagerEinkauf from './LagerEinkauf.vue'
import AemtliTodos from './AemtliTodos.vue'

type MahlzeitTyp = 'fruehstueck' | 'zmittag' | 'znacht' | 'jause'
type DashboardTab = 'uebersicht' | 'menuplaner' | 'gewohnheiten' | 'einkauf' | 'aufgaben'

interface MaterialZeile {
  name: string
  menge: string
  einheit: string
}

interface Vorlage {
  id: string
  name: string
  mahlzeit: MahlzeitTyp
  wochentag: number | null
  uhrzeit: string | null
  beschreibung: string | null
  material: MaterialZeile[]
}

interface Mahlzeit {
  id: string
  tag: string
  mahlzeit: MahlzeitTyp
  titel: string
  uhrzeit: string | null
  beschreibung: string | null
  material: MaterialZeile[]
  vorlage_id: string | null
}

interface Ausnahme {
  id: string
  tag: string
  vorlage_id: string
}

interface PersonEssen {
  id: string
  typ: 'tn' | 'leiter'
  name: string
  rolle: string
  allergien: string | null
  essensgewohnheiten: string | null
  essensgewohnheiten_sonstiges: string | null
  anwesend_von: string | null
  anwesend_bis: string | null
}

interface KuecheNotiz {
  id: string
  titel: string
  inhalt: string
  kategorie: string
}

const props = defineProps<{
  lagerId: string
  aemtliId: string
  lagerName: string
  userId: string
  startDatum: string | null
  endDatum: string | null
  bloecke: { id: string; titel: string; code: string }[]
  kannEinkaufMelden?: boolean
}>()

const ansicht = ref<DashboardTab>('uebersicht')
const menuTeil = ref<'plan' | 'wiederkehrend' | 'einzeln'>('plan')
const ausgewaehlterTag = ref<string>('')
const vorlagen = ref<Vorlage[]>([])
const mahlzeiten = ref<Mahlzeit[]>([])
const ausnahmen = ref<Ausnahme[]>([])
const personen = ref<PersonEssen[]>([])
const notizen = ref<KuecheNotiz[]>([])
const fehler = ref('')

const vorlageForm = ref({
  name: '',
  mahlzeit: 'zmittag' as MahlzeitTyp,
  wochentag: 1,
  uhrzeit: '12:00',
  beschreibung: '',
  materialText: '',
})

const einzelForm = ref({
  tag: '',
  mahlzeit: 'zmittag' as MahlzeitTyp,
  uhrzeit: '12:00',
  titel: '',
  beschreibung: '',
  materialText: '',
})

const notizForm = ref({ titel: '', inhalt: '', kategorie: 'allgemein' })

const mahlzeitLabels: Record<MahlzeitTyp, string> = {
  fruehstueck: 'Frühstück',
  zmittag: 'Zmorgen',
  znacht: 'Znacht',
  jause: 'Jause',
}

const defaultUhrzeit: Record<MahlzeitTyp, string> = {
  fruehstueck: '07:30',
  zmittag: '12:00',
  jause: '15:30',
  znacht: '18:30',
}

const wochentage = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa']

const heute = computed(() => new Date().toISOString().slice(0, 10))

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

const personenMitHinweis = computed(() =>
  personen.value.filter(
    (p) =>
      p.allergien?.trim()
      || p.essensgewohnheiten?.trim()
      || p.essensgewohnheiten_sonstiges?.trim(),
  ),
)

const koepfeHeute = computed(() => koepfeAmTag(heute.value))

function istAnwesendAmTag(p: PersonEssen, tag: string) {
  if (p.typ === 'tn') return true
  const von = p.anwesend_von
  const bis = p.anwesend_bis
  if (!von && !bis) return true
  if (von && tag < von) return false
  if (bis && tag > bis) return false
  return true
}

function koepfeAmTag(tag: string) {
  const tn = personen.value.filter((p) => p.typ === 'tn' && istAnwesendAmTag(p, tag)).length
  const leiter = personen.value.filter((p) => p.typ === 'leiter' && istAnwesendAmTag(p, tag)).length
  return { tn, leiter, total: tn + leiter }
}

function essensText(p: PersonEssen) {
  const teile = [p.essensgewohnheiten?.trim(), p.essensgewohnheiten_sonstiges?.trim()].filter(Boolean)
  return teile.length ? teile.join(' · ') : '–'
}

function parseMaterial(text: string): MaterialZeile[] {
  return text
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)
    .map((line) => {
      const parts = line.split(/\s+/)
      if (parts.length >= 3 && !Number.isNaN(Number(parts[0]))) {
        return { menge: parts[0], einheit: parts[1], name: parts.slice(2).join(' ') }
      }
      return { menge: '', einheit: '', name: line }
    })
}

function formatTag(tag: string) {
  const d = new Date(tag + 'T00:00:00')
  return new Intl.DateTimeFormat('de-CH', { weekday: 'short', day: 'numeric', month: 'numeric' }).format(d)
}

function formatUhrzeit(zeit: string | null, typ: MahlzeitTyp) {
  if (!zeit) return defaultUhrzeit[typ]
  return zeit.slice(0, 5)
}

function wochentagVonTag(tag: string) {
  return new Date(tag + 'T00:00:00').getDay()
}

function istAusnahme(tag: string, vorlageId: string) {
  return ausnahmen.value.some((a) => a.tag === tag && a.vorlage_id === vorlageId)
}

function mahlzeitFuerSlot(tag: string, typ: MahlzeitTyp): Mahlzeit | null {
  return mahlzeiten.value.find((m) => m.tag === tag && m.mahlzeit === typ) ?? null
}

function vorlagenFuerTag(tag: string, typ: MahlzeitTyp): Vorlage[] {
  const wd = wochentagVonTag(tag)
  return vorlagen.value.filter((v) => v.mahlzeit === typ && v.wochentag === wd && !istAusnahme(tag, v.id))
}

interface PlanEintrag {
  quelle: 'einzeln' | 'vorlage'
  titel: string
  uhrzeit: string | null
  beschreibung: string | null
  material: MaterialZeile[]
  vorlageId?: string
  mahlzeitId?: string
}

function planFuerSlot(tag: string, typ: MahlzeitTyp): PlanEintrag | null {
  const einzel = mahlzeitFuerSlot(tag, typ)
  if (einzel) {
    return {
      quelle: 'einzeln',
      titel: einzel.titel,
      uhrzeit: einzel.uhrzeit,
      beschreibung: einzel.beschreibung,
      material: einzel.material,
      mahlzeitId: einzel.id,
    }
  }
  const vs = vorlagenFuerTag(tag, typ)
  if (vs.length === 1) {
    const v = vs[0]
    return {
      quelle: 'vorlage',
      titel: v.name,
      uhrzeit: v.uhrzeit,
      beschreibung: v.beschreibung,
      material: v.material,
      vorlageId: v.id,
    }
  }
  if (vs.length > 1) {
    return {
      quelle: 'vorlage',
      titel: vs.map((v) => v.name).join(' / '),
      uhrzeit: vs[0]?.uhrzeit ?? null,
      beschreibung: vs.map((v) => v.beschreibung).filter(Boolean).join(' · ') || null,
      material: vs.flatMap((v) => v.material),
    }
  }
  return null
}

const heutePlan = computed(() => {
  const tag = tage.value.includes(heute.value) ? heute.value : ausgewaehlterTag.value
  if (!tag) return []
  return (['fruehstueck', 'zmittag', 'jause', 'znacht'] as MahlzeitTyp[])
    .map((typ) => ({ typ, plan: planFuerSlot(tag, typ) }))
    .filter((e) => e.plan)
})

async function laden() {
  const [{ data: v }, { data: m }, { data: a }, { data: tn }, { data: leiter }, { data: n }] = await Promise.all([
    supabase.from('mahlzeit_vorlagen').select('*').eq('lager_id', props.lagerId).order('name'),
    supabase.from('mahlzeiten').select('*').eq('lager_id', props.lagerId).order('tag'),
    supabase.from('mahlzeit_ausnahmen').select('*').eq('lager_id', props.lagerId),
    supabase.from('anmeldungen_tn').select('id, vorname, nachname, rolle, allergien, essensgewohnheiten, essensgewohnheiten_sonstiges').eq('lager_id', props.lagerId).neq('status', 'abgesagt').order('nachname'),
    supabase.from('anmeldungen_leiter').select('id, vorname, nachname, essensgewohnheiten, anwesend_von, anwesend_bis').eq('lager_id', props.lagerId).in('status', ['bestaetigt', 'angemeldet']).order('nachname'),
    supabase.from('kueche_notizen').select('*').eq('lager_id', props.lagerId).order('created_at', { ascending: false }),
  ])
  vorlagen.value = (v ?? []).map((row) => ({ ...row, material: (row.material as MaterialZeile[]) ?? [] }))
  mahlzeiten.value = (m ?? []).map((row) => ({ ...row, material: (row.material as MaterialZeile[]) ?? [] }))
  ausnahmen.value = a ?? []
  personen.value = [
    ...(tn ?? []).map((p) => ({
      id: p.id,
      typ: 'tn' as const,
      name: `${p.vorname} ${p.nachname}`,
      rolle: p.rolle,
      allergien: p.allergien,
      essensgewohnheiten: p.essensgewohnheiten,
      essensgewohnheiten_sonstiges: p.essensgewohnheiten_sonstiges,
      anwesend_von: null,
      anwesend_bis: null,
    })),
    ...(leiter ?? []).map((p) => ({
      id: p.id,
      typ: 'leiter' as const,
      name: `${p.vorname} ${p.nachname}`,
      rolle: 'Leiter',
      allergien: null,
      essensgewohnheiten: p.essensgewohnheiten,
      essensgewohnheiten_sonstiges: null,
      anwesend_von: p.anwesend_von,
      anwesend_bis: p.anwesend_bis,
    })),
  ]
  notizen.value = n ?? []
  if (!ausgewaehlterTag.value && tage.value.length) {
    ausgewaehlterTag.value = tage.value.includes(heute.value) ? heute.value : tage.value[0]
  }
}

onMounted(laden)

function onMahlzeitTypChange(form: 'vorlage' | 'einzel') {
  const typ = form === 'vorlage' ? vorlageForm.value.mahlzeit : einzelForm.value.mahlzeit
  const zeit = defaultUhrzeit[typ]
  if (form === 'vorlage') vorlageForm.value.uhrzeit = zeit
  else einzelForm.value.uhrzeit = zeit
}

async function vorlageSpeichern() {
  fehler.value = ''
  const { error } = await supabase.from('mahlzeit_vorlagen').insert({
    lager_id: props.lagerId,
    name: vorlageForm.value.name,
    mahlzeit: vorlageForm.value.mahlzeit,
    wochentag: vorlageForm.value.wochentag,
    uhrzeit: vorlageForm.value.uhrzeit || defaultUhrzeit[vorlageForm.value.mahlzeit],
    beschreibung: vorlageForm.value.beschreibung || null,
    material: parseMaterial(vorlageForm.value.materialText),
  })
  if (error) { fehler.value = error.message; return }
  vorlageForm.value = { name: '', mahlzeit: 'zmittag', wochentag: 1, uhrzeit: '12:00', beschreibung: '', materialText: '' }
  await laden()
}

async function vorlageLoeschen(id: string) {
  await supabase.from('mahlzeit_vorlagen').delete().eq('id', id)
  await laden()
}

async function einzelSpeichern() {
  fehler.value = ''
  const tag = einzelForm.value.tag || ausgewaehlterTag.value
  if (!tag) { fehler.value = 'Bitte Tag wählen.'; return }
  const { error } = await supabase.from('mahlzeiten').upsert(
    {
      lager_id: props.lagerId,
      tag,
      mahlzeit: einzelForm.value.mahlzeit,
      uhrzeit: einzelForm.value.uhrzeit || defaultUhrzeit[einzelForm.value.mahlzeit],
      titel: einzelForm.value.titel,
      beschreibung: einzelForm.value.beschreibung || null,
      material: parseMaterial(einzelForm.value.materialText),
      vorlage_id: null,
    },
    { onConflict: 'lager_id,tag,mahlzeit' },
  )
  if (error) { fehler.value = error.message; return }
  einzelForm.value = { tag: '', mahlzeit: 'zmittag', uhrzeit: '12:00', titel: '', beschreibung: '', materialText: '' }
  await laden()
}

async function einzelLoeschen(id: string) {
  await supabase.from('mahlzeiten').delete().eq('id', id)
  await laden()
}

async function vorlageAussetzen(tag: string, vorlageId: string) {
  await supabase.from('mahlzeit_ausnahmen').upsert(
    { lager_id: props.lagerId, tag, vorlage_id: vorlageId },
    { onConflict: 'lager_id,tag,vorlage_id' },
  )
  await laden()
}

async function personSpeichern(person: PersonEssen) {
  fehler.value = ''
  const tabelle = person.typ === 'tn' ? 'anmeldungen_tn' : 'anmeldungen_leiter'
  const payload: Record<string, string | null> = { essensgewohnheiten: person.essensgewohnheiten || null }
  if (person.typ === 'tn') payload.allergien = person.allergien || null
  const { error } = await supabase.from(tabelle).update(payload).eq('id', person.id)
  if (error) fehler.value = error.message
}

async function notizSpeichern() {
  fehler.value = ''
  const { error } = await supabase.from('kueche_notizen').insert({
    lager_id: props.lagerId,
    titel: notizForm.value.titel,
    inhalt: notizForm.value.inhalt,
    kategorie: notizForm.value.kategorie,
  })
  if (error) { fehler.value = error.message; return }
  notizForm.value = { titel: '', inhalt: '', kategorie: 'allgemein' }
  await laden()
}

async function notizLoeschen(id: string) {
  await supabase.from('kueche_notizen').delete().eq('id', id)
  await laden()
}

async function materialZuEinkauf(material: MaterialZeile[]) {
  if (!material.length) return
  const rows = material.map((m) => ({
    lager_id: props.lagerId,
    name: m.name,
    menge: m.menge ? Number(m.menge) : null,
    einheit: m.einheit || null,
    bereich: 'lager',
    mahlzeit: null,
    notiz: 'Aus Menüplaner',
  }))
  await supabase.from('einkaufsliste_items').insert(rows)
  ansicht.value = 'einkauf'
}
</script>

<template>
  <section class="kueche-dashboard">
    <header class="dash-kopf">
      <div>
        <h2>Küchendashboard</h2>
        <p class="hint">Menüplanung, Essensgewohnheiten, Einkauf und Aufgaben an einem Ort.</p>
      </div>
    </header>

    <nav class="dash-tabs">
      <button :class="{ aktiv: ansicht === 'uebersicht' }" @click="ansicht = 'uebersicht'">Übersicht</button>
      <button :class="{ aktiv: ansicht === 'menuplaner' }" @click="ansicht = 'menuplaner'">Menüplaner</button>
      <button :class="{ aktiv: ansicht === 'gewohnheiten' }" @click="ansicht = 'gewohnheiten'">
        Essensgewohnheiten
        <span v-if="personenMitHinweis.length" class="badge">{{ personenMitHinweis.length }}</span>
      </button>
      <button :class="{ aktiv: ansicht === 'einkauf' }" @click="ansicht = 'einkauf'">Einkauf</button>
      <button :class="{ aktiv: ansicht === 'aufgaben' }" @click="ansicht = 'aufgaben'">Aufgaben</button>
    </nav>

    <p v-if="fehler" class="error">{{ fehler }}</p>

    <!-- Übersicht -->
    <div v-if="ansicht === 'uebersicht'" class="dash-grid">
      <article class="dash-karte">
        <h3>Heute auf dem Teller</h3>
        <p v-if="!tage.length" class="hint">Start- und Enddatum des Lagers in den Einstellungen setzen.</p>
        <ul v-else-if="heutePlan.length" class="heute-liste">
          <li v-for="e in heutePlan" :key="e.typ">
            <span class="zeit">{{ formatUhrzeit(e.plan!.uhrzeit, e.typ) }}</span>
            <span class="mahlzeit-label">{{ mahlzeitLabels[e.typ] }}</span>
            <strong>{{ e.plan!.titel }}</strong>
            <span v-if="e.plan!.beschreibung" class="beschreibung">{{ e.plan!.beschreibung }}</span>
          </li>
        </ul>
        <p v-else class="hint">Für heute ist noch nichts geplant.</p>
        <button class="secondary klein" @click="ansicht = 'menuplaner'">Menü planen</button>
      </article>

      <article class="dash-karte">
        <h3>Personen im Lager</h3>
        <p class="stat">{{ koepfeHeute.total }} heute</p>
        <p class="hint">{{ koepfeHeute.tn }} TN · {{ koepfeHeute.leiter }} Leiter</p>
        <p v-if="personenMitHinweis.length" class="hint">{{ personenMitHinweis.length }} mit Allergien/Essen-Hinweisen</p>
      </article>

      <article class="dash-karte">
        <h3>Essensgewohnheiten</h3>
        <p class="stat">{{ personenMitHinweis.length }} Personen mit Hinweisen</p>
        <ul v-if="personenMitHinweis.length" class="kurz-liste">
          <li v-for="p in personenMitHinweis.slice(0, 5)" :key="p.id">
            <strong>{{ p.name }}</strong>
            <span v-if="p.allergien"> · Allergien: {{ p.allergien }}</span>
            <span v-if="essensText(p) !== '–'"> · {{ essensText(p) }}</span>
          </li>
        </ul>
        <button class="secondary klein" @click="ansicht = 'gewohnheiten'">Alle anzeigen</button>
      </article>

      <article class="dash-karte">
        <h3>Küchennotizen</h3>
        <ul v-if="notizen.length" class="kurz-liste">
          <li v-for="n in notizen.slice(0, 4)" :key="n.id">
            <strong>{{ n.titel }}</strong> — {{ n.inhalt }}
          </li>
        </ul>
        <p v-else class="hint">Noch keine Notizen.</p>
        <button class="secondary klein" @click="ansicht = 'gewohnheiten'">Notiz hinzufügen</button>
      </article>
    </div>

    <!-- Menüplaner -->
    <div v-if="ansicht === 'menuplaner'">
      <nav class="sub-tabs">
        <button :class="{ aktiv: menuTeil === 'plan' }" @click="menuTeil = 'plan'">Tagesplan</button>
        <button :class="{ aktiv: menuTeil === 'wiederkehrend' }" @click="menuTeil = 'wiederkehrend'">Wiederkehrend</button>
        <button :class="{ aktiv: menuTeil === 'einzeln' }" @click="menuTeil = 'einzeln'">Einzelmahlzeit</button>
      </nav>

      <div v-if="menuTeil === 'plan'">
        <p v-if="!tage.length" class="hint">Lager-Start und -Ende in den Einstellungen setzen.</p>

        <nav v-else class="tage-nav">
          <button
            v-for="tag in tage"
            :key="tag"
            :class="{ aktiv: tag === ausgewaehlterTag, heute: tag === heute }"
            @click="ausgewaehlterTag = tag"
          >
            {{ formatTag(tag) }}
          </button>
        </nav>

        <div v-if="ausgewaehlterTag" class="tag-plan">
          <div
            v-for="typ in (['fruehstueck', 'zmittag', 'jause', 'znacht'] as MahlzeitTyp[])"
            :key="typ"
            class="mahlzeit-karte"
          >
            <div class="mahlzeit-kopf">
              <span class="uhrzeit-badge">{{ formatUhrzeit(planFuerSlot(ausgewaehlterTag, typ)?.uhrzeit ?? null, typ) }}</span>
              <h4>{{ mahlzeitLabels[typ] }}</h4>
            </div>
            <template v-if="planFuerSlot(ausgewaehlterTag, typ)">
              <p class="was-label">Was gibt es?</p>
              <p class="titel">{{ planFuerSlot(ausgewaehlterTag, typ)!.titel }}</p>
              <p v-if="planFuerSlot(ausgewaehlterTag, typ)!.beschreibung" class="beschreibung">
                {{ planFuerSlot(ausgewaehlterTag, typ)!.beschreibung }}
              </p>
              <ul v-if="planFuerSlot(ausgewaehlterTag, typ)!.material.length" class="material">
                <li v-for="(m, i) in planFuerSlot(ausgewaehlterTag, typ)!.material" :key="i">
                  {{ m.menge }} {{ m.einheit }} {{ m.name }}
                </li>
              </ul>
              <div class="aktionen">
                <button
                  v-if="planFuerSlot(ausgewaehlterTag, typ)!.material.length"
                  class="secondary klein"
                  @click="materialZuEinkauf(planFuerSlot(ausgewaehlterTag, typ)!.material)"
                >
                  Zutaten → Einkauf
                </button>
                <button
                  v-if="planFuerSlot(ausgewaehlterTag, typ)!.mahlzeitId"
                  class="secondary klein"
                  @click="einzelLoeschen(planFuerSlot(ausgewaehlterTag, typ)!.mahlzeitId!)"
                >
                  Einzelmahlzeit löschen
                </button>
                <button
                  v-if="planFuerSlot(ausgewaehlterTag, typ)!.vorlageId"
                  class="secondary klein"
                  @click="vorlageAussetzen(ausgewaehlterTag, planFuerSlot(ausgewaehlterTag, typ)!.vorlageId!)"
                >
                  Wiederkehrende an diesem Tag aussetzen
                </button>
              </div>
            </template>
            <p v-else class="hint">Noch nichts geplant.</p>
          </div>
        </div>
      </div>

      <div v-if="menuTeil === 'wiederkehrend'">
        <p class="hint">Wiederkehrende Mahlzeiten erscheinen automatisch an jedem passenden Wochentag im Tagesplan.</p>
        <div v-if="vorlagen.length" class="vorlagen-liste">
          <div v-for="v in vorlagen" :key="v.id" class="vorlage-karte">
            <div class="mahlzeit-kopf">
              <span class="uhrzeit-badge">{{ formatUhrzeit(v.uhrzeit, v.mahlzeit) }}</span>
              <strong>{{ v.name }}</strong>
            </div>
            <span class="meta">{{ mahlzeitLabels[v.mahlzeit] }} · jeden {{ wochentage[v.wochentag ?? 0] }}</span>
            <p class="was-label">Was gibt es?</p>
            <p>{{ v.name }}</p>
            <p v-if="v.beschreibung">{{ v.beschreibung }}</p>
            <ul v-if="v.material.length">
              <li v-for="(m, i) in v.material" :key="i">{{ m.menge }} {{ m.einheit }} {{ m.name }}</li>
            </ul>
            <button class="secondary klein" @click="vorlageLoeschen(v.id)">Löschen</button>
          </div>
        </div>
        <p v-else class="hint">Noch keine wiederkehrenden Mahlzeiten.</p>

        <h3>Neue wiederkehrende Mahlzeit</h3>
        <form class="form-grid" @submit.prevent="vorlageSpeichern">
          <label>Was gibt es? (Name) <input v-model="vorlageForm.name" required placeholder="z.B. Rösti und Salat" /></label>
          <label>Mahlzeit
            <select v-model="vorlageForm.mahlzeit" @change="onMahlzeitTypChange('vorlage')">
              <option v-for="(label, key) in mahlzeitLabels" :key="key" :value="key">{{ label }}</option>
            </select>
          </label>
          <label>Uhrzeit <input v-model="vorlageForm.uhrzeit" type="time" required /></label>
          <label>Wochentag
            <select v-model.number="vorlageForm.wochentag">
              <option v-for="(wd, i) in wochentage" :key="i" :value="i">{{ wd }}</option>
            </select>
          </label>
          <label class="full">Beschreibung / Zubereitung
            <textarea v-model="vorlageForm.beschreibung" rows="2" placeholder="Optional: Details zur Zubereitung"></textarea>
          </label>
          <label class="full">Zutaten (eine Zeile pro Zutat)
            <textarea v-model="vorlageForm.materialText" rows="4" placeholder="2 kg Kartoffeln&#10;1 Bund Schnittlauch"></textarea>
          </label>
          <button type="submit">Wiederkehrend speichern</button>
        </form>
      </div>

      <div v-if="menuTeil === 'einzeln'">
        <p class="hint">Einzelmahlzeiten überschreiben die wiederkehrende Planung an einem bestimmten Tag.</p>
        <form class="form-grid" @submit.prevent="einzelSpeichern">
          <label>Tag <input v-model="einzelForm.tag" type="date" /></label>
          <label>Mahlzeit
            <select v-model="einzelForm.mahlzeit" @change="onMahlzeitTypChange('einzel')">
              <option v-for="(label, key) in mahlzeitLabels" :key="key" :value="key">{{ label }}</option>
            </select>
          </label>
          <label>Uhrzeit <input v-model="einzelForm.uhrzeit" type="time" required /></label>
          <label>Was gibt es? <input v-model="einzelForm.titel" required placeholder="z.B. Grillabend mit Burger" /></label>
          <label class="full">Beschreibung
            <textarea v-model="einzelForm.beschreibung" rows="2"></textarea>
          </label>
          <label class="full">Zutaten
            <textarea v-model="einzelForm.materialText" rows="4"></textarea>
          </label>
          <button type="submit">Einzelmahlzeit speichern</button>
        </form>
      </div>
    </div>

    <!-- Essensgewohnheiten -->
    <div v-if="ansicht === 'gewohnheiten'">
      <h3>Essensgewohnheiten &amp; Allergien</h3>
      <p class="hint">Alle TN und Leiter – Angaben aus der Anmeldung. Die Küche kann sie hier ergänzen.</p>

      <div v-if="tage.length" class="koepfe-zeile">
        <span class="hint">Köpfe pro Tag:</span>
        <span v-for="tag in tage" :key="tag" class="kopf-badge" :class="{ heute: tag === heute }">
          {{ formatTag(tag) }}: {{ koepfeAmTag(tag).total }}
        </span>
      </div>

      <table v-if="personen.length" class="liste">
        <thead>
          <tr><th>Name</th><th>Typ</th><th>Allergien</th><th>Essensgewohnheiten</th><th></th></tr>
        </thead>
        <tbody>
          <tr v-for="p in personen" :key="p.id" :class="{ warn: p.allergien?.trim() || p.essensgewohnheiten?.trim() }">
            <td>{{ p.name }}</td>
            <td>{{ p.rolle }}</td>
            <td>
              <input
                v-if="p.typ === 'tn'"
                v-model="p.allergien"
                type="text"
                placeholder="z.B. Nüsse, Laktose"
                class="zellen-input"
              />
              <span v-else class="hint">–</span>
            </td>
            <td>
              <input
                v-model="p.essensgewohnheiten"
                type="text"
                placeholder="z.B. vegetarisch, kein Schwein"
                class="zellen-input"
              />
              <span v-if="p.essensgewohnheiten_sonstiges" class="klein-hinweis">{{ p.essensgewohnheiten_sonstiges }}</span>
            </td>
            <td><button class="secondary klein" @click="personSpeichern(p)">Speichern</button></td>
          </tr>
        </tbody>
      </table>
      <p v-else class="hint">Noch keine Teilnehmer oder Leiter erfasst.</p>

      <h3>Allgemeine Küchennotizen</h3>
      <p class="hint">Regeln, Hygiene-Hinweise, Einkaufs-Erinnerungen für das ganze Lager.</p>
      <div v-if="notizen.length" class="notizen-liste">
        <article v-for="n in notizen" :key="n.id" class="notiz-karte">
          <span class="kategorie">{{ n.kategorie }}</span>
          <strong>{{ n.titel }}</strong>
          <p>{{ n.inhalt }}</p>
          <button class="secondary klein" @click="notizLoeschen(n.id)">Löschen</button>
        </article>
      </div>
      <form class="form-grid" @submit.prevent="notizSpeichern">
        <label>Titel <input v-model="notizForm.titel" required placeholder="z.B. Hygiene vor dem Kochen" /></label>
        <label>Kategorie
          <select v-model="notizForm.kategorie">
            <option value="allgemein">Allgemein</option>
            <option value="allergie">Allergie-Hinweis</option>
            <option value="planung">Planung</option>
            <option value="einkauf">Einkauf</option>
            <option value="hygiene">Hygiene</option>
          </select>
        </label>
        <label class="full">Inhalt <textarea v-model="notizForm.inhalt" rows="3" required></textarea></label>
        <button type="submit">Notiz hinzufügen</button>
      </form>
    </div>

    <!-- Einkauf -->
    <div v-if="ansicht === 'einkauf'">
      <p class="hint">Leiter/innen können Artikel melden – die Küche plant den Einkaufstermin und schliesst die Liste.</p>
      <LagerEinkauf
        :lager-id="lagerId"
        :lager-name="lagerName"
        :user-id="userId"
        :ist-kueche="true"
        :kann-melden="kannEinkaufMelden ?? true"
        :bloecke="bloecke"
      />
    </div>

    <!-- Aufgaben -->
    <div v-if="ansicht === 'aufgaben'">
      <AemtliTodos :lager-id="lagerId" :aemtli-id="aemtliId" aemtli-name="Küche" />
    </div>
  </section>
</template>

<style scoped>
.kueche-dashboard { margin-bottom: 2rem; }
.dash-kopf { margin-bottom: 1rem; }
.dash-kopf h2 { margin: 0 0 0.25rem; }
.dash-tabs { display: flex; flex-wrap: wrap; gap: 0.4rem; margin-bottom: 1.25rem; }
.dash-tabs button {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  font-size: 0.85rem;
  color: var(--color-text);
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
}
.dash-tabs button.aktiv { background: var(--color-accent); color: #fdfbf3; border-color: var(--color-accent); }
.badge {
  display: inline-block;
  padding: 0.05rem 0.4rem;
  border-radius: var(--radius-pill);
  font-size: 0.7rem;
  background: rgba(0, 0, 0, 0.12);
}
.dash-tabs button.aktiv .badge { background: rgba(255, 255, 255, 0.25); }
.dash-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 0.85rem; margin-bottom: 1rem; }
.dash-karte {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 1rem;
}
.dash-karte h3 { margin: 0 0 0.5rem; font-size: 1rem; }
.stat { font-size: 1.4rem; font-weight: 700; margin: 0.25rem 0 0.75rem; color: var(--color-accent); }
.heute-liste, .kurz-liste { list-style: none; padding: 0; margin: 0 0 0.75rem; font-size: 0.9rem; }
.heute-liste li, .kurz-liste li { padding: 0.35rem 0; border-bottom: 1px solid var(--color-border); }
.heute-liste li:last-child, .kurz-liste li:last-child { border-bottom: none; }
.zeit { font-weight: 700; margin-right: 0.4rem; font-variant-numeric: tabular-nums; }
.mahlzeit-label { color: var(--color-text-muted); margin-right: 0.35rem; font-size: 0.85rem; }
.sub-tabs { display: flex; gap: 0.4rem; margin-bottom: 1rem; }
.sub-tabs button { background: var(--color-surface); border: 1px solid var(--color-border); font-size: 0.85rem; color: var(--color-text); }
.sub-tabs button.aktiv { background: var(--color-accent); color: #fdfbf3; border-color: var(--color-accent); }
.tage-nav { display: flex; flex-wrap: wrap; gap: 0.35rem; margin-bottom: 1rem; }
.tage-nav button { font-size: 0.8rem; padding: 0.35rem 0.6rem; background: var(--color-surface); border: 1px solid var(--color-border); color: var(--color-text); }
.tage-nav button.aktiv { background: var(--color-accent); color: #fdfbf3; }
.tage-nav button.heute:not(.aktiv) { border-color: var(--color-accent); }
.tag-plan { display: grid; gap: 0.75rem; margin-bottom: 1.5rem; }
.mahlzeit-karte { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.85rem 1rem; }
.mahlzeit-kopf { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.35rem; }
.mahlzeit-karte h4 { margin: 0; font-size: 0.9rem; color: var(--color-text-muted); }
.uhrzeit-badge {
  display: inline-block;
  padding: 0.15rem 0.5rem;
  border-radius: var(--radius-pill);
  background: var(--color-pill-bg);
  font-size: 0.78rem;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.was-label { margin: 0.25rem 0 0.1rem; font-size: 0.75rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.04em; color: var(--color-text-muted); }
.titel { font-weight: 700; margin: 0 0 0.3rem; font-size: 1.05rem; }
.beschreibung { margin: 0 0 0.4rem; font-size: 0.9rem; color: var(--color-text-muted); }
.material { margin: 0.4rem 0; padding-left: 1.2rem; font-size: 0.88rem; }
.aktionen { display: flex; flex-wrap: wrap; gap: 0.4rem; margin-top: 0.5rem; }
.form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 0.65rem; margin: 1rem 0; }
.form-grid label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.82rem; color: var(--color-text-muted); }
.form-grid .full { grid-column: 1 / -1; }
.vorlagen-liste, .notizen-liste { display: grid; gap: 0.65rem; margin-bottom: 1.5rem; }
.vorlage-karte, .notiz-karte { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.85rem 1rem; font-size: 0.9rem; }
.meta { display: block; font-size: 0.8rem; color: var(--color-text-muted); margin: 0.2rem 0 0.4rem; }
.kategorie { display: inline-block; font-size: 0.72rem; text-transform: uppercase; color: var(--color-text-muted); margin-bottom: 0.25rem; }
.liste { width: 100%; border-collapse: collapse; background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); margin: 1rem 0; font-size: 0.88rem; }
.liste th, .liste td { text-align: left; padding: 0.5rem 0.65rem; border-bottom: 1px solid var(--color-border); vertical-align: middle; }
.liste th { color: var(--color-text-muted); font-weight: 700; font-size: 0.78rem; }
.zellen-input { width: 100%; font-size: 0.85rem; padding: 0.35rem 0.5rem; }
tr.warn { background: #fdf8f0; }
.koepfe-zeile { display: flex; flex-wrap: wrap; gap: 0.4rem; align-items: center; margin-bottom: 0.75rem; }
.kopf-badge { font-size: 0.78rem; padding: 0.15rem 0.45rem; border-radius: var(--radius-pill); background: var(--color-surface-muted); border: 1px solid var(--color-border); }
.kopf-badge.heute { border-color: var(--color-accent); font-weight: 600; }
.klein-hinweis { display: block; font-size: 0.75rem; color: var(--color-text-muted); margin-top: 0.15rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.error { color: var(--color-danger); }
button.klein { font-size: 0.75rem; padding: 0.25rem 0.55rem; }
</style>
