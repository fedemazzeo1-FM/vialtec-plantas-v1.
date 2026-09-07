// Helper de notificaciones WhatsApp (el "WppToast" del sistema legado —
// Logica sis. plantas v1.rtf §8 / v2.rtf §6): el sistema NUNCA envía por
// API. Arma un mensaje pre-armado y un link a wa.me — la UI muestra un
// toast con ese mensaje y un botón que abre el link en una pestaña nueva;
// el usuario elige el contacto en su WhatsApp y lo manda él mismo.
//
// `plantas_usuarios_roles` sigue sin columna de teléfono propia (memory/
// relevamiento-sistema-viejo.md, gap de Usuarios) — pero el sistema de flota
// (`flota_usuarios_email.telefono`) sí lo tiene para varios usuarios
// (2026-09-07, ver `flota.service.js#fetchTelefonoPorNombre()`). Cuando se
// puede resolver un destinatario CONCRETO y sin ambigüedad (el encargado que
// pidió, por nombre exacto) el caller pasa `telefono` como segundo argumento
// de `urlWhatsapp()` y arma wa.me/<telefono>?text=... directo a su chat
// personal; sin match, sigue cayendo a wa.me/?text=... (el usuario elige el
// contacto a mano) — nunca se envía a un número adivinado.
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

/**
 * Al confirmar (solicitado → confirmado) — dirigido al encargado que pidió.
 * `telefono` (opcional, ver flota.service.js#fetchTelefonoPorNombre) manda
 * el link directo a su chat personal en vez de abrir wa.me sin destinatario.
 */
export function toastConfirmarPedido(pedido, { obraNombre, telefono } = {}) {
  const mensaje = `✅ Tu pedido de ${pedido.tipo === 'hormigon' ? 'hormigón' : 'asfalto'} fue confirmado\n${destinoLabel(pedido, obraNombre)} — ${pedido.cantidad_solicitada} ${unidad(pedido)}\nFecha: ${pedido.fecha_programada}`
  return { titulo: 'Avisar al encargado', mensaje, url: urlWhatsapp(mensaje, telefono) }
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
