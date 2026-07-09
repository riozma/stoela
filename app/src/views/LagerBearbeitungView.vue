<script setup lang="ts">
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import AppHeader from '../components/AppHeader.vue'
import LagerBearbeitung from '../components/lager/LagerBearbeitung.vue'

const route = useRoute()
const lagerId = computed(() => route.params.id as string)
</script>

<template>
  <div>
    <AppHeader />
    <main class="page">
      <LagerBearbeitung :lager-id="lagerId" />
    </main>
  </div>
</template>

<style scoped>
.page { max-width: 720px; margin: 0 auto; padding: 1.25rem; }
</style>
