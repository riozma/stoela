<script setup lang="ts">
import AemtliShell from './AemtliShell.vue'

defineProps<{
  lagerId: string
  aemtliId: string
  aemtliName: string
}>()
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <section class="leitung-funktionen">
      <h3>Lagerleitung</h3>
      <p class="hint">Zentrale Bereiche für Organisation, Team und Abschluss.</p>
      <div class="links">
        <router-link :to="`/lager/${lagerId}/leiter`">Leiter, Ämtli &amp; Berechtigungen</router-link>
        <router-link :to="`/lager/${lagerId}/teilnehmer`">TN-Anmeldung &amp; Teilnehmer</router-link>
        <router-link :to="`/lager/${lagerId}/kalender`">Kalender &amp; öffentliche Termine</router-link>
        <router-link :to="`/lager/${lagerId}/quittungen`">Quittungen / Kassier-Übersicht</router-link>
        <router-link :to="`/lager/${lagerId}/einstellungen`">Lager-Einstellungen</router-link>
      </div>
    </section>
  </AemtliShell>
</template>

<style scoped>
.leitung-funktionen h3 { margin: 0 0 0.35rem; font-size: 0.95rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.links { display: grid; gap: 0.45rem; margin-top: 0.65rem; }
.links a {
  display: block;
  padding: 0.55rem 0.7rem;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  background: var(--color-surface);
  font-weight: 600;
}
</style>
