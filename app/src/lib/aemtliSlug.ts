export function aemtliSlug(name: string): string {
  return name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
}

export function tabIdForAemtli(name: string): string {
  return `aemtli:${aemtliSlug(name)}`
}
