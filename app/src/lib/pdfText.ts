import * as pdfjsLib from 'pdfjs-dist'
// @ts-ignore -- Vite-spezifischer Worker-URL-Import
import pdfjsWorker from 'pdfjs-dist/build/pdf.worker.mjs?url'

pdfjsLib.GlobalWorkerOptions.workerSrc = pdfjsWorker

// Extrahiert Text pro Seite (statt einem grossen String), damit man das PDF
// später in Häppchen an eine LLM-Extraktion schicken kann.
export async function extractPdfPages(
  file: File,
  onProgress?: (seite: number, total: number) => void,
): Promise<string[]> {
  const buffer = await file.arrayBuffer()
  const pdf = await pdfjsLib.getDocument({ data: buffer }).promise

  const pages: string[] = []
  for (let i = 1; i <= pdf.numPages; i++) {
    const page = await pdf.getPage(i)
    const content = await page.getTextContent()
    const text = content.items.map((item: any) => ('str' in item ? item.str : '')).join(' ')
    pages.push(`--- Seite ${i} ---\n${text}`)
    onProgress?.(i, pdf.numPages)
  }
  return pages
}
