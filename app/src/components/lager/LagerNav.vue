<script setup lang="ts">
import { tabIdForAemtli } from '../../lib/aemtliSlug'

interface AemtliTab {
  id: string
  name: string
}

defineProps<{
  activeTab: string
  meineAemtli: AemtliTab[]
  isLeitung: boolean
  hatKuecheTab: boolean
  leiterAnfragen: number
  tnCount: number
  leiterCount: number
}>()

const emit = defineEmits<{ navigate: [tab: string] }>()

function nav(tab: string) {
  emit('navigate', tab)
}
</script>

<template>
  <nav class="lager-nav">
    <div class="nav-gruppe">
      <span class="nav-label">Start</span>
      <button :class="{ aktiv: activeTab === 'dashboard' }" @click="nav('dashboard')">Dashboard</button>
    </div>

    <div class="nav-gruppe">
      <span class="nav-label">Tagesbetrieb</span>
      <button :class="{ aktiv: activeTab === 'programm' }" @click="nav('programm')">Programm</button>
    </div>

    <div class="nav-gruppe">
      <span class="nav-label">Leute</span>
      <button :class="{ aktiv: activeTab === 'teilnehmer' }" @click="nav('teilnehmer')">
        Teilnehmer <span class="badge">{{ tnCount }}</span>
      </button>
      <button :class="{ aktiv: activeTab === 'leiter' }" @click="nav('leiter')">
        Leiter <span class="badge">{{ leiterCount }}</span>
        <span v-if="leiterAnfragen && isLeitung" class="badge warn">{{ leiterAnfragen }} offen</span>
      </button>
      <button :class="{ aktiv: activeTab === 'gruppen' }" @click="nav('gruppen')">Gruppen</button>
    </div>

    <div v-if="meineAemtli.length" class="nav-gruppe">
      <span class="nav-label">Meine Ämtli</span>
      <button
        v-for="a in meineAemtli"
        :key="a.id"
        :class="{ aktiv: activeTab === tabIdForAemtli(a.name) }"
        @click="nav(tabIdForAemtli(a.name))"
      >
        {{ a.name }}
      </button>
    </div>

    <div class="nav-gruppe">
      <span class="nav-label">Organisation</span>
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

    <div v-if="isLeitung" class="nav-gruppe">
      <span class="nav-label">Leitung</span>
      <button :class="{ aktiv: activeTab === 'team' }" @click="nav('team')">Team &amp; Zugriff</button>
      <button :class="{ aktiv: activeTab === 'reminders' }" @click="nav('reminders')">Erinnerungen</button>
      <button :class="{ aktiv: activeTab === 'einstellungen' }" @click="nav('einstellungen')">Einstellungen</button>
    </div>
  </nav>
</template>

<style scoped>
.lager-nav {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  margin: 1rem 0 1.25rem;
  padding-bottom: 1rem;
  border-bottom: 1px solid var(--color-border);
}
.nav-gruppe { display: flex; flex-wrap: wrap; align-items: center; gap: 0.35rem; }
.nav-label {
  width: 100%;
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--color-text-muted);
  margin-bottom: 0.15rem;
}
.nav-gruppe button {
  background: var(--color-surface);
  color: var(--color-text);
  border: 1px solid var(--color-border);
  font-size: 0.85rem;
  padding: 0.4rem 0.75rem;
  border-radius: var(--radius-md);
}
.nav-gruppe button.aktiv {
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
