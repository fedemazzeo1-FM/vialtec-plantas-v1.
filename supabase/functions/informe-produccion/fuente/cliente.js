// Reemplazo de src/config/supabase.js SOLO para el paquete de la Edge Function informe-produccion (16/11/2026).
// El front crea su cliente con la anon key y la sesión del navegador; la Edge Function corre con service_role y le
// pasa su cliente con usarCliente() antes de leer. Live binding de ES modules: los services que importan `supabase`
// ven el cliente nuevo.
export let supabase = null

export function usarCliente(cliente) {
  supabase = cliente
}

export function alRechazarSesion() {
  return () => {}
}
