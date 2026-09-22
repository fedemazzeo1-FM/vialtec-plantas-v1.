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
//
// Fix 2026-09-22 (bug reportado por Federico, mobile: "la tarjeta de login
// queda superpuesta arriba de la interfaz principal, a veces colgada"):
// `auth.estaLogueado` pasa a `true` de forma SÍNCRONA dentro de
// `auth.login()` (auth.store.js: `this.user = data.user` antes incluso de
// cargar rol/permisos), pero la URL sigue siendo `/login` hasta que
// `LoginView.vue#enviar()` termina de esperar todo `auth.login()` y recién
// ahí llama a `router.replace(...)`. En esa ventana (varios round-trips a
// Supabase — rol, permisos, nombre — más lentos en mobile), este `v-if`
// ya elige `MobileLayout`/`DesktopLayout`, pero el `<router-view>` de esos
// layouts todavía resuelve a la ruta `/login` (name: 'login') y renderiza
// LoginView DE NUEVO, ahora anidado dentro del `<main>` del layout — eso es
// el "cuadrado flotante": la card de login centrada adentro del área de
// contenido, con el header/nav del layout alrededor. No es un problema de
// z-index (LoginView no tiene posicionamiento fijo) sino de dos fuentes de
// verdad (estado de auth vs. ruta actual) desincronizadas por un instante.
// Fix: no montar el layout hasta que la ruta TAMBIÉN dejó de ser 'login' —
// mientras tanto, mismo loader que ya se usa para "sesión no resuelta
// todavía". Ver también auth.store.js#_cargarPerfil (paralelizado en el
// mismo fix, para acortar esta ventana).
import { onMounted } from 'vue'
import { useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth.store'
import { useBreakpoint } from '@/composables/useBreakpoint'
import DesktopLayout from '@/layouts/DesktopLayout.vue'
import MobileLayout from '@/layouts/MobileLayout.vue'
import LoginView from '@/views/LoginView.vue'

const auth = useAuthStore()
const route = useRoute()
const { esMobile } = useBreakpoint()

onMounted(() => {
  if (!auth.listo) auth.restaurarSesion()
})
</script>

<template>
  <div v-if="!auth.listo" class="flex min-h-screen items-center justify-center text-sm text-gray-400">Cargando…</div>
  <LoginView v-else-if="!auth.estaLogueado || auth.isPasswordRecovery" />
  <div v-else-if="route.name === 'login'" class="flex min-h-screen items-center justify-center text-sm text-gray-400">Cargando…</div>
  <MobileLayout v-else-if="esMobile" />
  <DesktopLayout v-else />
</template>
