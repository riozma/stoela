<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import {
  RASTER_SLOT_MIN,
  RASTER_START_MIN,
  formatProgrammTag,
  formatProgrammZeit,
  heuteIso,
  lagerLaeuft,
  minutenZuLabel,
  rasterSlots,
  tageFuerSeite,
  tageZwischen,
  wocheIndexFuerTag,
  zeitZuMinuten,
  type BlockCode,
  type ProgrammBlockBasis,
} from '../../lib/programmUtils'

const props = defineProps<{
  lagerId: string
  startDatum: string | null
  endDatum: string | null
  bloecke: ProgrammBlockBasis[]
}>()

const router = useRouter()
const rasterModus = ref<'woche' | 'zweiwochen'>('woche')
const seitenIndex = ref(0)
const SLOT_HEIGHT_REM = 1.15

const tageProSeite = computed(() => (rasterModus.value === 'woche' ? 7 : 14))

const alleTage = computed(() => {
  if (props.startDatum && props.endDatum) return tageZwischen(props.startDatum, props.endDatum)
  const tags = new Set(props.bloecke.map((b) => b.tag).filter((t): t is string => !!t))
  return [...tags].sort()
})

const sichtbareTage = computed(() => tageFuerSeite(alleTage.value, seitenIndex.value, tageProSeite.value))

const maxSeite = computed(() =>
  alleTage.value.length ? Math.ceil(alleTage.value.length / tageProSeite.value) - 1 : 0,
)

const slots = computed(() => rasterSlots())

watch(
  () => [props.startDatum, props.endDatum, alleTage.value.length] as const,
  () => {
    const heute = heuteIso()
    if (lagerLaeuft(props.startDatum, props.endDatum) && alleTage.value.includes(heute)) {
      seitenIndex.value = wocheIndexFuerTag(alleTage.value, heute, tageProSeite.value)
    } else {
      seitenIndex.value = 0
    }
  },
  { immediate: true },
)

function bloeckeAnPosition(tag: string, slotMin: number) {
  return props.bloecke.filter((b) => {
    if (b.tag !== tag) return false
    const start = zeitZuMinuten(b.start_zeit)
    return start >= slotMin && start < slotMin + RASTER_SLOT_MIN
  })
}

function blockHoehe(b: ProgrammBlockBasis): number {
  const start = zeitZuMinuten(b.start_zeit)
  const end = Math.max(zeitZuMinuten(b.end_zeit), start + RASTER_SLOT_MIN)
  const span = Math.ceil((end - start) / RASTER_SLOT_MIN)
  return Math.max(1, span)
}

function blockTopOffsetRem(b: ProgrammBlockBasis, slotMin: number): number {
  const start = zeitZuMinuten(b.start_zeit)
  const diff = start - slotMin
  return diff <= 0 ? 0 : (diff / RASTER_SLOT_MIN) * SLOT_HEIGHT_REM
}

function zuBlock(id: string) {
  router.push(`/lager/${props.lagerId}/programm/block/${id}`)
}

function zuTag(tag: string) {
  router.push(`/lager/${props.lagerId}/programm/tag/${tag}`)
}

function neuBlock(tag?: string, typ?: string) {
  router.push({
    path: `/lager/${props.lagerId}/programm/neu`,
    query: { ...(tag ? { tag } : {}), ...(typ ? { typ } : {}) },
  })
}

function codeClass(code: BlockCode) {
  return `code-${code}`
}
</script>

<template>
  <div class="programm-gesamt">
    <div class="gesamt-kopf">
      <div>
        <h3>Gesamtprogramm</h3>
        <p class="hint">Wochenraster – Klick auf einen Block zum Bearbeiten, auf einen Tag für die Tagesansicht.</p>
      </div>
      <div class="gesamt-aktionen">
        <button type="button" @click="neuBlock()">+ Neues Programm</button>
        <button type="button" class="secondary" @click="neuBlock(undefined, 'anreise')">+ Anreise</button>
        <button type="button" class="secondary" @click="neuBlock(undefined, 'abreise')">+ Abreise</button>
        <router-link :to="`/lager/${lagerId}/programm/tag/${heuteIso()}`" class="secondary link-btn">
          Heute
        </router-link>
      </div>
    </div>

    <div class="raster-steuerung">
      <button class="secondary klein" :disabled="seitenIndex <= 0" @click="seitenIndex--">← Zurück</button>
      <span class="raster-info">
        {{ formatProgrammTag(sichtbareTage[0] ?? '') }}
        <template v-if="sichtbareTage.length > 1"> – {{ formatProgrammTag(sichtbareTage[sichtbareTage.length - 1]) }}</template>
      </span>
      <button class="secondary klein" :disabled="seitenIndex >= maxSeite" @click="seitenIndex++">Weiter →</button>
      <select v-model="rasterModus" class="raster-select">
        <option value="woche">1 Woche</option>
        <option value="zweiwochen">2 Wochen</option>
      </select>
    </div>

    <p v-if="!alleTage.length" class="hint">
      Noch keine Lagerdaten oder Programmblöcke. Start/Ende in Einstellungen setzen oder Programm importieren.
    </p>

    <div v-else class="raster-wrap">
      <div class="raster-grid" :style="{ gridTemplateColumns: `4rem repeat(${sichtbareTage.length}, minmax(100px, 1fr))` }">
        <div class="raster-ecke" />
        <button
          v-for="tag in sichtbareTage"
          :key="'h-' + tag"
          type="button"
          class="raster-tag-kopf"
          :class="{ heute: tag === heuteIso() }"
          @click="zuTag(tag)"
        >
          {{ formatProgrammTag(tag) }}
        </button>

        <template v-for="slotMin in slots" :key="slotMin">
          <div class="raster-zeit">{{ minutenZuLabel(slotMin) }}</div>
          <div
            v-for="tag in sichtbareTage"
            :key="tag + '-' + slotMin"
            class="raster-zelle"
            @dblclick="neuBlock(tag)"
          >
            <button
              v-for="b in bloeckeAnPosition(tag, slotMin)"
              :key="b.id"
              type="button"
              class="raster-block"
              :class="codeClass(b.code)"
              :style="{
                height: `${Math.max(SLOT_HEIGHT_REM, blockHoehe(b) * SLOT_HEIGHT_REM - 0.04)}rem`,
                top: `${blockTopOffsetRem(b, slotMin) + 0.02}rem`,
              }"
              @click.stop="zuBlock(b.id)"
            >
              <span class="rb-zeit">{{ formatProgrammZeit(b.start_zeit) }}</span>
              <span class="rb-titel">{{ b.nummer ? b.nummer + ' ' : '' }}{{ b.titel }}</span>
            </button>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>

<style scoped>
.gesamt-kopf { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: flex-start; gap: 0.75rem; margin-bottom: 1rem; }
.gesamt-kopf h3 { margin: 0 0 0.25rem; }
.gesamt-aktionen { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: center; }
.link-btn { display: inline-flex; align-items: center; padding: 0.55rem 1.1rem; text-decoration: none; border-radius: var(--radius-pill); font-size: 1rem; }
.raster-steuerung { display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem; margin-bottom: 0.75rem; }
.raster-info { font-size: 0.9rem; font-weight: 600; min-width: 8rem; text-align: center; }
.raster-select { font-size: 0.85rem; padding: 0.35rem 0.5rem; }
.raster-wrap { overflow-x: auto; border: 1px solid var(--color-border); border-radius: var(--radius-md); background: var(--color-surface); }
.raster-grid { display: grid; min-width: 640px; }
.raster-ecke { background: var(--color-surface-muted); border-bottom: 1px solid var(--color-border); border-right: 1px solid var(--color-border); }
.raster-tag-kopf {
  padding: 0.5rem 0.35rem; font-size: 0.78rem; font-weight: 700; text-align: center;
  background: var(--color-surface-muted); border-bottom: 1px solid var(--color-border); border-right: 1px solid var(--color-border);
  cursor: pointer; color: var(--color-text);
}
.raster-tag-kopf.heute { background: var(--color-accent); color: #fdfbf3; }
.raster-tag-kopf:hover { filter: brightness(0.97); }
.raster-zeit {
  height: 1.15rem;
  padding: 0 0.28rem;
  display: flex;
  align-items: flex-start;
  justify-content: flex-end;
  font-size: 0.66rem;
  color: var(--color-text-muted);
  text-align: right;
  border-bottom: 1px solid var(--color-border);
  border-right: 1px solid var(--color-border);
  font-variant-numeric: tabular-nums;
}
.raster-zelle {
  position: relative;
  height: 1.15rem;
  border-bottom: 1px solid var(--color-border);
  border-right: 1px solid var(--color-border);
  background: var(--color-surface);
  overflow: visible;
}
.raster-block {
  position: absolute;
  left: 2px;
  right: 2px;
  z-index: 3;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  padding: 0.08rem 0.28rem;
  border: none;
  border-radius: 4px;
  text-align: left;
  font-size: 0.66rem;
  line-height: 1.15;
  cursor: pointer;
  color: #fdfbf3;
}
.raster-block.code-LP { background: #6b7fa8; }
.raster-block.code-LS { background: var(--color-accent); }
.raster-block.code-LA { background: #c98a3f; }
.raster-block.code-ES { background: #8a7f68; }
.rb-zeit { font-weight: 700; opacity: 0.9; }
.rb-titel { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 100%; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
button.klein { font-size: 0.75rem; padding: 0.25rem 0.55rem; }
</style>
