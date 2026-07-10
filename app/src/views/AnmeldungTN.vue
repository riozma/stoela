<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabaseClient'
import {
  ESSENS_OPTIONEN,
  ahvBeimTippen,
  ahvGueltig,
  berechneLagerbeitrag,
  essensLabel,
  formatDatumSpanne,
  leerEltern,
  leerKind,
  type ElternDaten,
  type KindDaten,
  type LagerTnInfo,
} from '../lib/tnAnmeldung'

const route = useRoute()
const lagerId = route.params.id as string

type Schritt = 'info' | 'eltern' | 'kind' | 'uebersicht' | 'fertig'

const schritt = ref<Schritt>('info')
const lager = ref<LagerTnInfo | null>(null)
const ladefehler = ref('')
const fehler = ref('')
const speichern = ref(false)

const eltern = ref<ElternDaten>(leerEltern())
const kind = ref<KindDaten>(leerKind())
const kinder = ref<KindDaten[]>([])
const elternKontaktId = ref<string | null>(null)

const beitragGesamt = computed(() => {
  if (!lager.value) return 0
  return berechneLagerbeitrag(
    kinder.value.length,
    lager.value.info.kosten_erstes_kind,
    lager.value.info.kosten_weiteres_kind,
  )
})

const fortschritt = computed(() => {
  const map: Record<Schritt, number> = { info: 1, eltern: 2, kind: 3, uebersicht: 4, fertig: 5 }
  return map[schritt.value]
})

onMounted(async () => {
  const { data, error } = await supabase.rpc('get_lager_tn_anmeldung_info', { p_lager_id: lagerId })
  if (error || !data) {
    const { data: peek } = await supabase.rpc('get_lager_anmeldung_peek', { p_lager_id: lagerId })
    ladefehler.value = peek?.status
      ? `Anmeldung nicht offen (Status: ${peek.status}).`
      : 'Die Anmeldung für dieses Lager ist aktuell nicht verfügbar.'
    return
  }
  lager.value = data as LagerTnInfo
})

function ahvInput(e: Event) {
  kind.value.ahv_nr = ahvBeimTippen((e.target as HTMLInputElement).value)
}

function toggleEssens(id: typeof ESSENS_OPTIONEN[number]['id']) {
  if (kind.value.essensgewohnheiten_keine) {
    kind.value.essensgewohnheiten_keine = false
  }
  const idx = kind.value.essensgewohnheiten.indexOf(id)
  if (idx >= 0) kind.value.essensgewohnheiten.splice(idx, 1)
  else kind.value.essensgewohnheiten.push(id)
}

function keineEssensGewohnheiten() {
  kind.value.essensgewohnheiten_keine = !kind.value.essensgewohnheiten_keine
  if (kind.value.essensgewohnheiten_keine) {
    kind.value.essensgewohnheiten = []
    kind.value.essensgewohnheiten_sonstiges = ''
  }
}

function impfHinzufuegen(e: Event) {
  const input = e.target as HTMLInputElement
  if (!input.files?.length) return
  kind.value.impfungen.push(...Array.from(input.files))
  input.value = ''
}

function impfEntfernen(i: number) {
  kind.value.impfungen.splice(i, 1)
}

function validiereEltern() {
  if (!eltern.value.eltern_email.trim() || !eltern.value.eltern_vorname.trim() || !eltern.value.eltern_nachname.trim()) {
    fehler.value = 'Bitte E-Mail und Name der Eltern ausfüllen.'
    return false
  }
  if (!eltern.value.telefon.trim() || !eltern.value.adresse.trim() || !eltern.value.plz.trim() || !eltern.value.ort.trim()) {
    fehler.value = 'Bitte Telefon und Adresse vollständig ausfüllen.'
    return false
  }
  if (!eltern.value.aufenthaltsort_unbekannt && !eltern.value.aufenthaltsort.trim()) {
    fehler.value = 'Bitte Aufenthaltsort angeben oder «später mitteilen» wählen.'
    return false
  }
  fehler.value = ''
  return true
}

function validiereKind() {
  if (!kind.value.vorname.trim() || !kind.value.nachname.trim() || !kind.value.geburtsdatum) {
    fehler.value = 'Bitte Name und Geburtsdatum des Kindes ausfüllen.'
    return false
  }
  if (!kind.value.geschlecht) {
    fehler.value = 'Bitte biologisches Geschlecht wählen.'
    return false
  }
  if (!kind.value.ahv_nr.trim() || !ahvGueltig(kind.value.ahv_nr)) {
    fehler.value = 'Bitte gültige AHV-Nr. im Format 756.xxxx.xxxx.xx eingeben.'
    return false
  }
  fehler.value = ''
  return true
}

function weiterZuEltern() {
  fehler.value = ''
  schritt.value = 'eltern'
}

function weiterZuKind() {
  if (!validiereEltern()) return
  schritt.value = 'kind'
}

function kindSpeichern() {
  if (!validiereKind()) return
  kinder.value.push({ ...kind.value, impfungen: [...kind.value.impfungen] })
  kind.value = leerKind()
  schritt.value = 'uebersicht'
}

function weiteresKind() {
  kind.value = leerKind()
  schritt.value = 'kind'
}

async function uploadDokument(anmeldungId: string, typ: string, file: File) {
  const path = `${lagerId}/${anmeldungId}/${typ}_${Date.now()}_${file.name}`
  const { error: upErr } = await supabase.storage.from('tn-anmeldungen').upload(path, file, { upsert: false })
  if (upErr) throw upErr
  const { error: metaErr } = await supabase.from('tn_anmeldung_dokumente').insert({
    anmeldung_tn_id: anmeldungId,
    typ,
    storage_path: path,
    dateiname: file.name,
  })
  if (metaErr) throw metaErr
}

async function anmeldungAbsenden() {
  if (!lager.value || !kinder.value.length) return
  fehler.value = ''
  speichern.value = true

  try {
    let kontaktId = elternKontaktId.value
    if (!kontaktId) {
      const { data: kontakt, error: kErr } = await supabase
        .from('tn_eltern_kontakte')
        .insert({
          lager_id: lagerId,
          eltern_email: eltern.value.eltern_email.trim(),
          eltern_vorname: eltern.value.eltern_vorname.trim(),
          eltern_nachname: eltern.value.eltern_nachname.trim(),
          telefon: eltern.value.telefon.trim(),
          adresse: eltern.value.adresse.trim(),
          plz: eltern.value.plz.trim(),
          ort: eltern.value.ort.trim(),
          aufenthaltsort: eltern.value.aufenthaltsort_unbekannt ? null : eltern.value.aufenthaltsort.trim() || null,
          aufenthaltsort_unbekannt: eltern.value.aufenthaltsort_unbekannt,
        })
        .select('id')
        .single()
      if (kErr || !kontakt) throw kErr ?? new Error('Elternkontakt konnte nicht gespeichert werden.')
      kontaktId = kontakt.id
      elternKontaktId.value = kontaktId
    }

    let nr = 1
    for (const k of kinder.value) {
      const essensText = essensLabel(k.essensgewohnheiten, k.essensgewohnheiten_sonstiges, k.essensgewohnheiten_keine)
      const { data: tn, error: tnErr } = await supabase
        .from('anmeldungen_tn')
        .insert({
          lager_id: lagerId,
          vorname: k.vorname.trim(),
          nachname: k.nachname.trim(),
          geburtsdatum: k.geburtsdatum,
          geschlecht: k.geschlecht,
          ahv_nr: k.ahv_nr.trim(),
          essensgewohnheiten: essensText === '–' ? null : essensText,
          essensgewohnheiten_sonstiges: k.essensgewohnheiten_sonstiges.trim() || null,
          medikamente: k.medikamente.trim() || null,
          gesundheit_bemerkungen: k.gesundheit_bemerkungen.trim() || null,
          sonstige_info: k.sonstige_info.trim() || null,
          eltern_email: eltern.value.eltern_email.trim(),
          eltern_aufenthaltsort: eltern.value.aufenthaltsort_unbekannt
            ? 'Wird später mitgeteilt'
            : eltern.value.aufenthaltsort.trim() || null,
          notfallkontakt: `${eltern.value.eltern_vorname.trim()} ${eltern.value.eltern_nachname.trim()} · ${eltern.value.telefon.trim()}`,
          eltern_kontakt_id: kontaktId,
          kind_nr: nr,
        })
        .select('id')
        .single()
      if (tnErr || !tn) throw tnErr ?? new Error(`Anmeldung für ${k.vorname} fehlgeschlagen.`)

      if (k.krankenkasse_vorne) await uploadDokument(tn.id, 'krankenkasse_vorne', k.krankenkasse_vorne)
      if (k.krankenkasse_hinten) await uploadDokument(tn.id, 'krankenkasse_hinten', k.krankenkasse_hinten)
      for (const impf of k.impfungen) {
        await uploadDokument(tn.id, 'impfung', impf)
      }
      nr += 1
    }

    schritt.value = 'fertig'
  } catch (e) {
    fehler.value = e instanceof Error ? e.message : 'Anmeldung fehlgeschlagen.'
  } finally {
    speichern.value = false
  }
}
</script>

<template>
  <main class="tn-anmeldung">
    <header class="kopf">
      <h1>Anmeldung Teilnehmer/in</h1>
      <p v-if="lager" class="hint">{{ lager.name }} {{ lager.jahr }}</p>
      <div v-if="lager && schritt !== 'fertig'" class="fortschritt">
        <span>Schritt {{ fortschritt }} von 4</span>
      </div>
    </header>

    <p v-if="ladefehler" class="error">{{ ladefehler }}</p>

    <!-- Schritt 1: Lagerinfo -->
    <section v-else-if="schritt === 'info' && lager" class="karte">
      <h2>Lagerinfo</h2>
      <dl class="info-liste">
        <dt>Wann</dt>
        <dd>{{ formatDatumSpanne(lager.start_datum, lager.end_datum) }}</dd>
        <dt>Wo</dt>
        <dd>{{ lager.info.lageradresse || lager.ort || '–' }}</dd>
        <dt v-if="lager.info.lagertelefon">Lagertelefon</dt>
        <dd v-if="lager.info.lagertelefon">{{ lager.info.lagertelefon }}</dd>
        <dt>Kosten</dt>
        <dd>
          erstes Kind {{ lager.info.kosten_erstes_kind }}.–, jedes weitere {{ lager.info.kosten_weiteres_kind }}.—
          <span class="klein">(Bei finanziellen Schwierigkeiten bitte Kontakt aufnehmen)</span>
        </dd>
        <dt v-if="lager.info.einzahlungsfrist">Einzahlungsfrist</dt>
        <dd v-if="lager.info.einzahlungsfrist">{{ lager.info.einzahlungsfrist }}</dd>
        <dt>Lagerart</dt>
        <dd>{{ lager.info.lagerart }}</dd>
        <dt v-if="lager.info.anmeldeschluss">Anmeldeschluss</dt>
        <dd v-if="lager.info.anmeldeschluss">{{ lager.info.anmeldeschluss }}</dd>
        <dt>Durchgeführt von</dt>
        <dd>{{ lager.info.durchgefuehrt_von }}</dd>
        <dt v-if="lager.info.mindestalter">Mindestalter</dt>
        <dd v-if="lager.info.mindestalter">{{ lager.info.mindestalter }}</dd>
        <dt>Max. Teilnehmende</dt>
        <dd>{{ lager.info.max_teilnehmer }}</dd>
      </dl>
      <p v-if="lager.info.beschreibung" class="beschreibung">{{ lager.info.beschreibung }}</p>
      <p class="hint">{{ lager.info.versicherung_hinweis }}</p>

      <template v-if="lager.info.reise_besammlung || lager.info.reise_abfahrt || lager.info.reise_rueckkehr">
        <h3>Reise</h3>
        <ul class="termine">
          <li v-if="lager.info.reise_besammlung">Besammlung: {{ lager.info.reise_besammlung }}</li>
          <li v-if="lager.info.reise_abfahrt">Abfahrt: {{ lager.info.reise_abfahrt }}</li>
          <li v-if="lager.info.reise_rueckkehr">Rückkehr: {{ lager.info.reise_rueckkehr }}</li>
        </ul>
      </template>

      <template v-if="lager.info.elternabend_datum || lager.info.kennenlernabend_datum">
        <h3>Termine</h3>
        <ul class="termine">
          <li v-if="lager.info.elternabend_datum">
            Elternabend: {{ lager.info.elternabend_datum }}<span v-if="lager.info.elternabend_ort"> · {{ lager.info.elternabend_ort }}</span>
          </li>
          <li v-if="lager.info.kennenlernabend_datum">
            Kennenlernabend: {{ lager.info.kennenlernabend_datum }}<span v-if="lager.info.kennenlernabend_ort"> · {{ lager.info.kennenlernabend_ort }}</span>
          </li>
          <li v-if="lager.info.lagerrueckblick_datum">
            Lagerrückblick: {{ lager.info.lagerrueckblick_datum }}<span v-if="lager.info.lagerrueckblick_ort"> · {{ lager.info.lagerrueckblick_ort }}</span>
          </li>
        </ul>
      </template>

      <h3>Kontakt Lagerleitung</h3>
      <p>
        {{ lager.info.kontakt_name }}<br />
        <a v-if="lager.info.kontakt_email" :href="`mailto:${lager.info.kontakt_email}`">{{ lager.info.kontakt_email }}</a><br />
        <span v-if="lager.info.kontakt_telefon">{{ lager.info.kontakt_telefon }}</span><br />
        <span v-if="lager.info.kontakt_adresse">{{ lager.info.kontakt_adresse }}</span>
      </p>

      <h3>Elterninfo</h3>
      <p class="hint">
        Die folgenden Angaben zu Eltern gelten für alle Geschwisterkinder in dieser Anmeldung.
      </p>
      <button type="button" @click="weiterZuEltern">Weiter zur Anmeldung</button>
    </section>

    <!-- Schritt 2: Eltern -->
    <section v-else-if="schritt === 'eltern'" class="karte">
      <h2>Angaben Eltern / Erziehungsberechtigte</h2>
      <form class="formular" @submit.prevent="weiterZuKind">
        <label>E-Mail <input v-model="eltern.eltern_email" type="email" required /></label>
        <label>Vorname <input v-model="eltern.eltern_vorname" required /></label>
        <label>Nachname <input v-model="eltern.eltern_nachname" required /></label>
        <label>Telefon <input v-model="eltern.telefon" type="tel" required /></label>
        <label>Adresse <input v-model="eltern.adresse" required /></label>
        <label>PLZ <input v-model="eltern.plz" required /></label>
        <label>Ort <input v-model="eltern.ort" required /></label>
        <label>Aufenthaltsort während Lager
          <input v-model="eltern.aufenthaltsort" :disabled="eltern.aufenthaltsort_unbekannt" />
        </label>
        <label class="checkbox">
          <input v-model="eltern.aufenthaltsort_unbekannt" type="checkbox" />
          Noch nicht bekannt – kann später der Lagerleitung mitgeteilt werden
        </label>
        <div class="aktionen">
          <button type="button" class="secondary" @click="schritt = 'info'">Zurück</button>
          <button type="submit">Weiter zum Kind</button>
        </div>
      </form>
    </section>

    <!-- Schritt 3: Kind -->
    <section v-else-if="schritt === 'kind'" class="karte">
      <h2>Angaben Kind {{ kinder.length + 1 }}</h2>
      <form class="formular" @submit.prevent="kindSpeichern">
        <label>Vorname <input v-model="kind.vorname" required /></label>
        <label>Nachname <input v-model="kind.nachname" required /></label>
        <label>Geburtsdatum <input v-model="kind.geburtsdatum" type="date" required /></label>
        <label>Biologisches Geschlecht
          <select v-model="kind.geschlecht" required>
            <option value="">– wählen –</option>
            <option value="m">männlich</option>
            <option value="w">weiblich</option>
            <option value="d">divers</option>
          </select>
        </label>

        <fieldset>
          <legend>Essensgewohnheiten (optional)</legend>
          <label v-for="o in ESSENS_OPTIONEN" :key="o.id" class="checkbox">
            <input type="checkbox" :checked="kind.essensgewohnheiten.includes(o.id)" @change="toggleEssens(o.id)" />
            {{ o.label }}
          </label>
          <label class="checkbox">
            <input type="checkbox" :checked="kind.essensgewohnheiten_keine" @change="keineEssensGewohnheiten" />
            Keine besonderen Gewohnheiten
          </label>
          <label>Sonstiges
            <input v-model="kind.essensgewohnheiten_sonstiges" placeholder="Eigene Angabe" />
          </label>
        </fieldset>

        <fieldset>
          <legend>Gesundheit (optional)</legend>
          <label>Medikamente – welche, wann?
            <textarea v-model="kind.medikamente" rows="2" />
          </label>
          <label>Weitere Infos (Nachtwandeln, Bettnässen, ADHS, …)
            <textarea v-model="kind.gesundheit_bemerkungen" rows="3" />
          </label>
        </fieldset>

        <fieldset>
          <legend>Dokumente</legend>
          <label>Krankenkassenkarte Vorderseite
            <input type="file" accept="image/*,application/pdf" @change="kind.krankenkasse_vorne = ($event.target as HTMLInputElement).files?.[0] ?? null" />
          </label>
          <label>Krankenkassenkarte Rückseite
            <input type="file" accept="image/*,application/pdf" @change="kind.krankenkasse_hinten = ($event.target as HTMLInputElement).files?.[0] ?? null" />
          </label>
          <label>Impfausweis (mehrere Dateien möglich)
            <input type="file" accept="image/*,application/pdf" multiple @change="impfHinzufuegen" />
          </label>
          <ul v-if="kind.impfungen.length" class="datei-liste">
            <li v-for="(f, i) in kind.impfungen" :key="i">
              {{ f.name }}
              <button type="button" class="link-btn" @click="impfEntfernen(i)">entfernen</button>
            </li>
          </ul>
        </fieldset>

        <label>AHV-Nummer
          <input :value="kind.ahv_nr" required placeholder="756.xxxx.xxxx.xx" @input="ahvInput" />
        </label>
        <label>Sonstige Informationen
          <textarea v-model="kind.sonstige_info" rows="3" />
        </label>

        <div class="aktionen">
          <button type="button" class="secondary" @click="schritt = 'eltern'">Zurück</button>
          <button type="submit">Weiter zur Übersicht</button>
        </div>
      </form>
    </section>

    <!-- Schritt 4: Übersicht -->
    <section v-else-if="schritt === 'uebersicht' && lager" class="karte">
      <h2>Übersicht &amp; Lagerbeitrag</h2>
      <p class="hinweis-box">
        Der berechnete Beitrag gilt für diese Anmeldung. Die Rechnung mit Packliste etc. erhalten Sie einige Wochen vor dem Lager.
      </p>

      <h3>Angemeldete Kinder ({{ kinder.length }})</h3>
      <ul class="kinder-liste">
        <li v-for="(k, i) in kinder" :key="i">
          <strong>{{ k.vorname }} {{ k.nachname }}</strong>
          <span>Geb. {{ k.geburtsdatum }} · AHV {{ k.ahv_nr }}</span>
          <span>{{ essensLabel(k.essensgewohnheiten, k.essensgewohnheiten_sonstiges, k.essensgewohnheiten_keine) }}</span>
        </li>
      </ul>

      <p class="beitrag">
        Lagerbeitrag total: <strong>CHF {{ beitragGesamt }}.—</strong>
        <span class="klein">(1. Kind {{ lager.info.kosten_erstes_kind }}.—, jedes weitere {{ lager.info.kosten_weiteres_kind }}.—)</span>
      </p>

      <p>
        Wir werden Ihnen alle Infos via E-Mail, Brief und WhatsApp zustellen.
        Sie sollten eine Bestätigungsmail für die Anmeldung erhalten.
        Für die Kommunikation erstellen wir einen Eltern-WhatsApp-Chat.
      </p>

      <h3>Termine</h3>
      <ul class="termine">
        <li v-if="lager.info.elternabend_datum">
          Elternabend: {{ lager.info.elternabend_datum }}<span v-if="lager.info.elternabend_ort"> · {{ lager.info.elternabend_ort }}</span>
        </li>
        <li v-if="lager.info.kennenlernabend_datum">
          Kennenlernabend: {{ lager.info.kennenlernabend_datum }}<span v-if="lager.info.kennenlernabend_ort"> · {{ lager.info.kennenlernabend_ort }}</span>
        </li>
        <li>
          Lagerrückblick: {{ lager.info.lagerrueckblick_datum ?? 'wird noch angekündigt' }}<span v-if="lager.info.lagerrueckblick_ort"> · {{ lager.info.lagerrueckblick_ort }}</span>
        </li>
      </ul>

      <h3>Kontakt bei Fragen</h3>
      <p>
        {{ lager.info.kontakt_name }}<br />
        {{ lager.info.kontakt_email }}<span v-if="lager.info.kontakt_telefon"> · {{ lager.info.kontakt_telefon }}</span>
      </p>
      <p class="hint">{{ lager.info.versicherung_hinweis }}</p>

      <div class="aktionen">
        <button type="button" class="secondary" @click="weiteresKind">Weiteres Kind erfassen</button>
        <button type="button" :disabled="speichern" @click="anmeldungAbsenden">
          {{ speichern ? 'Sende…' : 'Anmeldung verbindlich absenden' }}
        </button>
      </div>
    </section>

    <!-- Schritt 5: Fertig -->
    <section v-else-if="schritt === 'fertig' && lager" class="karte">
      <h2>Vielen Dank!</h2>
      <p>Die Anmeldung für {{ kinder.length }} Kind(er) ist eingegangen.</p>
      <p>
        Lagerbeitrag total: <strong>CHF {{ beitragGesamt }}.—</strong><br />
        Sie erhalten eine Bestätigung per E-Mail.
      </p>
      <router-link :to="`/lager/${lagerId}/willkommen`">Zur Lager-Infoseite</router-link>
    </section>

    <p v-if="fehler" class="error">{{ fehler }}</p>
  </main>
</template>

<style scoped>
.tn-anmeldung { max-width: 640px; margin: 0 auto; padding: 1.5rem 1rem 3rem; }
.kopf { margin-bottom: 1rem; }
.kopf h1 { margin: 0 0 0.25rem; }
.hint { color: var(--color-text-muted); font-size: 0.9rem; }
.fortschritt { font-size: 0.82rem; color: var(--color-text-muted); margin-top: 0.35rem; }
.karte { background: var(--color-surface); border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 1.15rem; }
.karte h2 { margin: 0 0 0.75rem; font-size: 1.15rem; }
.karte h3 { margin: 1.25rem 0 0.5rem; font-size: 1rem; }
.info-liste { display: grid; grid-template-columns: 9rem 1fr; gap: 0.35rem 0.75rem; margin: 0 0 1rem; }
.info-liste dt { font-weight: 600; color: var(--color-text-muted); }
.info-liste dd { margin: 0; }
.beschreibung { line-height: 1.5; margin: 0.75rem 0; }
.klein { display: block; font-size: 0.82rem; color: var(--color-text-muted); }
.formular { display: flex; flex-direction: column; gap: 0.85rem; }
label { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.85rem; color: var(--color-text-muted); }
.checkbox { flex-direction: row !important; align-items: center; gap: 0.5rem; color: var(--color-text) !important; }
fieldset { border: 1px solid var(--color-border); border-radius: var(--radius-md); padding: 0.75rem; margin: 0; display: flex; flex-direction: column; gap: 0.5rem; }
legend { font-weight: 600; padding: 0 0.25rem; }
.aktionen { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 0.5rem; }
.hinweis-box { background: var(--color-surface-muted); padding: 0.65rem 0.8rem; border-radius: var(--radius-md); font-size: 0.9rem; }
.kinder-liste { list-style: none; padding: 0; margin: 0; }
.kinder-liste li { border-bottom: 1px solid var(--color-border); padding: 0.5rem 0; display: flex; flex-direction: column; gap: 0.15rem; }
.beitrag { font-size: 1.05rem; margin: 1rem 0; }
.termine { padding-left: 1.2rem; }
.datei-liste { list-style: none; padding: 0; margin: 0; font-size: 0.85rem; }
.link-btn { border: none; background: none; color: var(--color-accent); cursor: pointer; padding: 0; margin-left: 0.5rem; }
.error { color: var(--color-danger); margin-top: 1rem; }
</style>
