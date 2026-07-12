<script setup lang="ts">
import AemtliShell from './AemtliShell.vue'

defineProps<{ lagerId: string; aemtliId: string; aemtliName: string }>()
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <p class="hint">Für dieses Ämtli sind aktuell keine weiteren Angaben nötig.</p>
  </AemtliShell>
</template>

<style scoped>
label { display: flex; flex-direction: column; gap: 0.35rem; font-size: 0.85rem; color: var(--color-text-muted); }
textarea { width: 100%; max-width: 480px; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; margin-bottom: 0.75rem; }
</style>
