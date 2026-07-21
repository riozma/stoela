<script setup lang="ts">
import { ref, watch } from 'vue'

const props = defineProps<{
  open: boolean
  titel?: string
  breit?: boolean
}>()

const emit = defineEmits<{ close: [] }>()

const dialogRef = ref<HTMLDialogElement | null>(null)

watch(
  () => props.open,
  (istOffen) => {
    const el = dialogRef.value
    if (!el) return
    if (istOffen && !el.open) el.showModal()
    else if (!istOffen && el.open) el.close()
  },
  { immediate: true },
)

function onCancel(e: Event) {
  // native ESC-Schliessen abfangen, damit @close konsistent über v-model läuft
  e.preventDefault()
  emit('close')
}

function onBackdropClick(e: MouseEvent) {
  if (e.target === dialogRef.value) emit('close')
}
</script>

<template>
  <dialog ref="dialogRef" class="app-dialog" :class="{ breit }" @cancel="onCancel" @close="emit('close')" @click="onBackdropClick">
    <div class="app-dialog-inner" @click.stop>
      <header v-if="titel" class="app-dialog-kopf">
        <h3>{{ titel }}</h3>
        <button type="button" class="app-dialog-schliessen" aria-label="Schliessen" @click="emit('close')">✕</button>
      </header>
      <div class="app-dialog-body">
        <slot />
      </div>
    </div>
  </dialog>
</template>

<style scoped>
.app-dialog {
  padding: 0;
  border: none;
  border-radius: var(--radius-md);
  background: var(--color-surface);
  color: var(--color-text);
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.25);
  max-width: 440px;
  width: calc(100% - 2rem);
  max-height: calc(100vh - 2rem);
  overflow: hidden;
}
.app-dialog.breit { max-width: 640px; }
.app-dialog::backdrop {
  background: rgba(0, 0, 0, 0.45);
}
.app-dialog-inner {
  display: flex;
  flex-direction: column;
  max-height: calc(100vh - 2rem);
}
.app-dialog-kopf {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;
  padding: 1rem 1.15rem 0.75rem;
  border-bottom: 1px solid var(--color-border);
  flex-shrink: 0;
}
.app-dialog-kopf h3 { margin: 0; font-size: 1.05rem; }
.app-dialog-schliessen {
  background: none; border: none; cursor: pointer; font-size: 1rem;
  color: var(--color-text-muted); padding: 0.15rem 0.35rem; border-radius: var(--radius-sm);
  line-height: 1;
}
.app-dialog-schliessen:hover { background: var(--color-surface-muted); }
.app-dialog-body {
  padding: 1.15rem;
  overflow-y: auto;
}
</style>
