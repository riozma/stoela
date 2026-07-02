<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import { featureAktiv } from '../../lib/lagerTimeline'

const props = defineProps<{
  lagerId: string
  tag: string
  startDatum: string | null
  endDatum: string | null
}>()

const gruppeModus = ref<'gerade' | 'ungerade' | 'alle'>('ungerade')
const tnMitGruppe = ref<{ id: string; gruppe_nr: number | null }[]>([])

const kioskAktiv = computed(() => featureAktiv('kiosk', props.startDatum, props.endDatum))

const heuteKiosk = computed(() => {
  if (!kioskAktiv.value) return false
  if (props.tag !== new Date().toISOString().slice(0, 10)) return false
  const h = new Date().getHours()
  if (h < 12) return false
  if (gruppeModus.value === 'alle') return true
  const gerade = tnMitGruppe.value.filter((t) => t.gruppe_nr != null && t.gruppe_nr % 2 === 0).length
  const ungerade = tnMitGruppe.value.filter((t) => t.gruppe_nr != null && t.gruppe_nr % 2 === 1).length
  if (gruppeModus.value === 'gerade') return gerade >= ungerade || ungerade === 0
  return ungerade >= gerade || gerade === 0
})

const gruppenText = computed(() => {
  if (gruppeModus.value === 'alle') return 'alle Gruppen'
  if (gruppeModus.value === 'gerade') return 'Gruppen mit gerader Nummer'
  return 'Gruppen mit ungerader Nummer'
})

onMounted(async () => {
  const [{ data: l }, { data: tn }] = await Promise.all([
    supabase.from('lager').select('kiosk_gruppe_modus').eq('id', props.lagerId).single(),
    supabase.from('anmeldungen_tn').select('id').eq('lager_id', props.lagerId),
  ])
  if (l?.kiosk_gruppe_modus) gruppeModus.value = l.kiosk_gruppe_modus as typeof gruppeModus.value

  const { data: gruppen } = await supabase.from('lagergruppen').select('id, name').eq('lager_id', props.lagerId).order('name')
  const gruppenMap = new Map((gruppen ?? []).map((g, i) => [g.id, i + 1]))
  const { data: mitglieder } = await supabase.from('gruppen_mitglieder').select('anmeldung_tn_id, lagergruppe_id').not('anmeldung_tn_id', 'is', null)
  const tnGruppe = new Map((mitglieder ?? []).map((m) => [m.anmeldung_tn_id, gruppenMap.get(m.lagergruppe_id) ?? null]))
  tnMitGruppe.value = (tn ?? []).map((t) => ({ id: t.id, gruppe_nr: tnGruppe.get(t.id) ?? null }))
})
</script>

<template>
  <div v-if="heuteKiosk" class="kiosk-banner">
    <strong>🛒 Kiosk heute Nachmittag</strong>
    <span>{{ gruppenText }} – Süssigkeiten &amp; Postkarten</span>
    <router-link :to="`/lager/${lagerId}/aemtli/kiosk`" class="link">Kiosk öffnen →</router-link>
  </div>
</template>

<style scoped>
.kiosk-banner {
  display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem 1rem;
  padding: 0.65rem 1rem; margin-bottom: 1rem;
  background: #fdf8f0; border: 1px solid #c98a3f; border-radius: var(--radius-md);
  font-size: 0.88rem;
}
.link { margin-left: auto; color: var(--color-accent); font-weight: 600; text-decoration: none; font-size: 0.85rem; }
.link:hover { text-decoration: underline; }
</style>
