// Configuración general de la app (no secretos — eso va en .env / supabase.js).

export const appConfig = {
  nombre: 'VialTec Plantas',
  // Los vales de báscula del sistema anterior siguen una secuencia nativa que
  // empieza en 9579 (ver memory/business-rules.md). Este valor documenta el
  // punto de partida para la migración del historial, no un contador en vivo.
  vales: {
    numeroInicial: 9579,
  },
  // Materiales que nunca se descuentan del stock (ver memory/business-rules.md).
  stock: {
    materialesSinDescuento: ['Agua', 'Purgue'],
  },
  // La semana operativa va de lunes a domingo.
  semana: {
    inicio: 'lunes',
  },
}
