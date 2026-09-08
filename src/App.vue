<script setup>
// Raíz de la app. Gate de sesión: mientras no se resuelve la sesión inicial
// se muestra un loader (evita parpadeo del login), sin sesión se muestra
// LoginView a pantalla completa (sin sidebar), y con sesión se elige layout
// según viewport (roadmap Mobile, memory/pending.md 2026-09-02):
// DesktopLayout (sidebar) o MobileLayout (nav inferior + hoja "Más"),
// mismo breakpoint (768px) que useBreakpoint()/Tailwind `md:` en toda la app.
//
// auth.isPasswordRecovery (2026-09-08, flujo "¿Olvidaste tu contraseña?"): la sesión
// temporal que abre un link de recovery puede resolver un perfil válido (estaLogueado
// pasa a true) antes de que el usuario haya elegido su nueva contraseña — sin este chequeo
// entraría directo al dashboard salteándose el formulario de "Crear nueva contraseña".
import { onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth.store'
import { useBreakpoint } from '@/composables/useBreakpoint'
import DesktopLayout from '@/layouts/DesktopLayout.vue'
import MobileLayout from '@/layouts/MobileLayout.vue'
import LoginView from '@/views/LoginView.vue'

const auth = useAuthStore()
const { esMobile } = useBreakpoint()

onMounted(() => {
  if (!auth.listo) auth.restaurarSesion()
})
</script>

<template>
  <div v-if="!auth.listo" class="flex min-h-screen items-center justify-center text-sm text-gray-400">Cargando…</div>
  <LoginView v-else-if="!auth.estaLogueado || auth.isPasswordRecovery" />
  <MobileLayout v-else-if="esMobile" />
  <DesktopLayout v-else />
</template>
