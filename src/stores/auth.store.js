// Store de autenticación (Pinia).
// Login vía Supabase Auth (compartido con flota, email/password). El rol se
// resuelve contra plantas_usuarios_roles (propio de este proyecto — ver
// supabase/migrations/07_roles_y_rpc_atomicas.sql y memory/pending.md para
// por qué no se reusa flota_roles directamente). nombre para mostrar es
// lectura best-effort de flota_usuarios_email (solo lectura,
// memory/architecture.md).

import { defineStore } from 'pinia'
import { supabase } from '@/config/supabase'

// Fix 2026-09-01: App.vue (onMounted) y el guard de router/index.js llaman a
// restaurarSesion() en el mismo arranque, ambos viendo `listo === false` en
// el mismo tick — sin esta guarda quedaban DOS llamadas concurrentes a
// supabase.auth.getSession() + _cargarPerfil() en cada carga de página. No
// rompía nada (ambas terminaban en el mismo estado final), pero duplicaba
// requests de red innecesariamente en cada F5. Se comparte la misma promesa
// en vuelo entre llamadas concurrentes.
let promesaRestaurarSesion = null

// Mapeo tab (router meta / nav.js) -> modulo de plantas_permisos. 'usuarios'
// no está: el módulo "Administración" es SIEMPRE admin-only, fijo, no pasa
// por la matriz (migración 26 — mismo piso de seguridad que
// plantas_tiene_permiso() del lado del servidor, ver ese archivo).
// 'dashboard' (Home) SÍ pasa por la matriz desde la migración 30 (pedido de
// Federico 2026-09-07: antes era un caso especial siempre visible, sin
// togglable) — sembrada en `true` para los 6 roles no-admin existentes, así
// que aplicar esa migración no le sacó Home a nadie hasta que se destilde a
// propósito desde Administración → Roles.
const TAB_A_MODULO = {
  dashboard: 'dashboard',
  pedidos: 'pedidos',
  'plan-semanal': 'plan_semanal',
  despachos: 'despachos',
  stock: 'stock',
  simulador: 'simulador',
  bascula: 'bascula',
  formulas: 'formulas',
  maestros: 'maestros',
}

// Evita suscribir el listener de onAuthStateChange más de una vez (restaurarSesion()
// puede en teoría llamarse de nuevo tras un logout/remount) — mismo criterio que
// promesaRestaurarSesion de arriba, pero para algo que solo debe engancharse 1 vez.
let escuchandoCambiosAuth = false

export const useAuthStore = defineStore('auth', {
  state: () => ({
    user: null,
    nombre: null,
    rol: null,
    verTodasObras: false,
    verVentas: false,
    obraIds: [],
    // Set de módulos con permiso "ver" habilitado (2026-09-06, migración 26
    // — matriz real de permisos, ver plantas_permisos/plantas_tiene_permiso
    // en supabase/migrations/26_matriz_permisos_roles.sql). Vacío para
    // admin: admin tiene bypass total, no se calcula desde acá.
    modulosVer: new Set(),
    cargando: false,
    listo: false, // true cuando ya se resolvió la sesión inicial (evita parpadeo en los guards)
    // true tras click en un link de recuperación de contraseña (evento PASSWORD_RECOVERY
    // de Supabase, ver escucharCambiosAuth() más abajo) — App.vue/LoginView.vue muestran el
    // formulario de "Crear nueva contraseña" en vez del login/dashboard normal mientras esto
    // sea true, aunque la sesión temporal del link ya haya resuelto un perfil válido y
    // estaLogueado dé true. Mismo patrón que vialtec-flota-v2 (2026-09-08, Federico pidió
    // clonar el login de Flota, que ya tenía este flujo — acá no existía todavía).
    isPasswordRecovery: false,
  }),

  getters: {
    estaLogueado: (state) => !!state.user,
    puedeVerTab: (state) => (tab) => {
      if (!state.rol) return false
      if (state.rol === 'admin') return true
      if (tab === 'usuarios') return false // Administración: siempre admin-only, fijo
      const modulo = TAB_A_MODULO[tab]
      return modulo ? state.modulosVer.has(modulo) : false
    },
    // Fix 2026-09-14 (bug real reportado por Federico: un balancero logueaba
    // bien pero la pantalla quedaba congelada en /login, sin redirigir a
    // ningún módulo). Causa real: router/index.js redirigía SIEMPRE a
    // `{ name: 'dashboard' }` tanto desde /login como desde cualquier tab sin
    // permiso — funciona para casi todos los roles (que sí tienen "ver" en
    // dashboard, migración 30), pero balancero tiene
    // dashboard/ver = false en plantas_permisos (rol pensado para vivir
    // 100% en Báscula) — el guard entraba en un loop infinito
    // login -> dashboard -> (sin permiso) -> dashboard -> ... que Vue Router
    // corta solo, dejando al usuario varado en la última pantalla real
    // (login). Esta getter devuelve la primera tab con permiso real, en el
    // mismo orden en que aparecen en el sidebar (nav.js) — el router la usa
    // en vez de asumir 'dashboard' a ciegas.
    primeraTabDisponible(state) {
      if (state.rol === 'admin') return 'dashboard'
      const ORDEN_TABS = ['dashboard', 'pedidos', 'plan-semanal', 'despachos', 'bascula', 'stock', 'simulador', 'formulas', 'maestros']
      return ORDEN_TABS.find((tab) => this.puedeVerTab(tab)) ?? null
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

      // Matriz real de "ver" por módulo (migración 26) — admin no la
      // necesita (bypass total en el getter de arriba), así nos ahorramos
      // el request para el rol más frecuente en el día a día del admin.
      if (rolRow.rol === 'admin') {
        this.modulosVer = new Set()
      } else {
        const { data: filasVer, error: errorVer } = await supabase
          .from('plantas_permisos')
          .select('modulo')
          .eq('rol_id', rolRow.rol)
          .eq('accion', 'ver')
          .eq('habilitado', true)
        // No tumba el login si falla — degradación segura: sin filas, el
        // usuario no ve ninguna pestaña más que Home (mismo criterio de
        // "seguro por default" que plantas_tiene_permiso() del servidor).
        this.modulosVer = new Set(errorVer ? [] : (filasVer ?? []).map((f) => f.modulo))
      }

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

    /**
     * Se llama al arrancar la app (App.vue Y el guard de router/index.js
     * llaman a esto en el mismo tick — ver nota de `promesaRestaurarSesion`
     * arriba), para restaurar sesión tras un refresh (F5) o pestaña nueva.
     */
    async restaurarSesion() {
      this.escucharCambiosAuth()
      if (promesaRestaurarSesion) return promesaRestaurarSesion
      promesaRestaurarSesion = this._restaurarSesionInterna().finally(() => {
        promesaRestaurarSesion = null
      })
      return promesaRestaurarSesion
    },

    async _restaurarSesionInterna() {
      this.cargando = true
      try {
        const { data } = await supabase.auth.getSession()
        if (data.session?.user) {
          this.user = data.session.user
          await this._cargarPerfil(data.session.user.email)
        }
      } catch (e) {
        // Sesión inválida o usuario sin rol asignado -> queda deslogueado, sin tirar la app.
        // $reset() no debe pisar isPasswordRecovery: si esto corre justo después de que el
        // link de recovery ya prendió el flag (sesión temporal sin perfil resuelto todavía,
        // o con error), LoginView tiene que seguir mostrando "Crear nueva contraseña", no
        // volver al login vacío perdiendo el contexto del link recién clickeado.
        const eraRecovery = this.isPasswordRecovery
        this.$reset()
        this.isPasswordRecovery = eraRecovery
      } finally {
        this.cargando = false
        this.listo = true
      }
    },

    // Único punto que escucha onAuthStateChange — sin esto, el evento PASSWORD_RECOVERY que
    // dispara Supabase al procesar el token del link (#access_token=...&type=recovery) se
    // pierde siempre (no hay forma de "consultarlo" después, es un evento puntual) y la app
    // trataría la sesión temporal del link como un login normal. Ver auth.store.js de
    // vialtec-flota-v2, mismo patrón, ya probado en producción.
    escucharCambiosAuth() {
      if (escuchandoCambiosAuth) return
      escuchandoCambiosAuth = true
      supabase.auth.onAuthStateChange((event) => {
        if (event === 'PASSWORD_RECOVERY') this.isPasswordRecovery = true
      })
    },

    // "¿Olvidaste tu contraseña?" (LoginView.vue) — redirectTo explícito para que el link
    // del mail siempre apunte a este dominio (sea cual sea), no al Site URL que tenga
    // configurado el proyecto de Supabase compartido con flota en su Dashboard.
    async enviarRecoveryEmail(email) {
      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${window.location.origin}/login`,
      })
      if (error) throw error
    },

    // Confirma la nueva contraseña durante un flujo de recovery — requiere la sesión
    // temporal que el SDK ya estableció solo a partir del token del link (ver arriba).
    // Reusa _cargarPerfil() para dejar el store poblado igual que un login normal.
    async completarRecoveryPassword(nuevaPassword) {
      this.cargando = true
      try {
        const { data, error } = await supabase.auth.updateUser({ password: nuevaPassword })
        if (error) throw error
        this.user = data.user
        await this._cargarPerfil(data.user.email)
        this.isPasswordRecovery = false
      } catch (e) {
        this.$reset()
        throw e
      } finally {
        this.cargando = false
        this.listo = true
      }
    },

    async logout() {
      await supabase.auth.signOut()
      this.$reset()
      this.listo = true
      // Terminal compartida entre turnos/operadores en Báscula (2026-09-14,
      // pedido de Federico): las puertas en curso viven a nivel de módulo
      // (useBascula.js) para sobrevivir a un remount de la vista — sin este
      // reset, el próximo balancero que loguee en la misma pestaña vería
      // las puertas sin guardar del turno anterior. Import DINÁMICO a
      // propósito (no estático arriba del archivo): auth.store.js se carga
      // eager para toda la app desde el arranque — un import estático de
      // useBascula.js lo arrastraría al bundle principal para TODOS los
      // roles, rompiendo el code-splitting por ruta que Báscula ya tenía
      // (verificado: el chunk de BasculaView bajaba de ~35kB a ~23kB y ese
      // peso se corría al bundle principal). Con import() dinámico, el
      // módulo de Báscula se resuelve del mismo chunk lazy de siempre —
      // recién se pide la primera vez que alguien hace logout, sin costo
      // para el resto de los roles que nunca entran a Báscula.
      const { resetPuertasBascula } = await import('@/modules/bascula/composables/useBascula')
      resetPuertasBascula()
    },
  },
})
