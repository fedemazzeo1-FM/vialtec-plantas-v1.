// Helpers de fecha transversales (memory/conventions.md: lógica compartida
// entre módulos va en un helper común). Extraído de PlanSemanalView.vue
// 2026-09-02 al necesitar el mismo cálculo en Báscula/Stock (roadmap
// Mobile, memory/pending.md) — un solo lugar para "hoy en formato ISO
// local", no uno por vista.

/**
 * Fecha de hoy en 'YYYY-MM-DD', en la zona horaria LOCAL del navegador (no
 * UTC) — `new Date().toISOString()` a secas trunca a UTC y puede dar el día
 * anterior/siguiente según la hora, lo cual rompe cualquier filtro "hoy" en
 * horarios de planta (madrugada/noche, Argentina UTC-3).
 */
export function hoyISO() {
  const d = new Date()
  d.setMinutes(d.getMinutes() - d.getTimezoneOffset())
  return d.toISOString().slice(0, 10)
}
