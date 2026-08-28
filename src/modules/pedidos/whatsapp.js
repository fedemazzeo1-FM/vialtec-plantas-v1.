// Helper de notificaciones WhatsApp (el "WppToast" del sistema legado —
// Logica sis. plantas v1.rtf §8 / v2.rtf §6): el sistema NUNCA envía por
// API. Arma un mensaje pre-armado y un link a wa.me — la UI muestra un
// toast con ese mensaje y un botón que abre el link en una pestaña nueva;
// el usuario elige el contacto en su WhatsApp y lo manda él mismo.
//
// Sin teléfono todavía: `plantas_usuarios_roles` no tiene una columna de
// teléfono hoy (memory/relevamiento-sistema-viejo.md, gap de Usuarios), así
// que se arma wa.me/?text=... sin número de destino — el día que exista un
// teléfono en el perfil, pasarlo como segundo argumento de `urlWhatsapp()`
// y listo, arma wa.me/<telefono>?text=... automáticamente.
//
// Funciones puras, sin Supabase — no es un service (memory/conventions.md:
// los services son solo acceso a datos). Vive en el módulo Pedidos porque
// es lógica específica de sus 2 disparadores (crear/confirmar), no
// compartida con otro módulo.

function destinoLabel(pedido, obraNombre) {
  return pedido.tipo_pedido === 'venta' ? pedido.cliente_externo || 'cliente externo' : obraNombre || 'obra'
}

function unidad(pedido) {
  return pedido.tipo === 'hormigon' ? 'm³' : 'tn'
}

export function urlWhatsapp(mensaje, telefono) {
  const texto = encodeURIComponent(mensaje)
  return telefono ? `https://wa.me/${telefono}?text=${texto}` : `https://wa.me/?text=${texto}`
}

/** Al crear un pedido (solicitado) — dirigido al plantista. */
export function toastCrearPedido(pedido, { obraNombre }) {
  const mensaje = `🔔 Nuevo pedido de ${pedido.tipo === 'hormigon' ? 'hormigón' : 'asfalto'}\n${destinoLabel(pedido, obraNombre)} — ${pedido.cantidad_solicitada} ${unidad(pedido)}\nFecha: ${pedido.fecha_programada}\nSolicitado por: ${pedido.encargado || '—'}`
  return { titulo: 'Avisar al plantista', mensaje, url: urlWhatsapp(mensaje) }
}

/** Al confirmar (solicitado → confirmado) — dirigido al encargado que pidió. */
export function toastConfirmarPedido(pedido, { obraNombre }) {
  const mensaje = `✅ Tu pedido de ${pedido.tipo === 'hormigon' ? 'hormigón' : 'asfalto'} fue confirmado\n${destinoLabel(pedido, obraNombre)} — ${pedido.cantidad_solicitada} ${unidad(pedido)}\nFecha: ${pedido.fecha_programada}`
  return { titulo: 'Avisar al encargado', mensaje, url: urlWhatsapp(mensaje) }
}

/**
 * Al confirmar un pedido de HORMIGÓN — mensaje adicional para el operador de
 * hormigón (en el legado va a un usuario hardcodeado "angel"/u12 — acá no
 * hardcodeamos ningún contacto puntual, el balancero/plantista elige el
 * destinatario real en WhatsApp).
 */
export function toastConfirmarHormigonOperador(pedido, { obraNombre }) {
  const mensaje = `🧱 Hormigón confirmado para producción\n${destinoLabel(pedido, obraNombre)} — ${pedido.cantidad_solicitada} m³\nFecha: ${pedido.fecha_programada}`
  return { titulo: 'Avisar al operador de hormigón', mensaje, url: urlWhatsapp(mensaje) }
}
