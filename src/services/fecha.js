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

// ---------------------------------------------------------------------------
// Límites de rango de fecha contra columnas timestamptz (2026-09-04, bug
// real encontrado en Báscula: un filtro "1 al 4 de septiembre" mostraba
// bastante menos que el sistema legado).
//
// El problema: pasar una fecha "pelada" ('YYYY-MM-DD') o un string
// 'YYYY-MM-DDTHH:MM:SS' sin offset directo a un filtro de Supabase hace que
// Postgres la castee como si ya estuviera en el timezone de la sesión (UTC
// en este proyecto, ver `select current_setting('TimeZone')`), NO como
// medianoche LOCAL (Argentina, UTC-3). Contra una columna `date` esto no
// importa (`fecha_programada` de Pedidos/Despachos) pero contra una
// `timestamptz` (`fecha_pesada` de plantas_vales, `fecha_movimiento` de
// plantas_stock_movimientos, `fecha` de plantas_v_despachos_camion) corre el
// corte 3hs de más temprano de lo esperado: un `.lte(hasta, '2026-09-04T23:59:59')`
// termina siendo "23:59:59 UTC" = "20:59:59 local", perdiendo en silencio
// los movimientos cargados esa noche entre las 21:00 y las 23:59.
//
// Fix: construir un Date real con el string SIN sufijo 'Z' ni offset (el
// motor de JS lo interpreta en el timezone LOCAL del navegador) y recién ahí
// convertir a ISO — así el offset se aplica una sola vez, correctamente.
// `limiteFinDiaLocalExclusivo()` devuelve la medianoche del día SIGUIENTE
// para usar con `.lt()` (nunca `.lte()` + `.slice(0, 10)`, que tira el
// horario y reintroduce el mismo bug).

/** Medianoche LOCAL de `fechaISO` ('YYYY-MM-DD'), en ISO — límite inferior inclusivo (`.gte()`). */
export function limiteInicioDiaLocal(fechaISO) {
  return new Date(`${fechaISO}T00:00:00`).toISOString()
}

/** Medianoche LOCAL del día siguiente a `fechaISO`, en ISO — límite superior exclusivo (`.lt()`). */
export function limiteFinDiaLocalExclusivo(fechaISO) {
  const inicioDiaSiguiente = new Date(`${fechaISO}T00:00:00`)
  inicioDiaSiguiente.setDate(inicioDiaSiguiente.getDate() + 1)
  return inicioDiaSiguiente.toISOString()
}
