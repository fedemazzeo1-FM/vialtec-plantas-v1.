<script setup>
// Login por email/password contra Supabase Auth (compartido con flota). El
// rol de VialTec Plantas se resuelve dentro de auth.store.js#login() contra
// plantas_usuarios_roles — si el usuario no tiene fila ahí, login() tira un
// error legible y esta vista lo muestra tal cual (memory/pending.md).

import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth.store'

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
    <form class="w-full max-w-sm rounded border border-gray-200 bg-white p-6 shadow-sm" @submit.prevent="enviar">
      <p class="mb-4 text-lg font-semibold">VialTec Plantas</p>

      <div v-if="error" class="mb-3 rounded border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">
        {{ error }}
      </div>

      <label class="mb-3 block text-sm">
        Email
        <input
          v-model="email"
          type="email"
          required
          autocomplete="username"
          class="mt-1 w-full rounded border-gray-300 text-sm"
        />
      </label>
      <label class="mb-4 block text-sm">
        Contraseña
        <input
          v-model="password"
          type="password"
          required
          autocomplete="current-password"
          class="mt-1 w-full rounded border-gray-300 text-sm"
        />
      </label>

      <button
        type="submit"
        :disabled="enviando"
        class="w-full rounded bg-gray-900 px-3 py-2 text-sm text-white hover:bg-gray-700 disabled:opacity-50"
      >
        {{ enviando ? 'Ingresando…' : 'Ingresar' }}
      </button>
    </form>
  </div>
</template>
