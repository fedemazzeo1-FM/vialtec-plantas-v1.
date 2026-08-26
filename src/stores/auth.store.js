// Store de autenticación (Pinia).
// Login vía Supabase Auth; el rol/permisos se resuelven contra las tablas
// flota_* compartidas con el sistema de flota. Ver memory/architecture.md y
// memory/business-rules.md (sección Roles) antes de completar este service.

import { defineStore } from 'pinia'
import { supabase } from '@/config/supabase'

export const useAuthStore = defineStore('auth', {
  state: () => ({
    user: null,
    rol: null,
    obraIds: [],
    verTodasObras: false,
    verVentas: false,
    cargando: false,
  }),

  getters: {
    estaLogueado: (state) => !!state.user,
  },

  actions: {
    async login(email, password) {
      // TODO: signInWithPassword + resolver rol/permisos contra flota_usuarios /
      // flota_roles. No implementado todavía — ver memory/pending.md.
      throw new Error('auth.store: login() no implementado todavía')
    },

    async logout() {
      await supabase.auth.signOut()
      this.$reset()
    },
  },
})
