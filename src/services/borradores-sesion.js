// Borradores al vencer la sesión (2026-11-04, pedido de Federico): si la
// sesión vence mientras se está cargando algo, se guarda lo escrito y se
// recupera al volver a entrar (mismo usuario, misma pestaña).
//
// Cada pantalla registra qué tiene a medio cargar:
//   - registrarBorrador(clave, etiqueta, obtener): `obtener()` devuelve los
//     datos a guardar (JSON) o null si no hay nada en curso.
//   - con { soloAviso: true } no se guarda nada (no es fácil de restaurar,
//     ej. un despacho): solo se avisa que se perdió.
// auth.store.js#marcarSesionVencida() llama a guardarBorradores() y la
// pantalla, al volver, llama a tomarBorrador().
//
// sessionStorage (por pestaña) y no localStorage: un borrador no tiene que
// aparecer en otra pestaña ni en otra computadora. Todo con try/catch
// (modo privado de Safari puede tirar).

const PREFIJO = 'vt-borrador:'
const VIGENCIA_MS = 12 * 60 * 60 * 1000

const registrados = new Map() // clave -> { etiqueta, obtener, soloAviso }

/** @returns {() => void} función para darlo de baja (al desmontar). */
export function registrarBorrador(clave, etiqueta, obtener, { soloAviso = false } = {}) {
  const registro = { etiqueta, obtener, soloAviso }
  registrados.set(clave, registro)
  return () => {
    if (registrados.get(clave) === registro) registrados.delete(clave)
  }
}

/**
 * Guarda todo lo que esté en curso.
 * @returns {{ guardados: string[], sinGuardar: string[] }} etiquetas para el aviso.
 */
export function guardarBorradores(email) {
  const guardados = []
  const sinGuardar = []
  for (const [clave, { etiqueta, obtener, soloAviso }] of registrados) {
    let datos = null
    try {
      datos = obtener()
    } catch {
      datos = null
    }
    if (!datos) continue
    if (soloAviso) {
      sinGuardar.push(etiqueta)
      continue
    }
    try {
      sessionStorage.setItem(PREFIJO + clave, JSON.stringify({ email, fecha: Date.now(), datos }))
      guardados.push(etiqueta)
    } catch {
      sinGuardar.push(etiqueta)
    }
  }
  return { guardados, sinGuardar }
}

/** Devuelve y borra el borrador si es del mismo usuario y reciente; si no, null. */
export function tomarBorrador(clave, email) {
  let crudo = null
  try {
    crudo = sessionStorage.getItem(PREFIJO + clave)
    sessionStorage.removeItem(PREFIJO + clave)
  } catch {
    return null
  }
  if (!crudo || !email) return null
  try {
    const borrador = JSON.parse(crudo)
    if (borrador.email !== email || Date.now() - borrador.fecha > VIGENCIA_MS) return null
    return borrador.datos
  } catch {
    return null
  }
}

/** Descarta los borradores de la pestaña (entró otro usuario). */
export function descartarBorradores() {
  try {
    Object.keys(sessionStorage)
      .filter((k) => k.startsWith(PREFIJO))
      .forEach((k) => sessionStorage.removeItem(k))
  } catch {
    // sin sessionStorage: no hay nada que descartar
  }
}
