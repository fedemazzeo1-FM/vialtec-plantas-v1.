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
