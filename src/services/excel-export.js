// Export a Excel — helper transversal (memory/conventions.md: lógica
// compartida entre módulos va en un helper común, no duplicada en cada
// service). Usado por Báscula/Stock (roadmap Mobile, memory/pending.md
// 2026-09-02) y cualquier otro módulo que necesite el mismo botón "Excel"
// que ya tenía el legado en varias pantallas (memory/relevamiento-sistema-
// viejo.md — Báscula, Despachos, Stock, Analítica de proveedores).
//
// Librería: `xlsx` (SheetJS, community/última versión en npm) — 100%
// client-side, arma el .xlsx en el navegador con los datos ya cargados, sin
// tocar Supabase de nuevo ni pasar por un backend.
//
// Import DINÁMICO (`await import('xlsx')` adentro de exportarExcel(), no un
// `import` estático arriba): xlsx pesa ~300kB minificado — un import
// estático lo mete en el bundle de CUALQUIER vista que solo referencie este
// archivo (Báscula pasó de ~21kB a ~300kB de chunk antes de este fix), aunque
// el usuario nunca clickee "Excel". Con el import dinámico, Vite lo separa en
// su propio chunk que solo se baja la primera vez que se exporta algo.
export async function exportarExcel(nombreArchivo, hojas) {
  const XLSX = await import('xlsx')
  const libro = XLSX.utils.book_new()

  for (const hoja of hojas) {
    const encabezados = hoja.columnas.map((c) => c.label)
    const filasPlanas = hoja.filas.map((fila) =>
      Object.fromEntries(
        hoja.columnas.map((c) => [c.label, c.format ? c.format(fila[c.key], fila) : (fila[c.key] ?? '')])
      )
    )
    const planilla = XLSX.utils.json_to_sheet(filasPlanas, { header: encabezados })
    // Ancho de columna aproximado al contenido (mínimo el largo del label) —
    // sin esto todas las columnas salen al ancho default de Excel (~8.43),
    // ilegible con más de 2-3 caracteres.
    planilla['!cols'] = hoja.columnas.map((c) => ({
      wch: Math.max(c.label.length, 10, ...filasPlanas.slice(0, 200).map((f) => String(f[c.label] ?? '').length)) + 2,
    }))
    // Fila de headers congelada — igual que cualquier planilla "profesional"
    // con muchas filas, no se pierde de vista qué es cada columna al scrollear.
    planilla['!views'] = [{ state: 'frozen', ySplit: 1 }]
    XLSX.utils.book_append_sheet(libro, planilla, hoja.nombre.slice(0, 31)) // Excel limita el nombre de hoja a 31 caracteres
  }

  XLSX.writeFile(libro, nombreArchivo)
}

/** Nombre de archivo con fecha de hoy, consistente entre todos los exports. */
export function nombreArchivoConFecha(base) {
  const hoy = new Date().toISOString().slice(0, 10)
  return `${base}-${hoy}.xlsx`
}
