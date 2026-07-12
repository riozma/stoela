<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { supabase } from '../../supabaseClient'
import DessertaktienUebersicht from './DessertaktienUebersicht.vue'

interface TN {
  id: string
  vorname: string
  nachname: string
  status: string
  notfallkontakt: string | null
  eltern_email: string | null
  ahv_nr: string | null
  essensgewohnheiten: string | null
  gesundheit_bemerkungen: string | null
  rezeption_notiz: string | null
  angekommen: boolean
}

interface TnFinanz {
  anmeldung_tn_id: string
  bezahlt: boolean
  bemerkung: string | null
}

const props = defineProps<{ lagerId: string }>()

const tnListe = ref<TN[]>([])
const finanzen = ref<Record<string, TnFinanz>>({})
const laden = ref(true)

async function laden_() {
  laden.value = true
  const { data: tn } = await supabase
    .from('anmeldungen_tn')
    .select('id, vorname, nachname, status, notfallkontakt, eltern_email, ahv_nr, essensgewohnheiten, gesundheit_bemerkungen, rezeption_notiz, angekommen')
    .eq('lager_id', props.lagerId)
    .order('nachname')
  tnListe.value = (tn ?? []) as TN[]

  const tnIds = tnListe.value.map((t) => t.id)
  if (tnIds.length) {
    const { data: fin } = await supabase
      .from('tn_finanzen')
      .select('anmeldung_tn_id, bezahlt, bemerkung')
      .in('anmeldung_tn_id', tnIds)
    const map: Record<string, TnFinanz> = {}
    for (const f of fin ?? []) map[f.anmeldung_tn_id] = f
    finanzen.value = map
  } else {
    finanzen.value = {}
  }
  laden.value = false
}

onMounted(laden_)

function fehlendeAngaben(tn: TN): string[] {
  const fehlt: string[] = []
  if (!tn.notfallkontakt?.trim()) fehlt.push('Notfallkontakt')
  if (!tn.ahv_nr?.trim()) fehlt.push('AHV-Nr.')
  if (!tn.eltern_email?.trim()) fehlt.push('E-Mail Eltern')
  return fehlt
}

function bezahlt(tnId: string): boolean {
  return finanzen.value[tnId]?.bezahlt ?? false
}

function finanzBemerkung(tnId: string): string | null {
  return finanzen.value[tnId]?.bemerkung?.trim() || null
}

const bereitAnzahl = computed(() => tnListe.value.filter((t) => !fehlendeAngaben(t).length && bezahlt(t.id)).length)
const angekommenAnzahl = computed(() => tnListe.value.filter((t) => t.angekommen).length)

const notizOffenId = ref<string | null>(null)
const notizSpeichern = ref<string | null>(null)

function notizToggeln(tnId: string) {
  notizOffenId.value = notizOffenId.value === tnId ? null : tnId
}

async function notizSpeichernHandler(tn: TN) {
  notizSpeichern.value = tn.id
  await supabase.from('anmeldungen_tn').update({ rezeption_notiz: tn.rezeption_notiz?.trim() || null }).eq('id', tn.id)
  notizSpeichern.value = null
}

async function angekommenSetzen(tn: TN, wert: boolean) {
  tn.angekommen = wert
  await supabase.from('anmeldungen_tn').update({ angekommen: wert }).eq('id', tn.id)
}
</script>

<template>
  <section class="rezeption">
    <h2>Rezeption vor dem Lager</h2>
    <p class="hint">
      Übersicht für den Anreisetag: fehlende Angaben, was bereits vorliegt, und ob der Lagerbeitrag bezahlt ist.
      Ausserdem können hier Dessertaktien erfasst werden.
    </p>

    <p v-if="!laden" class="stand">
      {{ bereitAnzahl }} / {{ tnListe.length }} vollständig und bezahlt · {{ angekommenAnzahl }} / {{ tnListe.length }} angekommen
    </p>
    <p v-if="laden" class="hint">Lade…</p>

    <table v-if="tnListe.length" class="liste">
      <thead>
        <tr>
          <th>Angekommen</th>
          <th>Name</th>
          <th>Status</th>
          <th>Fehlt noch</th>
          <th>Essen</th>
          <th>Gesundheit</th>
          <th>Bezahlt</th>
          <th>Notiz</th>
        </tr>
      </thead>
      <tbody>
        <template v-for="tn in tnListe" :key="tn.id">
        <tr>
          <td>
            <input type="checkbox" :checked="tn.angekommen" @change="angekommenSetzen(tn, ($event.target as HTMLInputElement).checked)" />
          </td>
          <td>{{ tn.vorname }} {{ tn.nachname }}</td>
          <td>{{ tn.status }}</td>
          <td>
            <span v-if="fehlendeAngaben(tn).length" class="fehlt-badge">{{ fehlendeAngaben(tn).join(', ') }}</span>
            <span v-else class="ok-badge">vollständig</span>
          </td>
          <td>{{ tn.essensgewohnheiten || '–' }}</td>
          <td>{{ tn.gesundheit_bemerkungen || '–' }}</td>
          <td>
            <span :class="bezahlt(tn.id) ? 'ok-badge' : 'fehlt-badge'">{{ bezahlt(tn.id) ? 'bezahlt' : 'offen' }}</span>
            <span v-if="finanzBemerkung(tn.id)" class="finanz-notiz" :title="finanzBemerkung(tn.id)!">📝 {{ finanzBemerkung(tn.id) }}</span>
          </td>
          <td>
            <button type="button" class="secondary klein" @click="notizToggeln(tn.id)">
              {{ tn.rezeption_notiz ? '📝 Notiz' : '+ Notiz' }}
            </button>
          </td>
        </tr>
        <tr v-if="notizOffenId === tn.id">
          <td colspan="8">
            <div class="notiz-zeile">
              <textarea v-model="tn.rezeption_notiz" rows="2" placeholder="Was die Eltern am Anreisetag noch mitgeteilt haben..."></textarea>
              <button type="button" :disabled="notizSpeichern === tn.id" @click="notizSpeichernHandler(tn)">
                {{ notizSpeichern === tn.id ? 'Speichere…' : 'Speichern' }}
              </button>
            </div>
          </td>
        </tr>
        </template>
      </tbody>
    </table>
    <p v-else-if="!laden" class="hint">Noch keine Teilnehmer angemeldet.</p>

    <hr class="trenner" />
    <DessertaktienUebersicht :lager-id="lagerId" bearbeitbar />
  </section>
</template>

<style scoped>
.rezeption h2 { margin: 0 0 0.35rem; }
.hint { color: var(--color-text-muted); font-size: 0.88rem; }
.stand { font-weight: 600; margin: 0.5rem 0 1rem; }
.liste { width: 100%; border-collapse: collapse; font-size: 0.85rem; margin-bottom: 1.5rem; }
.liste th, .liste td { text-align: left; padding: 0.45rem 0.6rem; border-bottom: 1px solid var(--color-border); vertical-align: middle; }
.liste th { color: var(--color-text-muted); font-size: 0.75rem; text-transform: uppercase; }
.fehlt-badge { display: inline-block; padding: 0.1rem 0.5rem; border-radius: var(--radius-pill); background: #fdf3e0; color: #8a5a1f; font-size: 0.78rem; }
.ok-badge { display: inline-block; padding: 0.1rem 0.5rem; border-radius: var(--radius-pill); background: #eaf3ec; color: #2f6b40; font-size: 0.78rem; }
.trenner { margin: 1.5rem 0; border: none; border-top: 1px solid var(--color-border); }
.finanz-notiz { display: block; margin-top: 0.2rem; font-size: 0.78rem; color: var(--color-text-muted); }
.notiz-zeile { display: flex; gap: 0.5rem; align-items: flex-start; padding: 0.5rem; }
.notiz-zeile textarea { flex: 1; }
</style>
