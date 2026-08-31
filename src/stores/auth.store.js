// Store de autenticación (Pinia).
// Login vía Supabase Auth (compartido con flota, email/password). El rol se
// resuelve contra plantas_usuarios_roles (propio de este proyecto — ver
// supabase/migrations/07_roles_y_rpc_atomicas.sql y memory/pending.md para
// por qué no se reusa flota_roles directamente). nombre para mostrar es
// lectura best-effort de flota_usuarios_email (solo lectura,
// memory/architecture.md).

import { defineStore } from 'pinia'
import { supabase } from '@/config/supabase'

// Matriz de permisos por rol — "Logica sis. plantas v1.rtf" §3 (7 roles).
// Es la fuente para mostrar/ocultar UI. El enforcement real y no salteable
// vive en las RPC (registrar_pesada_bascula, registrar_carga_hormigon) y,
// cuando se definan, en RLS — esto solo evita que la UI ofrezca acciones que
// el server va a rechazar igual.
export const PERMISOS_POR_ROL = {
  admin: { tabs: 'todas', crearPedido: true, confirmar: true, despachar: true, stock: 'editar', verVentas: true },
  // simulador: solo admin/plantista lo tienen explícito en ambos .rtf y en
  // el relevamiento en vivo (menú real de produccion.vialtec.app) — el
  // resto de los roles no lo lista ninguno de los dos documentos.
  plantista: {
    tabs: ['dashboard', 'pedidos', 'plan-semanal', 'despachos', 'stock', 'simulador', 'bascula', 'formulas', 'maestros'],
    crearPedido: true,
    confirmar: true,
    despachar: true,
    stock: 'editar',
    verVentas: true,
  },
  // encargado/supervisor: "ver Despachos" acá solo controla si el TAB
  // aparece — el filtrado real a "solo sus despachos" (memory/business-
  // rules.md, v1.rtf §257) es de la etapa de RLS fina/visibilidad por obra,
  // todavía PENDIENTE (memory/pending.md, P0.2). Hoy ambos roles ven todos.
  encargado: { tabs: ['dashboard', 'pedidos', 'despachos'], crearPedido: true, confirmar: false, despachar: false, stock: false, verVentas: true },
  supervisor: {
    tabs: ['dashboard', 'pedidos', 'plan-semanal', 'despachos'],
    crearPedido: true,
    confirmar: false,
    despachar: false,
    stock: false,
    verVentas: false,
  },
  balancero: { tabs: ['bascula', 'stock', 'maestros'], crearPedido: false, confirmar: false, despachar: false, stock: 'ver', verVentas: false },
  gerencia: {
    tabs: ['dashboard', 'pedidos', 'plan-semanal', 'despachos', 'stock', 'formulas'],
    crearPedido: false,
    confirmar: false,
    despachar: false,
    stock: 'ver',
    verVentas: true,
  },
  plantista_hormigon: { tabs: ['pedidos'], crearPedido: false, confirmar: false, despachar: false, stock: false, verVentas: false },
}

export const useAuthStore = defineStore('auth', {
  state: () => ({
    user: null,
    nombre: null,
    rol: null,
    verTodasObras: false,
    verVentas: false,
    obraIds: [],
    cargando: false,
    listo: false, // true cuando ya se resolvió la sesión inicial (evita parpadeo en los guards)
  }),

  getters: {
    estaLogueado: (state) => !!state.user,
    permisos: (state) => (state.rol ? PERMISOS_POR_ROL[state.rol] : null),
    puedeVerTab: (state) => (tab) => {
      const p = state.rol ? PERMISOS_POR_ROL[state.rol] : null
      if (!p) return false
      return p.tabs === 'todas' || p.tabs.includes(tab)
    },
  },

  actions: {
    async _cargarPerfil(email) {
      const { data: rolRow, error: errorRol } = await supabase
        .from('plantas_usuarios_roles')
        .select('rol, ver_todas_obras, ver_ventas, obra_ids, activo')
        .eq('email', email)
        .maybeSingle()

      if (errorRol) throw errorRol
      if (!rolRow || !rolRow.activo) {
        await supabase.auth.signOut()
        throw new Error(
          'Tu usuario no tiene un rol asignado (o está inactivo) en VialTec Plantas. Pedile a un admin que te lo asigne.'
        )
      }

      this.rol = rolRow.rol
      this.verTodasObras = rolRow.ver_todas_obras
      this.verVentas = rolRow.ver_ventas
      this.obraIds = rolRow.obra_ids ?? []

      // Nombre para mostrar — lectura best-effort desde flota_usuarios_email,
      // no bloquea el login si falla (memory/architecture.md: solo lectura
      // sobre flota_*).
      const { data: perfilFlota } = await supabase.from('flota_usuarios_email').select('nombre').eq('email', email).maybeSingle()
      this.nombre = perfilFlota?.nombre ?? email
    },

    async login(email, password) {
      this.cargando = true
      try {
        const { data, error } = await supabase.auth.signInWithPassword({ email, password })
        if (error) throw error
        this.user = data.user
        await this._cargarPerfil(data.user.email)
      } catch (e) {
        this.$reset()
        throw e
      } finally {
        this.cargando = false
      }
    },

    /** Se llama una vez al arrancar la app (router guard), para restaurar sesión tras un refresh. */
    async restaurarSesion() {
      this.cargando = true
      try {
        const { data } = await supabase.auth.getSession()
        if (data.session?.user) {
          this.user = data.session.user
          await this._cargarPerfil(data.session.user.email)
        }
      } catch (e) {
        // Sesión inválida o usuario sin rol asignado -> queda deslogueado, sin tirar la app.
        this.$reset()
      } finally {
        this.cargando = false
        this.listo = true
      }
    },

    async logout() {
      await supabase.auth.signOut()
      this.$reset()
      this.listo = true
    },
  },
})
