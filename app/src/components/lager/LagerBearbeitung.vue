<script setup lang="ts">
defineProps<{
  lagerId: string
  bereich?: string
}>()
</script>

<template>
  <section class="bearbeitung">
    <h2>Diese Seite wird aktuell noch bearbeitet</h2>
    <p>
      Der Bereich
      <strong v-if="bereich">{{ bereich }}</strong>
      <span v-else>dieser Bereich</span>
      ist während des laufenden Lagers noch nicht freigeschaltet.
    </p>
    <p class="hint">
      Vorschläge und Feedback können an <strong>Manuel</strong> mitgeteilt werden
      (<a href="mailto:manuelzeltner@gmail.com">manuelzeltner@gmail.com</a>).
    </p>
    <router-link :to="`/lager/${lagerId}/dashboard`" class="zurueck">← Zum Dashboard</router-link>
  </section>
</template>

<style scoped>
.bearbeitung {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  padding: 1.25rem 1.35rem;
  max-width: 560px;
}
.bearbeitung h2 { margin: 0 0 0.6rem; font-size: 1.15rem; }
.hint { color: var(--color-text-muted); font-size: 0.9rem; line-height: 1.5; }
.zurueck {
  display: inline-block;
  margin-top: 1rem;
  color: var(--color-accent);
  text-decoration: none;
  font-size: 0.9rem;
}
</style>
