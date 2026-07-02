<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { tabIdForAemtli } from '../../lib/aemtliSlug'

interface AemtliTab {
  id: string
  name: string
}

const props = defineProps<{
  activeTab: string
  meineAemtli: AemtliTab[]
  isLeitung: boolean
  hatKuecheTab: boolean
  leiterAnfragen: number
  tnCount: number
  leiterCount: number
}>()

const emit = defineEmits<{ navigate: [tab: string] }>()

const offen = ref<Record<string, boolean>>({})

function nav(tab: string) {
  emit('navigate', tab)
}

function toggle(id: string) {
  offen.value[id] = !offen.value[id]
}

function istOffen(id: string) {
  return !!offen.value[id]
}

function sectionIdForTab(tab: string): string | null {
  if (tab === 'dashboard') return 'start'
  if (tab === 'programm') return 'tagesbetrieb'
  if (['teilnehmer', 'leiter', 'gruppen'].includes(tab)) return 'leute'
  if (tab.startsWith('aemtli:')) return 'aemtli'
  if (['einkauf', 'quittungen'].includes(tab)) return 'organisation'
  if (['team', 'reminders', 'einstellungen'].includes(tab)) return 'leitung'
  return null
}

watch(
  () => props.activeTab,
  (tab) => {
    const id = sectionIdForTab(tab)
    if (id) offen.value[id] = true
  },
  { immediate: true },
)

const hatAemtliSektion = computed(() => props.meineAemtli.length > 0)
</script>

<template>
  <nav class="lager-nav">
    <div class="nav-gruppe">
      <button type="button" class="nav-gruppe-kopf" :aria-expanded="istOffen('start')" @click="toggle('start')">
        <span class="nav-label">Start</span>
        <span class="nav-pfeil" :class="{ offen: istOffen('start') }">›</span>
      </button>
      <div v-show="istOffen('start')" class="nav-inhalt">
        <button :class="{ aktiv: activeTab === 'dashboard' }" @click="nav('dashboard')">Dashboard</button>
      </div>
    </div>

    <div class="nav-gruppe">
      <button type="button" class="nav-gruppe-kopf" :aria-expanded="istOffen('tagesbetrieb')" @click="toggle('tagesbetrieb')">
        <span class="nav-label">Tagesbetrieb</span>
        <span class="nav-pfeil" :class="{ offen: istOffen('tagesbetrieb') }">›</span>
      </button>
      <div v-show="istOffen('tagesbetrieb')" class="nav-inhalt">
        <button :class="{ aktiv: activeTab === 'programm' }" @click="nav('programm')">Programm</button>
      </div>
    </div>

    <div class="nav-gruppe">
      <button type="button" class="nav-gruppe-kopf" :aria-expanded="istOffen('leute')" @click="toggle('leute')">
        <span class="nav-label">Leute</span>
        <span class="nav-pfeil" :class="{ offen: istOffen('leute') }">›</span>
      </button>
      <div v-show="istOffen('leute')" class="nav-inhalt">
        <button :class="{ aktiv: activeTab === 'teilnehmer' }" @click="nav('teilnehmer')">
          Teilnehmer <span class="badge">{{ tnCount }}</span>
        </button>
        <button :class="{ aktiv: activeTab === 'leiter' }" @click="nav('leiter')">
          Leiter <span class="badge">{{ leiterCount }}</span>
          <span v-if="leiterAnfragen && isLeitung" class="badge warn">{{ leiterAnfragen }} offen</span>
        </button>
        <button :class="{ aktiv: activeTab === 'gruppen' }" @click="nav('gruppen')">Gruppen</button>
      </div>
    </div>

    <div v-if="hatAemtliSektion" class="nav-gruppe">
      <button type="button" class="nav-gruppe-kopf" :aria-expanded="istOffen('aemtli')" @click="toggle('aemtli')">
        <span class="nav-label">Meine Ämtli</span>
        <span class="nav-pfeil" :class="{ offen: istOffen('aemtli') }">›</span>
      </button>
      <div v-show="istOffen('aemtli')" class="nav-inhalt">
        <button
          v-for="a in meineAemtli"
          :key="a.id"
          :class="{ aktiv: activeTab === tabIdForAemtli(a.name) }"
          @click="nav(tabIdForAemtli(a.name))"
        >
          {{ a.name }}
        </button>
      </div>
    </div>

    <div class="nav-gruppe">
      <button type="button" class="nav-gruppe-kopf" :aria-expanded="istOffen('organisation')" @click="toggle('organisation')">
        <span class="nav-label">Organisation</span>
        <span class="nav-pfeil" :class="{ offen: istOffen('organisation') }">›</span>
      </button>
      <div v-show="istOffen('organisation')" class="nav-inhalt">
        <button
          v-if="!hatKuecheTab"
          :class="{ aktiv: activeTab === 'einkauf' }"
          @click="nav('einkauf')"
        >
          Einkaufsliste
        </button>
        <button :class="{ aktiv: activeTab === 'quittungen' }" @click="nav('quittungen')">
          Quittungen
        </button>
      </div>
    </div>

    <div v-if="isLeitung" class="nav-gruppe">
      <button type="button" class="nav-gruppe-kopf" :aria-expanded="istOffen('leitung')" @click="toggle('leitung')">
        <span class="nav-label">Leitung</span>
        <span class="nav-pfeil" :class="{ offen: istOffen('leitung') }">›</span>
      </button>
      <div v-show="istOffen('leitung')" class="nav-inhalt">
        <button :class="{ aktiv: activeTab === 'team' }" @click="nav('team')">Team &amp; Zugriff</button>
        <button :class="{ aktiv: activeTab === 'reminders' }" @click="nav('reminders')">Erinnerungen</button>
        <button :class="{ aktiv: activeTab === 'einstellungen' }" @click="nav('einstellungen')">Einstellungen</button>
      </div>
    </div>
  </nav>
</template>

<style scoped>
.lager-nav {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  margin: 1rem 0 1.25rem;
  padding-bottom: 1rem;
  border-bottom: 1px solid var(--color-border);
}
.nav-gruppe { display: flex; flex-direction: column; gap: 0.25rem; }
.nav-gruppe-kopf {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: 100%;
  background: none;
  border: none;
  padding: 0.35rem 0;
  cursor: pointer;
  text-align: left;
}
.nav-gruppe-kopf:hover .nav-label { color: var(--color-text); }
.nav-label {
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--color-text-muted);
}
.nav-pfeil {
  font-size: 1rem;
  color: var(--color-text-muted);
  transform: rotate(0deg);
  transition: transform 0.15s ease;
  line-height: 1;
}
.nav-pfeil.offen { transform: rotate(90deg); }
.nav-inhalt { display: flex; flex-wrap: wrap; align-items: center; gap: 0.35rem; padding-left: 0.15rem; }
.nav-inhalt button {
  background: var(--color-surface);
  color: var(--color-text);
  border: 1px solid var(--color-border);
  font-size: 0.85rem;
  padding: 0.4rem 0.75rem;
  border-radius: var(--radius-md);
}
.nav-inhalt button.aktiv {
  background: var(--color-accent);
  color: #fdfbf3;
  border-color: var(--color-accent);
}
.badge {
  display: inline-block;
  margin-left: 0.25rem;
  padding: 0.05rem 0.4rem;
  border-radius: var(--radius-pill);
  font-size: 0.72rem;
  background: rgba(0, 0, 0, 0.12);
}
button.aktiv .badge { background: rgba(255, 255, 255, 0.25); }
.badge.warn { background: #c98a3f; color: #fff; }
button.aktiv .badge.warn { background: rgba(255, 255, 255, 0.35); color: #fff; }
</style>
