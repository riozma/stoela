<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'

type MahlzeitTyp = 'fruehstueck' | 'zmittag' | 'znacht' | 'jause'

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
  beschreibung: string | null
  material: MaterialZeile[]
}

interface Mahlzeit {
  id: string
  tag: string
  mahlzeit: MahlzeitTyp
  titel: string
  beschreibung: string | null
  material: MaterialZeile[]
  vorlage_id: string | null
}

interface Ausnahme {
  id: string
  tag: string
  vorlage_id: string
}

const props = defineProps<{
  lagerId: string
  startDatum: string | null
  endDatum: string | null
}>()

const emit = defineEmits<{ einkauf: [] }>()

const vorlagen = ref<Vorlage[]>([])
const mahlzeiten = ref<Mahlzeit[]>([])
const ausnahmen = ref<Ausnahme[]>([])
const fehler = ref('')
const ansicht = ref<'plan' | 'vorlagen'>('plan')
const ausgewaehlterTag = ref<string>('')

const vorlageForm = ref({
  name: '',
  mahlzeit: 'zmittag' as MahlzeitTyp,
  wochentag: 1,
  beschreibung: '',
  materialText: '',
})

const einzelForm = ref({
  tag: '',
  mahlzeit: 'zmittag' as MahlzeitTyp,
  titel: '',
  beschreibung: '',
  materialText: '',
})

const mahlzeitLabels: Record<MahlzeitTyp, string> = {
  fruehstueck: 'Frühstück',
  zmittag: 'Zmorgen',
  znacht: 'Znacht',
  jause: 'Jause',
}

const wochentage = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa']

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

function materialAnzeige(material: MaterialZeile[]) {
  return material.map((m) => (m.menge ? `${m.menge} ${m.einheit} ${m.name}`.trim() : m.name)).join('\n')
}

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

function formatTag(tag: string) {
  const d = new Date(tag + 'T00:00:00')
  return new Intl.DateTimeFormat('de-CH', { weekday: 'short', day: 'numeric', month: 'numeric' }).format(d)
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
      beschreibung: v.beschreibung,
      material: v.material,
      vorlageId: v.id,
    }
  }
  if (vs.length > 1) {
    return {
      quelle: 'vorlage',
      titel: vs.map((v) => v.name).join(' / '),
      beschreibung: vs.map((v) => v.beschreibung).filter(Boolean).join(' · ') || null,
      material: vs.flatMap((v) => v.material),
    }
  }
  return null
}

async function laden() {
  const [{ data: v }, { data: m }, { data: a }] = await Promise.all([
    supabase.from('mahlzeit_vorlagen').select('*').eq('lager_id', props.lagerId).order('name'),
    supabase.from('mahlzeiten').select('*').eq('lager_id', props.lagerId).order('tag'),
    supabase.from('mahlzeit_ausnahmen').select('*').eq('lager_id', props.lagerId),
  ])
  vorlagen.value = (v ?? []).map((row) => ({ ...row, material: (row.material as MaterialZeile[]) ?? [] }))
  mahlzeiten.value = (m ?? []).map((row) => ({ ...row, material: (row.material as MaterialZeile[]) ?? [] }))
  ausnahmen.value = a ?? []
  if (!ausgewaehlterTag.value && tage.value.length) ausgewaehlterTag.value = tage.value[0]
}

onMounted(laden)

async function vorlageSpeichern() {
  fehler.value = ''
  const { error } = await supabase.from('mahlzeit_vorlagen').insert({
    lager_id: props.lagerId,
    name: vorlageForm.value.name,
    mahlzeit: vorlageForm.value.mahlzeit,
    wochentag: vorlageForm.value.wochentag,
    beschreibung: vorlageForm.value.beschreibung || null,
    material: parseMaterial(vorlageForm.value.materialText),
  })
  if (error) { fehler.value = error.message; return }
  vorlageForm.value = { name: '', mahlzeit: 'zmittag', wochentag: 1, beschreibung: '', materialText: '' }
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
      titel: einzelForm.value.titel,
      beschreibung: einzelForm.value.beschreibung || null,
      material: parseMaterial(einzelForm.value.materialText),
      vorlage_id: null,
    },
    { onConflict: 'lager_id,tag,mahlzeit' },
  )
  if (error) { fehler.value = error.message; return }
  einzelForm.value = { tag: '', mahlzeit: 'zmittag', titel: '', beschreibung: '', materialText: '' }
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

async function ausnahmeEntfernen(tag: string, vorlageId: string) {
  await supabase.from('mahlzeit_ausnahmen').delete().eq('lager_id', props.lagerId).eq('tag', tag).eq('vorlage_id', vorlageId)
  await laden()
}

async function materialZuEinkauf(material: MaterialZeile[]) {
  if (!material.length) return
  const rows = material.map((m) => ({
    lager_id: props.lagerId,
    name: m.name,
    menge: m.menge ? Number(m.menge) : null,
    einheit: m.einheit || null,
    bereich: 'kueche',
    notiz: 'Aus Kochplan',
  }))
  await supabase.from('einkaufsliste_items').insert(rows)
  emit('einkauf')
}
</script>

<template>
  <section class="kueche">
    <header class="kopf">
      <h2>Küche – Kochplan</h2>
      <button class="secondary" @click="emit('einkauf')">Zur Einkaufsliste →</button>
    </header>

    <nav class="sub-tabs">
      <button :class="{ aktiv: ansicht === 'plan' }" @click="ansicht = 'plan'">Wochenplan</button>
      <button :class="{ aktiv: ansicht === 'vorlagen' }" @click="ansicht = 'vorlagen'">Wiederkehrende Mahlzeiten</button>
    </nav>

    <p v-if="fehler" class="error">{{ fehler }}</p>

    <div v-if="ansicht === 'plan'">
      <p v-if="!tage.length" class="hint">Lager-Start und -Ende in den Einstellungen setzen, um den Plan anzuzeigen.</p>

      <nav v-else class="tage-nav">
        <button
          v-for="tag in tage"
          :key="tag"
          :class="{ aktiv: tag === ausgewaehlterTag }"
          @click="ausgewaehlterTag = tag"
        >
          {{ formatTag(tag) }}
        </button>
      </nav>

      <div v-if="ausgewaehlterTag" class="tag-plan">
        <div v-for="typ in (['fruehstueck', 'zmittag', 'znacht', 'jause'] as MahlzeitTyp[])" :key="typ" class="mahlzeit-karte">
          <h4>{{ mahlzeitLabels[typ] }}</h4>
          <template v-if="planFuerSlot(ausgewaehlterTag, typ)">
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
                Material → Einkauf
              </button>
              <button
                v-if="planFuerSlot(ausgewaehlterTag, typ)!.mahlzeitId"
                class="secondary klein"
                @click="einzelLoeschen(planFuerSlot(ausgewaehlterTag, typ)!.mahlzeitId!)"
              >
                Einzelmahlzeit löschen
              </button>
              <button
                v-if="planFuerSlot(ausgewaehlterTag, typ)!.vorlageId && planFuerSlot(ausgewaehlterTag, typ)!.quelle === 'vorlage'"
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

      <h3>Einzelne Mahlzeit hinzufügen / überschreiben</h3>
      <form class="form-grid" @submit.prevent="einzelSpeichern">
        <label>Tag <input v-model="einzelForm.tag" type="date" :placeholder="ausgewaehlterTag" /></label>
        <label>Mahlzeit
          <select v-model="einzelForm.mahlzeit">
            <option v-for="(label, key) in mahlzeitLabels" :key="key" :value="key">{{ label }}</option>
          </select>
        </label>
        <label>Titel <input v-model="einzelForm.titel" required placeholder="z.B. Rösti und Salat" /></label>
        <label>Beschreibung <textarea v-model="einzelForm.beschreibung" rows="2"></textarea></label>
        <label class="full">Material (eine Zeile pro Zutat, z.B. «2 kg Kartoffeln»)
          <textarea v-model="einzelForm.materialText" rows="4"></textarea>
        </label>
        <button type="submit">Speichern</button>
      </form>
    </div>

    <div v-if="ansicht === 'vorlagen'">
      <h3>Wiederkehrende Mahlzeiten</h3>
      <div v-if="vorlagen.length" class="vorlagen-liste">
        <div v-for="v in vorlagen" :key="v.id" class="vorlage-karte">
          <strong>{{ v.name }}</strong>
          <span class="meta">{{ mahlzeitLabels[v.mahlzeit] }} · jeden {{ wochentage[v.wochentag ?? 0] }}</span>
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
        <label>Name <input v-model="vorlageForm.name" required /></label>
        <label>Mahlzeit
          <select v-model="vorlageForm.mahlzeit">
            <option v-for="(label, key) in mahlzeitLabels" :key="key" :value="key">{{ label }}</option>
          </select>
        </label>
        <label>Wochentag
          <select v-model.number="vorlageForm.wochentag">
            <option v-for="(wd, i) in wochentage" :key="i" :value="i">{{ wd }}</option>
          </select>
        </label>
        <label>Beschreibung <textarea v-model="vorlageForm.beschreibung" rows="2"></textarea></label>
        <label class="full">Material
          <textarea v-model="vorlageForm.materialText" rows="4" placeholder="2 kg Kartoffeln&#10;1 Bund Schnittlauch"></textarea>
        </label>
        <button type="submit">Vorlage speichern</button>
      </form>
    </div>
  </section>
</template>

<style scoped>
.kopf { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 1rem; }
.kopf h2 { margin: 0; }
.sub-tabs { display: flex; gap: 0.4rem; margin-bottom: 1rem; }
.sub-tabs button { background: var(--color-surface); border: 1px solid var(--color-border); font-size: 0.85rem; }
.sub-tabs button.aktiv { background: var(--color-accent); color: #fdfbf3; border-color: var(--color-accent); }
.tage-nav { display: flex; flex-wrap: wrap; gap: 0.35rem; margin-bottom: 1rem; }
.tage-nav button { font-size: 0.8rem; padding: 0.35rem 0.6rem; background: var(--color-surface); border: 1px solid var(--color-border); }
.tage-nav button.aktiv { background: var(--color-accent); color: #fdfbf3; }
.tag-plan { display: grid; gap: 0.75rem; margin-bottom: 1.5rem; }
.mahlzeit-karte { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.85rem 1rem; }
.mahlzeit-karte h4 { margin: 0 0 0.4rem; font-size: 0.9rem; color: var(--color-text-muted); }
.titel { font-weight: 700; margin: 0 0 0.3rem; }
.beschreibung { margin: 0 0 0.4rem; font-size: 0.9rem; }
.material { margin: 0.4rem 0; padding-left: 1.2rem; font-size: 0.88rem; }
.aktionen { display: flex; flex-wrap: wrap; gap: 0.4rem; margin-top: 0.5rem; }
.form-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 0.65rem; margin: 1rem 0; }
.form-grid label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.82rem; color: var(--color-text-muted); }
.form-grid .full { grid-column: 1 / -1; }
.vorlagen-liste { display: grid; gap: 0.65rem; margin-bottom: 1.5rem; }
.vorlage-karte { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.85rem 1rem; font-size: 0.9rem; }
.meta { display: block; font-size: 0.8rem; color: var(--color-text-muted); margin: 0.2rem 0 0.4rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.error { color: var(--color-danger); }
button.klein { font-size: 0.75rem; padding: 0.25rem 0.55rem; }
</style>
