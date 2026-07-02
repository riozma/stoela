<script setup lang="ts">
import AemtliTodos from './AemtliTodos.vue'

defineProps<{
  lagerId: string
  aemtliId: string
  aemtliName: string
}>()
</script>

<template>
  <section class="aemtli-bereich">
    <h2>{{ aemtliName }}</h2>
    <AemtliTodos :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName" />
    <p class="hint">
      Notizen, Learnings und weitere Inhalte für «{{ aemtliName }}» können hier schrittweise ergänzt werden.
    </p>
  </section>
</template>

<style scoped>
.aemtli-bereich h2 { margin: 0 0 1rem; }
.hint { color: var(--color-text-muted); font-size: 0.9rem; margin-top: 1rem; }
</style>
