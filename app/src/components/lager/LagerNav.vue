<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { aemtliSlug, tabIdForAemtli } from '../../lib/aemtliSlug'

interface AemtliTab {
  id: string
  name: string
}

const props = defineProps<{
  lagerId: string
  activeTab: string
  programmLink?: string
  meineAemtli: AemtliTab[]
  isLeitung: boolean
  hatKuecheTab: boolean
  leiterAnfragen: number
  tnCount: number
  leiterCount: number
  mobileOpen?: boolean
  moerderliAktiv?: boolean
}>()

const emit = defineEmits<{ close: [] }>()

const route = useRoute()
const base = computed(() => `/lager/${props.lagerId}`)

function sectionPath(section: string) {
  return `${base.value}/${section}`
}

function aemtliPath(name: string) {
  return `${base.value}/aemtli/${aemtliSlug(name)}`
}

function isActive(section: string) {
  return props.activeTab === section
}

function isAemtliActive(name: string) {
  return props.activeTab === tabIdForAemtli(name)
}

function gruppeAktiv(sections: string[]) {
  return sections.some((s) => isActive(s))
}

function aemtliGruppeAktiv() {
  return props.activeTab.startsWith('aemtli:')
}

function navKlick() {
  if (route.meta?.mobileNavClose !== false) emit('close')
}
</script>

<template>
  <nav class="lager-top-nav" :class="{ 'mobile-open': mobileOpen }" aria-label="Lager-Navigation">
    <router-link to="/" class="nav-link alle-lager-nav" @click="navKlick">
      ← Start
    </router-link>

    <router-link :to="sectionPath('dashboard')" class="nav-link" :class="{ aktiv: isActive('dashboard') }" @click="navKlick">
      Dashboard
    </router-link>

    <router-link :to="sectionPath('chatbot')" class="nav-link" :class="{ aktiv: isActive('chatbot') }" @click="navKlick">
      Chatbot
    </router-link>

    <router-link v-if="moerderliAktiv" :to="`${base}/moerderli`" class="nav-link moerderli-nav" @click="navKlick">
      Mörderli
    </router-link>

    <router-link :to="programmLink ?? sectionPath('programm')" class="nav-link" :class="{ aktiv: isActive('programm') }" @click="navKlick">
      Programm
    </router-link>

    <div class="nav-dropdown" data-label="Leute" :class="{ 'gruppe-aktiv': gruppeAktiv(['teilnehmer', 'leiter', 'gruppen']) }">
      <span class="nav-dropdown-label">Leute</span>
      <div class="nav-dropdown-menu">
        <router-link :to="sectionPath('teilnehmer')" class="nav-link" :class="{ aktiv: isActive('teilnehmer') }" @click="navKlick">
          Teilnehmer <span class="badge">{{ tnCount }}</span>
        </router-link>
        <router-link :to="sectionPath('leiter')" class="nav-link" :class="{ aktiv: isActive('leiter') }" @click="navKlick">
          Leiter <span class="badge">{{ leiterCount }}</span>
          <span v-if="leiterAnfragen && isLeitung" class="badge warn">{{ leiterAnfragen }} offen</span>
        </router-link>
        <router-link :to="sectionPath('gruppen')" class="nav-link" :class="{ aktiv: isActive('gruppen') }" @click="navKlick">
          Gruppen
        </router-link>
      </div>
    </div>

    <div v-if="meineAemtli.length" class="nav-dropdown" data-label="Meine Ämtli" :class="{ 'gruppe-aktiv': aemtliGruppeAktiv() }">
      <span class="nav-dropdown-label">Meine Ämtli</span>
      <div class="nav-dropdown-menu">
        <router-link
          v-for="a in meineAemtli"
          :key="a.id"
          :to="aemtliPath(a.name)"
          class="nav-link"
          :class="{ aktiv: isAemtliActive(a.name) }"
          @click="navKlick"
        >
          {{ a.name }}
        </router-link>
      </div>
    </div>

    <div class="nav-dropdown" data-label="Vorbereitung" :class="{ 'gruppe-aktiv': gruppeAktiv(['fahrplan', 'vorweekend', 'elterninfo']) }">
      <span class="nav-dropdown-label">Vorbereitung</span>
      <div class="nav-dropdown-menu">
        <router-link :to="sectionPath('fahrplan')" class="nav-link" :class="{ aktiv: isActive('fahrplan') }" @click="navKlick">
          Fahrplan
        </router-link>
        <router-link :to="sectionPath('vorweekend')" class="nav-link" :class="{ aktiv: isActive('vorweekend') }" @click="navKlick">
          Vorweekend
        </router-link>
        <router-link :to="sectionPath('elterninfo')" class="nav-link" :class="{ aktiv: isActive('elterninfo') }" @click="navKlick">
          Elterninfo
        </router-link>
      </div>
    </div>

    <div class="nav-dropdown" data-label="Organisation" :class="{ 'gruppe-aktiv': gruppeAktiv(['einkauf', 'quittungen']) }">
      <span class="nav-dropdown-label">Organisation</span>
      <div class="nav-dropdown-menu">
        <router-link
          v-if="!hatKuecheTab"
          :to="sectionPath('einkauf')"
          class="nav-link"
          :class="{ aktiv: isActive('einkauf') }"
          @click="navKlick"
        >
          Einkaufsliste
        </router-link>
        <router-link :to="sectionPath('quittungen')" class="nav-link" :class="{ aktiv: isActive('quittungen') }" @click="navKlick">
          Quittungen
        </router-link>
      </div>
    </div>

    <div v-if="isLeitung" class="nav-dropdown" data-label="Leitung" :class="{ 'gruppe-aktiv': gruppeAktiv(['gemini', 'team', 'einstellungen', 'statistik']) }">
      <span class="nav-dropdown-label">Leitung</span>
      <div class="nav-dropdown-menu">
        <router-link :to="sectionPath('gemini')" class="nav-link" :class="{ aktiv: isActive('gemini') }" @click="navKlick">
          Gemini
        </router-link>
        <router-link :to="sectionPath('statistik')" class="nav-link" :class="{ aktiv: isActive('statistik') }" @click="navKlick">
          Statistik
        </router-link>
        <router-link :to="sectionPath('team')" class="nav-link" :class="{ aktiv: isActive('team') }" @click="navKlick">
          Team &amp; Zugriff
        </router-link>
        <router-link :to="sectionPath('einstellungen')" class="nav-link" :class="{ aktiv: isActive('einstellungen') }" @click="navKlick">
          Einstellungen
        </router-link>
      </div>
    </div>
  </nav>
</template>

<style scoped>
.lager-top-nav {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 0.25rem 0.5rem;
  width: 100%;
  padding: 0.35rem 1.25rem 0.75rem;
  box-sizing: border-box;
}
.nav-link {
  display: inline-flex;
  align-items: center;
  gap: 0.2rem;
  padding: 0.4rem 0.75rem;
  border-radius: var(--radius-md);
  font-size: 0.85rem;
  color: var(--color-text);
  text-decoration: none;
  border: 1px solid transparent;
  background: transparent;
  white-space: nowrap;
}
.nav-link:hover {
  background: var(--color-surface-muted);
  border-color: var(--color-border);
}
.nav-link.aktiv {
  background: var(--color-accent);
  color: #fdfbf3;
  border-color: var(--color-accent);
}
.nav-dropdown { position: relative; }
.nav-dropdown-label {
  display: inline-flex;
  align-items: center;
  padding: 0.4rem 0.75rem;
  font-size: 0.85rem;
  font-weight: 600;
  color: var(--color-text-muted);
  cursor: default;
  border-radius: var(--radius-md);
  border: 1px solid transparent;
}
.nav-dropdown:hover .nav-dropdown-label,
.nav-dropdown.gruppe-aktiv .nav-dropdown-label,
.nav-dropdown:focus-within .nav-dropdown-label {
  color: var(--color-text);
  background: var(--color-surface-muted);
  border-color: var(--color-border);
}
.nav-dropdown-menu {
  display: none;
  position: absolute;
  top: 100%;
  left: 0;
  z-index: 30;
  min-width: 11rem;
  padding: 0.35rem;
  margin-top: 0.15rem;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  box-shadow: 0 4px 14px rgba(0, 0, 0, 0.08);
  flex-direction: column;
}
.nav-dropdown:hover .nav-dropdown-menu,
.nav-dropdown:focus-within .nav-dropdown-menu {
  display: flex;
}
.nav-dropdown-menu .nav-link {
  width: 100%;
  border: none;
  border-radius: var(--radius-sm);
}
.badge {
  display: inline-block;
  margin-left: 0.15rem;
  padding: 0.05rem 0.35rem;
  border-radius: var(--radius-pill);
  font-size: 0.7rem;
  background: rgba(0, 0, 0, 0.1);
}
.nav-link.aktiv .badge { background: rgba(255, 255, 255, 0.25); }
.badge.warn { background: #c98a3f; color: #fff; }
.nav-link.aktiv .badge.warn { background: rgba(255, 255, 255, 0.35); color: #fff; }

@media (min-width: 769px) {
  .alle-lager-nav { display: none; }
}

@media (max-width: 768px) {
  .lager-top-nav {
    display: none;
    flex-direction: column;
    align-items: stretch;
    gap: 0.15rem;
    padding-bottom: 0.85rem;
    border-top: 1px solid var(--color-border);
  }
  .lager-top-nav.mobile-open { display: flex; }
  .nav-dropdown-label { display: none; }
  .nav-dropdown-menu {
    display: flex;
    position: static;
    box-shadow: none;
    border: none;
    padding: 0;
    margin: 0;
    min-width: 0;
  }
  .nav-dropdown::before {
    content: attr(data-label);
    font-size: 0.72rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--color-text-muted);
    padding: 0.5rem 0.75rem 0.15rem;
  }
  .nav-link { width: 100%; }
}
</style>
