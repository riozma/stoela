<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../composables/useAuth'
import { supabase } from '../supabaseClient'

withDefaults(
  defineProps<{
    lagerName?: string
    showAlleLager?: boolean
    showNavToggle?: boolean
    navOpen?: boolean
  }>(),
  { showAlleLager: true },
)

defineEmits<{ toggleNav: [] }>()

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
      <button
        v-if="showNavToggle"
        type="button"
        class="burger-btn"
        aria-label="Navigation"
        :aria-expanded="navOpen"
        @click="$emit('toggleNav')"
      >
        <span class="burger-line" />
        <span class="burger-line" />
        <span class="burger-line" />
      </button>
      <router-link v-if="showAlleLager" to="/lager" class="alle-lager-btn">
        ← Alle Lager
      </router-link>
      <h1 v-if="!showAlleLager" class="app-titel">Stöckli Lager</h1>
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
  width: 100%;
  padding: 0.65rem 1.25rem;
  box-sizing: border-box;
}
.app-header-left {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  min-width: 0;
}
.burger-btn {
  display: none;
  flex-direction: column;
  justify-content: center;
  gap: 4px;
  width: 2.25rem;
  height: 2.25rem;
  padding: 0.4rem;
  border-radius: var(--radius-md);
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  color: var(--color-text);
}
.burger-line {
  display: block;
  height: 2px;
  width: 100%;
  background: currentColor;
  border-radius: 1px;
}
.app-titel {
  margin: 0;
  font-size: 1.15rem;
  font-weight: 700;
}
.alle-lager-btn {
  display: inline-flex;
  align-items: center;
  flex-shrink: 0;
  font-weight: 700;
  font-size: 0.88rem;
  color: #fdfbf3;
  text-decoration: none;
  white-space: nowrap;
  padding: 0.45rem 0.85rem;
  background: var(--color-accent);
  border: 2px solid var(--color-accent);
  border-radius: var(--radius-md);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.12);
}
.alle-lager-btn:hover {
  background: var(--color-accent-hover);
  border-color: var(--color-accent-hover);
  text-decoration: none;
  color: #fdfbf3;
}
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
@media (max-width: 768px) {
  .burger-btn { display: flex; }
  .lager-name { display: none; }
}
</style>
