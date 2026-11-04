// Instancia ÚNICA de Supabase para todo el proyecto.
// No crear otro createClient() en ningún otro archivo — importar siempre desde acá.
// Proyecto compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny).
// Ver memory/architecture.md para el detalle de tablas flota_* vs plantas_*.

import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Faltan VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY en las variables de entorno.'
  )
}

// Sesión vencida (2026-11-04): una lectura rechazada por falta de sesión
// (401) avisa a quien escuche (auth.store.js), que verifica la sesión y,
// si ya no existe, muestra "Tu sesión venció" y lleva al login. No hay
// import del store acá (evita una dependencia circular): se registra con
// alRechazarSesion().
const escuchas401 = new Set()

/** @param {() => void} fn @returns {() => void} */
export function alRechazarSesion(fn) {
  escuchas401.add(fn)
  return () => escuchas401.delete(fn)
}

async function fetchConAvisoDeSesion(...args) {
  const respuesta = await fetch(...args)
  if (respuesta.status === 401) {
    const url = String(args[0]?.url ?? args[0] ?? '')
    if (url.includes('/rest/v1/')) {
      // Fuera del flujo del pedido: el store consulta la sesión, y eso no
      // tiene que bloquear ni demorar esta respuesta.
      setTimeout(() => escuchas401.forEach((fn) => fn()), 0)
    }
  }
  return respuesta
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  global: { fetch: fetchConAvisoDeSesion },
})
