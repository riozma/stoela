<script setup lang="ts">
defineProps<{ aemtliName: string }>()
</script>

<template>
  <section class="aemtli-placeholder">
    <h2>{{ aemtliName }}</h2>
    <p class="hint">
      Dein Ämtli-Bereich. Hier können Checklisten, Learnings und Aufgaben für «{{ aemtliName }}» ergänzt werden.
    </p>
  </section>
</template>

<style scoped>
.hint { color: var(--color-text-muted); font-size: 0.9rem; }
</style>
