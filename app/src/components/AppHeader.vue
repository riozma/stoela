<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { supabase } from '../supabaseClient'

defineProps<{
  lagerName?: string
  showAlleLager?: boolean
}>()

const { session, signOut } = useAuth()
const router = useRouter()
const profil = ref<{ vorname: string | null; nachname: string | null } | null>(null)

async function ladeProfil() {
  if (!session.value) {
    profil.value = null
    return
  }
  const { data } = await supabase
    .from('profiles')
    .select('vorname, nachname')
    .eq('id', session.value.user.id)
    .single()
  profil.value = data
}

onMounted(ladeProfil)
watch(session, ladeProfil)

const kuerzel = computed(() => {
  const p = profil.value
  if (p?.vorname && p?.nachname) return `${p.vorname[0]}${p.nachname[0]}`.toUpperCase()
  if (p?.vorname) return p.vorname.slice(0, 2).toUpperCase()
  const email = session.value?.user.email ?? ''
  return email.slice(0, 2).toUpperCase()
})

async function logout() {
  await signOut()
  await router.push('/login')
}
</script>

<template>
  <header class="app-header">
    <div class="app-header-left">
      <router-link v-if="showAlleLager !== false" to="/lager" class="alle-lager-link">Alle Lager</router-link>
      <h1 v-else class="app-titel">Stöckli Lager</h1>
      <span v-if="lagerName" class="lager-name">{{ lagerName }}</span>
    </div>
    <div class="app-header-right">
      <span class="profil-kuerzel" :title="session?.user.email ?? ''">{{ kuerzel }}</span>
      <button type="button" class="secondary logout-btn" @click="logout">Logout</button>
    </div>
  </header>
</template>

<style scoped>
.app-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.65rem 0;
  margin-bottom: 0.25rem;
  border-bottom: 1px solid var(--color-border);
}
.app-header-left {
  display: flex;
  align-items: baseline;
  gap: 0.75rem;
  min-width: 0;
}
.app-titel {
  margin: 0;
  font-size: 1.15rem;
  font-weight: 700;
}
.alle-lager-link {
  font-weight: 700;
  font-size: 0.95rem;
  color: var(--color-accent);
  text-decoration: none;
  white-space: nowrap;
}
.alle-lager-link:hover { text-decoration: underline; }
.lager-name {
  font-size: 0.95rem;
  color: var(--color-text-muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.app-header-right {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  flex-shrink: 0;
}
.profil-kuerzel {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 2rem;
  height: 2rem;
  border-radius: 50%;
  background: var(--color-accent);
  color: #fdfbf3;
  font-size: 0.78rem;
  font-weight: 700;
  letter-spacing: 0.02em;
}
.logout-btn {
  font-size: 0.82rem;
  padding: 0.35rem 0.65rem;
}
</style>
