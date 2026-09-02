<script setup>
// Login por email/password contra Supabase Auth (compartido con flota). El
// rol de VialTec Plantas se resuelve dentro de auth.store.js#login() contra
// plantas_usuarios_roles — si el usuario no tiene fila ahí, login() tira un
// error legible y esta vista lo muestra tal cual (memory/pending.md).

import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth.store'
import VButton from '@/components/shared/VButton.vue'
import logoVialtec from '@/assets/img/logo-vialtec.png'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const email = ref('')
const password = ref('')
const error = ref(null)
const enviando = ref(false)

async function enviar() {
  error.value = null
  enviando.value = true
  try {
    await auth.login(email.value.trim(), password.value)
    router.replace(route.query.redirect || '/dashboard')
  } catch (e) {
    error.value = e.message
  } finally {
    enviando.value = false
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-gray-50">
    <form class="w-full max-w-sm rounded-xl border border-border bg-white p-6 shadow-sm" @submit.prevent="enviar">
      <img :src="logoVialtec" alt="VIAL-TEC S.A." class="mx-auto mb-4 h-14 w-auto" />
      <p class="mb-4 text-center text-sm font-semibold uppercase tracking-wide text-text-soft">Plantas</p>

      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <label class="mb-3 block text-sm text-text-mid">
        Email
        <input
          v-model="email"
          type="email"
          required
          autocomplete="username"
          class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
        />
      </label>
      <label class="mb-4 block text-sm text-text-mid">
        Contraseña
        <input
          v-model="password"
          type="password"
          required
          autocomplete="current-password"
          class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
        />
      </label>

      <VButton type="submit" :disabled="enviando" class="w-full">
        {{ enviando ? 'Ingresando…' : 'Ingresar' }}
      </VButton>
    </form>
  </div>
</template>
