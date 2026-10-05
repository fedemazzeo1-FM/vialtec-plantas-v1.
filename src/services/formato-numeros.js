// Formatters de numeración transversales (memory/architecture.md: lógica
// compartida entre módulos va en un helper común, no duplicada en cada uno).
// Distinto de formatearNumeroVale() (bascula.service.js, 8 dígitos — la
// numeración de vales continúa el papel del legado desde 9579): el remito es
// una numeración 100% nueva desde la migración 36, Federico pidió que se vea
// con cero a la izquierda a 5 dígitos ("00001, 00002, etc.").

export function formatearNumeroRemito(numero) {
  if (numero == null) return '—'
  return String(numero).padStart(5, '0')
}

// Número correlativo de pedido (migración 52): "P-0001", 4 dígitos (más si
// hace falta). Gemela SQL: plantas_etiqueta_pedido(). Sin número (fila vieja
// en memoria, pedido todavía sin guardar) devuelve '' para que el caller
// pueda omitirlo.
export function formatearNumeroPedido(numero) {
  if (numero == null || numero === '') return ''
  return `P-${String(numero).padStart(4, '0')}`
}

/** 'P-0230', 'p230', '230' → 230. Texto sin dígitos → null. */
export function parsearNumeroPedido(texto) {
  const digitos = String(texto ?? '').replace(/\D/g, '')
  return digitos ? Number(digitos) : null
}
