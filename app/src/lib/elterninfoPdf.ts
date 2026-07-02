export interface ElterninfoDaten {
  lagerName: string
  jahr: number
  ort: string | null
  felder: Record<string, string | number>
  vorlage: Record<string, unknown>
  packliste: string[]
}

function esc(s: string | number | undefined | null): string {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
}

function packlisteHtml(items: string[]): string {
  const noetig = items.slice(0, Math.ceil(items.length * 0.7))
  const optional = items.slice(Math.ceil(items.length * 0.7))
  return `
    <h3>Notwendig</h3>
    <ul>${noetig.map((p) => `<li>${esc(p)}</li>`).join('')}</ul>
    ${optional.length ? `<h3>Wenn möglich / wenn nötig</h3><ul>${optional.map((p) => `<li>${esc(p)}</li>`).join('')}</ul>` : ''}
  `
}

export function downloadElterninfoPdf(d: ElterninfoDaten) {
  const f = d.felder
  const v = d.vorlage
  const homepage = String(v.homepage ?? 'https://www.stoecklilager.ch')

  const html = `<!DOCTYPE html><html lang="de"><head><meta charset="utf-8">
<title>Elterninfo ${esc(d.lagerName)} ${d.jahr}</title>
<style>
  @page { margin: 18mm 16mm; }
  body { font-family: 'Segoe UI', Arial, sans-serif; color: #2a2418; font-size: 11pt; line-height: 1.45; }
  .page { page-break-after: always; max-width: 180mm; margin: 0 auto; }
  .page:last-child { page-break-after: auto; }
  h1 { font-size: 18pt; margin: 0 0 0.2rem; color: #3d5a40; }
  h2 { font-size: 13pt; margin: 1.2rem 0 0.4rem; color: #3d5a40; border-bottom: 1px solid #c8d4c0; padding-bottom: 0.2rem; }
  h3 { font-size: 11pt; margin: 0.8rem 0 0.3rem; }
  .kopf { margin-bottom: 1rem; }
  .untertitel { color: #6b5d3f; font-size: 10pt; }
  .leiter { margin: 0.5rem 0 1rem; font-size: 10.5pt; }
  .footer { font-size: 9pt; color: #6b5d3f; margin-top: 1.5rem; }
  ul { margin: 0.3rem 0; padding-left: 1.2rem; }
  li { margin: 0.15rem 0; }
  .highlight { background: #f5f0e4; padding: 0.6rem 0.8rem; border-radius: 4px; margin: 0.5rem 0; }
  .termine td { padding: 0.2rem 0.6rem 0.2rem 0; vertical-align: top; }
  .termine td:first-child { font-weight: 600; white-space: nowrap; }
  .formular { border: 1px solid #ccc; padding: 0.8rem; margin-top: 0.5rem; font-size: 10pt; }
  .formular label { display: block; margin: 0.5rem 0; border-bottom: 1px dotted #bbb; min-height: 1.6rem; }
</style></head><body>

<div class="page">
  <div class="kopf">
    <h1>${esc(d.lagerName)}</h1>
    <p class="untertitel">${esc(d.ort ?? '')}</p>
    <p class="untertitel">Besuchen Sie uns auf <strong>${esc(homepage)}</strong></p>
  </div>
  <div class="leiter">
    <strong>${esc(f.lagerleiter_name ?? 'Lagerleitung')}</strong><br>
    Lagerleiter/in<br>
    ${esc(f.lagerleiter_adresse ?? '')}<br>
    ${esc(f.lagerleiter_telefon ?? '')}<br>
    ${esc(f.lagerleiter_email ?? '')}
  </div>

  <p>Liebe Eltern,</p>
  <p>wir laden Sie herzlich ein zum <strong>Elternabend</strong> des ${esc(d.lagerName)}.</p>

  <table class="termine">
    <tr><td>Elternabend:</td><td>${esc(f.elternabend_datum)}<br>${esc(f.elternabend_ort)}</td></tr>
    <tr><td>Kennenlernabend Kinder:</td><td>${esc(f.kennenlernabend_datum)}<br>${esc(f.kennenlernabend_ort)}</td></tr>
    <tr><td>Diashow:</td><td>${esc(f.diashow_datum)}<br>${esc(f.diashow_ort)}</td></tr>
  </table>

  <p>Der Elternabend dient dem Kennenlernen und der Vorstellung des Leitungsteams. Bitte füllen Sie das Blatt «Wichtige Kinder-Informationen» aus und bringen es mit.</p>
  <p class="footer">Seite 1 · ${esc(d.lagerName)} ${d.jahr}</p>
</div>

<div class="page">
  <h2>Lagerbeitrag</h2>
  <p>Der Lagerbeitrag beträgt <strong>CHF ${esc(f.lagerbeitrag)}.—</strong> bzw. <strong>CHF ${esc(f.lagerbeitrag_geschwister)}.—</strong> für jedes weitere Geschwisterkind.</p>
  <p>Einzahlung bis spätestens <strong>${esc(f.einzahlungsfrist)}</strong>.</p>
  <div class="highlight">
    <p><strong>Pfarrei:</strong> 50% Unterstützung – Kontakt Kassier ${esc(String(v.kassier_name ?? ''))} (${esc(String(v.kassier_email ?? ''))}, ${esc(String(v.kassier_telefon ?? ''))})</p>
    <p><strong>Kulturlegi:</strong> bis 70% Rabatt – ${esc(String(v.kulturlegi_link ?? ''))}</p>
    <p>${esc(String(v.pfarrei_name ?? ''))}<br>IBAN: ${esc(String(v.pfarrei_iban ?? ''))}</p>
  </div>
  <p>Herzlichen Dank! Auf eine zahlreiche Teilnahme freuen wir uns.</p>
  <p>Das ${esc(d.lagerName)}-Team</p>
  <p class="footer">Seite 2 · ${esc(d.lagerName)} ${d.jahr}</p>
</div>

<div class="page">
  <h2>Die wichtigsten Informationen auf einen Blick</h2>
  <table class="termine">
    <tr><td>Reise Besammlung:</td><td>${esc(f.reise_besammlung)}</td></tr>
    <tr><td>Abfahrt:</td><td>${esc(f.reise_abfahrt)}</td></tr>
    <tr><td>Rückkehr:</td><td>${esc(f.reise_rueckkehr)}</td></tr>
    <tr><td>Lageradresse:</td><td>${esc(f.lageradresse || d.ort)}</td></tr>
    <tr><td>Lagertelefon:</td><td>${esc(f.lagertelefon)}</td></tr>
    <tr><td>Telefonzeiten:</td><td>${esc(f.telefon_zeiten ?? 'Wird noch bekannt gegeben')}</td></tr>
    <tr><td>Taschengeld:</td><td>Lagerkiosk – nach eigenem Ermessen ein paar Franken und Briefmarken für Postkarten.</td></tr>
  </table>
  <p>${esc(String(v.dessertaktien_hinweis ?? 'Dessertaktien werden am Elternabend vorgestellt.'))}</p>
  <p>${esc(String(v.besuche_hinweis ?? ''))}</p>
  <p class="footer">Seite 3 · ${esc(d.lagerName)} ${d.jahr}</p>
</div>

<div class="page">
  <h2>Packliste ${d.jahr}</h2>
  ${packlisteHtml(d.packliste)}
  <p><em>Natels sowie Energy-Drinks bleiben zuhause.</em></p>
  <p class="footer">Seite 4 · ${esc(d.lagerName)} ${d.jahr}</p>
</div>

<div class="page">
  <h2>Wichtige «Kinder-Informationen»</h2>
  <p><em>Dieses Dokument unterliegt der Geheimhaltung.</em></p>
  <p>Bitte zusammen mit einer Kopie des Impfausweises mitbringen oder bis spätestens an die Lagerleitung senden.</p>
  <div class="formular">
    <label>Name, Vorname des Kindes:</label>
    <label>Muss Ihr Kind Medikamente einnehmen? Welche? Wann?</label>
    <label>Weitere Bemerkungen (Allergien, Unverträglichkeiten):</label>
    <label>Ihr Aufenthaltsort während des Lagers:</label>
    <label>Weitere Hinweise (Nachtwandeln, Bettnässen, usw.):</label>
    <label>Die Versicherung ist Sache der Teilnehmer/innen!</label>
    <label>Ort, Datum: &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; Unterschrift eines Elternteils:</label>
  </div>
  <p class="footer">Seite 5 · ${esc(d.lagerName)} ${d.jahr}</p>
</div>

</body></html>`

  const win = window.open('', '_blank')
  if (!win) return
  win.document.write(html)
  win.document.close()
  win.onload = () => {
    win.document.title = `Elterninfo-${d.jahr}.pdf`
    win.print()
  }
}
