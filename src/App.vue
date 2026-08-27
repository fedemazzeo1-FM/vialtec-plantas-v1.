<script setup>
// Raíz de la app. Gate de sesión: mientras no se resuelve la sesión inicial
// se muestra un loader (evita parpadeo del login), sin sesión se muestra
// LoginView a pantalla completa (sin sidebar), y con sesión el layout normal.
// Por ahora solo existe DesktopLayout — cuando haya detección de
// mobile/breakpoint se elige entre DesktopLayout y MobileLayout acá.
import { onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth.store'
import DesktopLayout from '@/layouts/DesktopLayout.vue'
import LoginView from '@/views/LoginView.vue'

const auth = useAuthStore()

onMounted(() => {
  if (!auth.listo) auth.restaurarSesion()
})
</script>

<template>
  <div v-if="!auth.listo" class="flex min-h-screen items-center justify-center text-sm text-gray-400">Cargando…</div>
  <LoginView v-else-if="!auth.estaLogueado" />
  <DesktopLayout v-else />
</template>
