export function downloadEinkaufPdf(lagerName: string, termine: { einkaufAm: string; deadline: string }[], items: {
  name: string
  menge: string
  bereich: string
  mahlzeit: string
  notiz: string
  erledigt: boolean
}[]) {
  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>Einkaufsliste ${lagerName}</title>
<style>
  body { font-family: Georgia, serif; padding: 2rem; color: #3d3222; }
  h1 { font-size: 1.4rem; }
  table { width: 100%; border-collapse: collapse; margin-top: 1rem; }
  th, td { border: 1px solid #d8cdb0; padding: 0.4rem 0.6rem; text-align: left; font-size: 0.9rem; }
  th { background: #efe8d6; }
  .meta { color: #6b5d3f; font-size: 0.85rem; margin: 0.5rem 0; }
  .erledigt { text-decoration: line-through; color: #999; }
</style></head><body>
<h1>Einkaufsliste – ${escapeHtml(lagerName)}</h1>
${termine.map((t) => `<p class="meta">Einkauf: ${t.einkaufAm} · Deadline Einträge: ${t.deadline}</p>`).join('')}
<table><thead><tr><th>✓</th><th>Artikel</th><th>Menge</th><th>Bereich</th><th>Mahlzeit</th><th>Notiz</th></tr></thead>
<tbody>${items.map((i) => `<tr class="${i.erledigt ? 'erledigt' : ''}">
<td>${i.erledigt ? '☑' : '☐'}</td><td>${escapeHtml(i.name)}</td><td>${escapeHtml(i.menge)}</td>
<td>${escapeHtml(i.bereich)}</td><td>${escapeHtml(i.mahlzeit)}</td><td>${escapeHtml(i.notiz)}</td></tr>`).join('')}
</tbody></table></body></html>`

  const win = window.open('', '_blank')
  if (!win) return
  win.document.write(html)
  win.document.close()
  win.onload = () => win.print()
}

function escapeHtml(s: string) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}
