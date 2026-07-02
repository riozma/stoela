<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { supabase } from '../supabaseClient'
import AppHeader from '../components/AppHeader.vue'

interface OrgPerson {
  id: string
  vorname: string
  nachname: string
  email: string | null
  telefon: string | null
  rolle_hinweis: string | null
  aktiv: boolean
}

interface OrgTodoVorlage {
  id: string
  titel: string
  ebene: string
  monate_vor_lager: number | null
  kategorie: string
}

const orgName = ref('Stöckli Lager')
const personen = ref<OrgPerson[]>([])
const vorlagen = ref<OrgTodoVorlage[]>([])
const loading = ref(true)

const personForm = ref({ vorname: '', nachname: '', email: '', telefon: '', rolle_hinweis: '' })

async function datenLaden() {
  loading.value = true
  const [{ data: org }, { data: p }, { data: v }] = await Promise.all([
    supabase.from('organisation').select('name').eq('slug', 'stoeckli').single(),
    supabase.from('org_personen').select('*').eq('aktiv', true).order('nachname'),
    supabase.from('org_todo_vorlagen').select('id, titel, ebene, monate_vor_lager, kategorie').eq('aktiv', true).order('sortierung'),
  ])
  if (org?.name) orgName.value = org.name
  personen.value = p ?? []
  vorlagen.value = v ?? []
  loading.value = false
}

onMounted(datenLaden)

async function personHinzufuegen() {
  const { data: org } = await supabase.from('organisation').select('id').eq('slug', 'stoeckli').single()
  if (!org) return
  await supabase.from('org_personen').insert({
    organisation_id: org.id,
    vorname: personForm.value.vorname.trim(),
    nachname: personForm.value.nachname.trim(),
    email: personForm.value.email || null,
    telefon: personForm.value.telefon || null,
    rolle_hinweis: personForm.value.rolle_hinweis || null,
  })
  personForm.value = { vorname: '', nachname: '', email: '', telefon: '', rolle_hinweis: '' }
  await datenLaden()
}
</script>

<template>
  <div class="org-page">
    <div class="top-full">
      <AppHeader :show-alle-lager="false" />
    </div>
    <main>
      <header class="kopf">
        <div>
          <router-link to="/lager" class="zurueck">← Alle Lager</router-link>
          <h1>{{ orgName }} – Wissensspeicher</h1>
          <p class="hint">Organisation über alle Jahre: Personen, Fahrplan-Vorlagen, Ämtli-Wissen. Wächst mit jedem Lager.</p>
        </div>
      </header>

      <section class="karte">
        <h2>Personen-Pool</h2>
        <p class="hint">Leiter/innen und Helfer/innen – können bei neuem Lager übernommen werden.</p>
        <table v-if="personen.length" class="liste">
          <thead><tr><th>Name</th><th>Kontakt</th><th>Rolle</th></tr></thead>
          <tbody>
            <tr v-for="p in personen" :key="p.id">
              <td>{{ p.vorname }} {{ p.nachname }}</td>
              <td>{{ p.email ?? '–' }}<br><span class="klein">{{ p.telefon }}</span></td>
              <td>{{ p.rolle_hinweis ?? '–' }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else class="hint">Noch keine Personen erfasst.</p>
        <form class="inline-form" @submit.prevent="personHinzufuegen">
          <input v-model="personForm.vorname" placeholder="Vorname" required />
          <input v-model="personForm.nachname" placeholder="Nachname" required />
          <input v-model="personForm.email" type="email" placeholder="E-Mail" />
          <input v-model="personForm.telefon" placeholder="Telefon" />
          <input v-model="personForm.rolle_hinweis" placeholder="Rolle (z.B. Küche, Vorstand)" />
          <button type="submit">Person hinzufügen</button>
        </form>
      </section>

      <section class="karte">
        <h2>Fahrplan-Vorlagen</h2>
        <p class="hint">Werden beim «Fahrplan laden» in jedes neue Lager kopiert (mit Fälligkeit relativ zum Lagerstart).</p>
        <ul v-if="vorlagen.length" class="vorlagen-liste">
          <li v-for="v in vorlagen" :key="v.id">
            <strong>{{ v.titel }}</strong>
            <span class="meta">
              {{ v.ebene === 'verein' ? 'Verein' : (v.monate_vor_lager != null ? v.monate_vor_lager + ' Mo. vor Lager' : 'Lager') }}
              · {{ v.kategorie }}
            </span>
          </li>
        </ul>
      </section>

      <section class="karte hinweis-karte">
        <h2>Was wächst mit der Zeit?</h2>
        <ul>
          <li>Leiter-Pool und Vorjahres-Übernahme (provisorisch → Bestätigung 3 Monate vor Lager)</li>
          <li>Ämtli-Hinweise (Finanzen, Werbung, Motto, Sponsoring, …)</li>
          <li>Elterninfo-Vorlage mit Packliste</li>
          <li>Learnings pro Ämtli nach jedem Lager</li>
        </ul>
      </section>
    </main>
  </div>
</template>

<style scoped>
.org-page { min-height: 100vh; }
.top-full {
  position: sticky; top: 0; z-index: 100; width: 100%;
  background: var(--color-surface); border-bottom: 1px solid var(--color-border);
}
main { max-width: 960px; margin: 0 auto; padding: 1rem 1.25rem 2rem; }
.kopf { margin-bottom: 1.5rem; }
.kopf h1 { margin: 0.25rem 0; }
.zurueck { font-size: 0.85rem; font-weight: 600; color: var(--color-accent); text-decoration: none; }
.karte { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 1rem 1.15rem; margin-bottom: 1rem; }
.karte h2 { margin: 0 0 0.35rem; font-size: 1.05rem; }
.liste { width: 100%; border-collapse: collapse; margin: 0.75rem 0; font-size: 0.88rem; }
.liste th, .liste td { text-align: left; padding: 0.45rem 0.6rem; border-bottom: 1px solid var(--color-border); }
.klein { font-size: 0.78rem; color: var(--color-text-muted); }
.inline-form { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 0.75rem; align-items: center; }
.vorlagen-liste { list-style: none; padding: 0; margin: 0.75rem 0 0; }
.vorlagen-liste li { padding: 0.4rem 0; border-bottom: 1px solid var(--color-border); font-size: 0.9rem; }
.meta { display: block; font-size: 0.78rem; color: var(--color-text-muted); margin-top: 0.1rem; }
.hinweis-karte ul { margin: 0.5rem 0 0; padding-left: 1.2rem; font-size: 0.9rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
</style>
