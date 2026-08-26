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

export const supabase = createClient(supabaseUrl, supabaseAnonKey)
