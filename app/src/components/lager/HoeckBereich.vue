<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'

interface Leiter {
  id: string
  vorname: string
  nachname: string
}

interface HoeckRolle {
  id: string
  rolle: string
  ist_eigene: boolean
  sortierung: number
  leute: { id: string; leiter_id: string; vorname: string; nachname: string }[]
}

interface GruppenDienst {
  id: string
  tag: string
  dienst: string
  gruppen_name: string
}

const FIXE_ROLLEN = ['Tagwach', 'Zmorge', 'Nachtruhe']

const props = defineProps<{
  lagerId: string
  startDatum: string | null
  endDatum: string | null
  isLeitung: boolean
}>()

const alleLeiter = ref<Leiter[]>([])
const alleGruppen = ref<string[]>([])
const rollen = ref<HoeckRolle[]>([])
const gruppenDienste = ref<GruppenDienst[]>([])
const laden = ref(true)
const aktiverTag = ref('')
const eigeneRolleNeu = ref('')
const leiterFuerRolle = ref<Record<string, string>>({}) // hoeck_rolle_id -> leiter_id

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
  return new Intl.DateTimeFormat('de-CH', { weekday: 'short', day: 'numeric', month: 'numeric' }).format(new Date(tag + 'T00:00:00'))
}

async function ladeDaten() {
  laden.value = true

  // Leiter laden
  const { data: leiterData } = await supabase
    .from('anmeldungen_leiter')
    .select('id, vorname, nachname')
    .eq('lager_id', props.lagerId)
    .eq('status', 'bestaetigt')
    .order('nachname')
  alleLeiter.value = leiterData ?? []

  // Gruppen laden
  const { data: gruppenData } = await supabase
    .from('lagergruppen')
    .select('name')
    .eq('lager_id', props.lagerId)
    .order('name')
  alleGruppen.value = gruppenData?.map((g: any) => g.name) ?? []

  // Falls kein Tag aktiv ist, ersten nehmen
  if (!aktiverTag.value && tage.value.length) {
    aktiverTag.value = tage.value[0]
  }

  if (aktiverTag.value) {
    await ladeFuerTag(aktiverTag.value)
  }

  laden.value = false
}

async function ladeFuerTag(tag: string) {
  aktiverTag.value = tag

  // Rollen laden
  const { data: rollenData } = await supabase
    .rpc('get_hoeck_rollen_fuer_tag', { p_lager_id: props.lagerId, p_tag: tag })

  if (rollenData) {
    rollen.value = rollenData as HoeckRolle[]
  } else {
    // Fallback: direkter Query
    const { data } = await supabase
      .from('hoeck_rollen')
      .select('*')
      .eq('lager_id', props.lagerId)
      .eq('tag', tag)
      .order('sortierung')
    if (data) {
      // Lade Zuweisungen separat
      rollen.value = []
      for (const r of data) {
        const { data: zuw } = await supabase
          .from('hoeck_zuweisungen')
          .select('id, leiter_id')
          .eq('hoeck_rolle_id', r.id)
        const leute = (zuw ?? []).map((z: any) => {
          const l = alleLeiter.value.find((l) => l.id === z.leiter_id)
          return { id: z.id, leiter_id: z.leiter_id, vorname: l?.vorname ?? '', nachname: l?.nachname ?? '' }
        })
        rollen.value.push({
          id: r.id,
          rolle: r.rolle,
          ist_eigene: r.ist_eigene,
          sortierung: r.sortierung,
          leute,
        })
      }
    }
  }

  // Gruppen-Dienste laden
  const { data: diensteData } = await supabase
    .from('hoeck_gruppen_dienste')
    .select('*')
    .eq('lager_id', props.lagerId)
    .eq('tag', tag)
  gruppenDienste.value = diensteData ?? []
}

function tagWechseln(tag: string) {
  ladeFuerTag(tag)
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
    // Entfernen
    await supabase.from('hoeck_zuweisungen').delete().eq('id', existing.id)
    rolle.leute = rolle.leute.filter((l) => l.leiter_id !== leiterId)
  } else {
    // Hinzufügen
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
  const { data } = await supabase
    .from('hoeck_rollen')
    .insert({
      lager_id: props.lagerId,
      tag: aktiverTag.value,
      rolle: eigeneRolleNeu.value.trim(),
      ist_eigene: true,
      sortierung: 10 + rollen.value.length,
    })
    .select()
    .single()
  if (data) {
    rollen.value.push({
      id: data.id,
      rolle: data.rolle,
      ist_eigene: true,
      sortierung: data.sortierung,
      leute: [],
    })
  }
  eigeneRolleNeu.value = ''
}

async function eigeneRolleLoeschen(rolleId: string) {
  await supabase.from('hoeck_rollen').delete().eq('id', rolleId)
  rollen.value = rollen.value.filter((r) => r.id !== rolleId)
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
    <h3>Höck – Tages-Rollen & Dienste</h3>
    <p class="hint">Pro Tag Leiter für Rollen einteilen und Gruppen für Kiosk/Telefon zuweisen.</p>

    <nav v-if="tage.length" class="tage-nav">
      <button
        v-for="t in tage"
        :key="t"
        type="button"
        :class="{ aktiv: t === aktiverTag }"
        @click="tagWechseln(t)"
      >
        {{ formatTag(t) }}
      </button>
    </nav>

    <div v-if="laden" class="hint">Lade...</div>

    <template v-if="!laden && aktiverTag">
      <!-- Rollen -->
      <div class="rollen-section">
        <h4>Rollen</h4>
        <div v-for="rolle in rollen" :key="rolle.id" class="rolle-card">
          <div class="rolle-kopf">
            <strong>{{ rolle.rolle }}</strong>
            <button v-if="rolle.ist_eigene" type="button" class="klein sekundaer" @click="eigeneRolleLoeschen(rolle.id)">✕</button>
          </div>
          <div class="rolle-leute">
            <button
              v-for="l in alleLeiter"
              :key="l.id"
              type="button"
              class="leiter-chip"
              :class="{ aktiv: rolle.leute.some((r) => r.leiter_id === l.id) }"
              @click="toggleLeiterRolle(rolle.id, l.id)"
            >
              {{ l.vorname }}
            </button>
          </div>
        </div>

        <div v-if="isLeitung" class="eigene-rolle-form">
          <input v-model="eigeneRolleNeu" placeholder="Neue Rolle..." @keyup.enter="eigeneRolleHinzufuegen" />
          <button type="button" class="sekundaer klein" @click="eigeneRolleHinzufuegen">+</button>
        </div>
      </div>

      <!-- Gruppen-Dienste -->
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

.rollen-section { margin-bottom: 1.5rem; }
.rolle-card {
  background: var(--color-surface); border: 1px solid var(--color-border);
  border-radius: var(--radius-md); padding: 0.6rem 0.75rem; margin-bottom: 0.5rem;
}
.rolle-kopf { display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.4rem; }
.rolle-leute { display: flex; flex-wrap: wrap; gap: 0.3rem; }
.leiter-chip {
  padding: 0.2rem 0.5rem; font-size: 0.78rem; border: 1px solid var(--color-border);
  border-radius: var(--radius-pill); background: transparent; color: var(--color-text); cursor: pointer;
}
.leiter-chip.aktiv { background: var(--color-accent); color: #fdfbf3; border-color: var(--color-accent); }
.eigene-rolle-form { display: flex; gap: 0.4rem; margin-top: 0.5rem; }
.eigene-rolle-form input { flex: 1; padding: 0.35rem 0.5rem; border: 1px solid var(--color-border); border-radius: var(--radius-md); font-size: 0.85rem; }

.dienst-row { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.4rem; }
.dienst-row label { font-size: 0.85rem; font-weight: 600; min-width: 60px; }
.dienst-row select { flex: 1; padding: 0.35rem 0.5rem; border: 1px solid var(--color-border); border-radius: var(--radius-md); font-size: 0.85rem; max-width: 200px; }

.klein { font-size: 0.75rem; padding: 0.15rem 0.4rem; }
.sekundaer { background: transparent; border: 1px solid var(--color-border); color: var(--color-text); border-radius: var(--radius-md); cursor: pointer; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>