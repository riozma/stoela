<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import AemtliShell from './AemtliShell.vue'

const props = defineProps<{
  lagerId: string
  aemtliId: string
  aemtliName: string
}>()
const emit = defineEmits<{ gespeichert: [link: string] }>()

const fotoLink = ref('')
const speichern = ref(false)
const gespeichert = ref(false)
const fehler = ref('')
const diashow = ref<{ start_datum: string | null; start_zeit: string | null; ort: string | null } | null>(null)

async function laden() {
  const [{ data: lager }, { data: termin }] = await Promise.all([
    supabase.from('lager').select('foto_link').eq('id', props.lagerId).single(),
    supabase
      .from('lager_termine')
      .select('start_datum, start_zeit, ort')
      .eq('lager_id', props.lagerId)
      .eq('typ', 'diashow')
      .maybeSingle(),
  ])
  fotoLink.value = lager?.foto_link ?? ''
  diashow.value = termin ?? null
}

onMounted(laden)

async function linkSpeichern() {
  fehler.value = ''
  gespeichert.value = false
  const link = fotoLink.value.trim()
  if (link && !/^https?:\/\//i.test(link)) {
    fehler.value = 'Bitte einen vollständigen Link mit https:// eingeben.'
    return
  }
  speichern.value = true
  const { error } = await supabase
    .from('lager')
    .update({ foto_link: link || null })
    .eq('id', props.lagerId)
  speichern.value = false
  if (error) {
    fehler.value = error.message
    return
  }
  gespeichert.value = true
  emit('gespeichert', link)
}
</script>

<template>
  <AemtliShell :lager-id="lagerId" :aemtli-id="aemtliId" :aemtli-name="aemtliName">
    <section class="foto-funktionen">
      <h3>Fotos &amp; Diashow</h3>
      <form @submit.prevent="linkSpeichern">
        <label>
          Fotoalbum / Google Fotos
          <input v-model="fotoLink" type="url" placeholder="https://photos.google.com/..." />
        </label>
        <button type="submit" :disabled="speichern">{{ speichern ? 'Speichere…' : 'Link speichern' }}</button>
      </form>
      <p v-if="gespeichert" class="ok">Fotolink gespeichert – er erscheint jetzt im Dashboard.</p>
      <p v-if="fehler" class="error">{{ fehler }}</p>

      <div class="diashow">
        <strong>Diashow-Termin</strong>
        <span v-if="diashow?.start_datum">
          {{ diashow.start_datum }}
          <template v-if="diashow.start_zeit"> · {{ diashow.start_zeit.slice(0, 5) }}</template>
          <template v-if="diashow.ort"> · {{ diashow.ort }}</template>
        </span>
        <span v-else class="hint">Noch nicht im Kalender erfasst.</span>
        <router-link :to="`/lager/${lagerId}/kalender`">Im Kalender bearbeiten →</router-link>
      </div>
    </section>
  </AemtliShell>
</template>

<style scoped>
.foto-funktionen h3 { margin: 0 0 0.6rem; font-size: 0.95rem; }
form { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: end; }
form label { flex: 1; min-width: 230px; display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.82rem; color: var(--color-text-muted); }
.diashow { margin-top: 1rem; display: flex; flex-wrap: wrap; gap: 0.4rem 0.75rem; align-items: center; font-size: 0.88rem; }
.hint { color: var(--color-text-muted); }
.ok { color: #2e7d32; font-size: 0.85rem; }
.error { color: var(--color-danger); font-size: 0.85rem; }
</style>
