<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import ProgrammHoeck from './ProgrammHoeck.vue'
import {
  bloeckeFuerTag,
  formatProgrammTag,
  formatProgrammZeit,
  heuteIso,
  type BlockCode,
  type ProgrammBlockBasis,
} from '../../lib/programmUtils'

const props = defineProps<{
  lagerId: string
  tag: string
  bloecke: ProgrammBlockBasis[]
  sessionUserId: string
  userName: string
  alleTage: string[]
}>()

const router = useRouter()

const blocksFuerTag = computed(() =>
  bloeckeFuerTag(props.bloecke, props.tag).sort((a, b) =>
    (a.start_zeit ?? '').localeCompare(b.start_zeit ?? ''),
  ),
)

function zuBlock(id: string) {
  router.push(`/lager/${props.lagerId}/programm/block/${id}`)
}

function tagWechseln(tag: string) {
  router.push(`/lager/${props.lagerId}/programm/tag/${tag}`)
}

function neuBlock() {
  router.push({ path: `/lager/${props.lagerId}/programm/neu`, query: { tag: props.tag } })
}

function codeClass(code: BlockCode) {
  return `code-${code}`
}
</script>

<template>
  <div class="programm-tag">
    <div class="tag-kopf">
      <div>
        <router-link :to="`/lager/${lagerId}/programm`" class="zurueck-link">← Gesamtprogramm</router-link>
        <h3>{{ formatProgrammTag(tag) }}</h3>
      </div>
      <button type="button" @click="neuBlock">+ Programm an diesem Tag</button>
    </div>

    <nav v-if="alleTage.length" class="tage-nav">
      <button
        v-for="t in alleTage"
        :key="t"
        type="button"
        :class="{ aktiv: t === tag, heute: t === heuteIso() }"
        @click="tagWechseln(t)"
      >
        {{ formatProgrammTag(t) }}
      </button>
    </nav>

    <ProgrammHoeck
      :lager-id="lagerId"
      :tag="tag"
      :bloecke="bloecke"
      :user-id="sessionUserId"
      :user-name="userName"
    />

    <p v-if="!blocksFuerTag.length" class="hint">Noch keine Programmblöcke an diesem Tag.</p>

    <div v-else class="timetable">
      <button
        v-for="b in blocksFuerTag"
        :key="b.id"
        type="button"
        class="block-zeile"
        @click="zuBlock(b.id)"
      >
        <span class="zeit">{{ formatProgrammZeit(b.start_zeit) }}–{{ formatProgrammZeit(b.end_zeit) }}</span>
        <span class="code" :class="codeClass(b.code)">{{ b.code }}</span>
        <span class="titel">{{ b.nummer ? b.nummer + ' ' : '' }}{{ b.titel }}</span>
        <span class="verantwortlich">{{ b.verantwortlich ?? '–' }}</span>
        <span class="bearbeiten-hinweis">Bearbeiten →</span>
      </button>
    </div>
  </div>
</template>

<style scoped>
.tag-kopf { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: flex-start; gap: 0.75rem; margin-bottom: 1rem; }
.tag-kopf h3 { margin: 0.15rem 0 0; }
.zurueck-link { font-size: 0.85rem; font-weight: 600; color: var(--color-accent); text-decoration: none; }
.zurueck-link:hover { text-decoration: underline; }
.tage-nav { display: flex; flex-wrap: wrap; gap: 0.35rem; margin-bottom: 1rem; }
.tage-nav button { font-size: 0.8rem; padding: 0.35rem 0.6rem; background: var(--color-surface); border: 1px solid var(--color-border); color: var(--color-text); border-radius: var(--radius-md); }
.tage-nav button.aktiv { background: var(--color-accent); color: #fdfbf3; border-color: var(--color-accent); }
.tage-nav button.heute:not(.aktiv) { border-color: var(--color-accent); }
.timetable { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); overflow: hidden; }
.block-zeile {
  display: grid; grid-template-columns: 100px 40px 1fr 140px auto; gap: 0.75rem; align-items: center;
  width: 100%; padding: 0.6rem 0.9rem; border: none; border-bottom: 1px solid var(--color-border);
  background: transparent; color: var(--color-text); text-align: left; cursor: pointer; border-radius: 0;
}
.block-zeile:hover { background: var(--color-surface-muted); }
.zeit { font-size: 0.85rem; color: var(--color-text-muted); font-variant-numeric: tabular-nums; }
.code { font-size: 0.7rem; font-weight: 700; text-align: center; padding: 0.2rem 0; border-radius: var(--radius-pill); color: #fdfbf3; }
.code-LP { background: #6b7fa8; } .code-LS { background: var(--color-accent); } .code-LA { background: #c98a3f; } .code-ES { background: #8a7f68; }
.titel { font-size: 0.95rem; }
.verantwortlich { font-size: 0.8rem; color: var(--color-text-muted); text-align: right; }
.bearbeiten-hinweis { font-size: 0.75rem; color: var(--color-accent); white-space: nowrap; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
