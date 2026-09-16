<script setup>
// Login por email/password contra Supabase Auth (compartido con flota). El
// rol de VialTec Plantas se resuelve dentro de auth.store.js#login() contra
// plantas_usuarios_roles — si el usuario no tiene fila ahí, login() tira un
// error legible y esta vista lo muestra tal cual (memory/pending.md).
//
// Diseño (2026-09-08, pedido explícito de Federico): réplica visual exacta
// de la pantalla de login de vialtec-flota-v2 (equipos2.vialtec.app) — fondo
// cuadriculado + glow, misma card (medidas/padding/radio), mismos estilos de
// input/botón (ver .login-* en <style> más abajo, clonados 1:1 de
// vialtec-flota-v2/src/views/LoginView.vue). Por eso el botón de acá NO usa
// VButton (excepción deliberada a la convención de components/shared: es una
// réplica pixel a pixel de un estilo que tampoco usa un componente
// compartido en el sistema de origen). Distinción mínima entre los dos
// sistemas: el título debajo del logo ("Plantas" acá, "Gestión de Flota" en
// el otro) — se deja afuera a propósito el acceso mobile por PIN de Flota
// (el separador "o" + botón "Acceso operadores/despachantes"): ese login
// alternativo no existe en Plantas, solo hay login por email.
//
// "¿Olvidaste tu contraseña?" es funcionalidad nueva acá (no existía en este
// sistema) — mismo flujo ya probado en producción en Flota:
// resetPasswordForEmail()/updateUser() vía auth.store.js, evento
// PASSWORD_RECOVERY escuchado en auth.store.js#escucharCambiosAuth().

import { ref, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth.store'
import { esPantallaMobile } from '@/composables/useBreakpoint'
import logoVialtec from '@/assets/img/logo-vialtec.png'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

const modo = ref('login') // 'login' | 'olvide' | 'recovery'
const error = ref(null)

const email = ref('')
const password = ref('')
const enviando = ref(false)

async function enviar() {
  error.value = null
  enviando.value = true
  try {
    await auth.login(email.value.trim(), password.value)
    // Ruta de aterrizaje: respeta un ?redirect= explícito (deep link) por
    // sobre todo; si no hay, en mobile prioriza Pedidos sobre Home
    // (2026-09-16, ver auth.store.js#rutaInicioSesion).
    router.replace(route.query.redirect || { name: auth.rutaInicioSesion(esPantallaMobile()) })
  } catch (e) {
    error.value = e.message
  } finally {
    enviando.value = false
  }
}

// "¿Olvidaste tu contraseña?" — modo aparte, mismo patrón de máquina de
// estados que usa vialtec-flota-v2/LoginView.vue.
const emailOlvide = ref('')
const enviandoRecovery = ref(false)
const recoveryEnviado = ref(false)

function abrirOlvidePassword() {
  error.value = null
  recoveryEnviado.value = false
  emailOlvide.value = email.value.trim()
  modo.value = 'olvide'
}

function volverAlLogin() {
  error.value = null
  modo.value = 'login'
}

async function enviarRecovery() {
  if (!emailOlvide.value.trim()) {
    error.value = 'Ingresá tu email.'
    return
  }
  error.value = null
  enviandoRecovery.value = true
  try {
    await auth.enviarRecoveryEmail(emailOlvide.value.trim())
    recoveryEnviado.value = true
  } catch (e) {
    error.value = e.message
  } finally {
    enviandoRecovery.value = false
  }
}

// Password recovery real — se activa vía auth.isPasswordRecovery (evento
// PASSWORD_RECOVERY de Supabase, ver auth.store.js). watch en vez de un
// chequeo one-shot en el montaje: el SDK procesa el token del link de forma
// asíncrona, puede setearse un instante después de que esta vista ya montó.
const nuevaPassword = ref('')
const confirmarPassword = ref('')
const guardandoPassword = ref(false)

watch(
  () => auth.isPasswordRecovery,
  (esRecovery) => {
    if (esRecovery) {
      error.value = null
      modo.value = 'recovery'
    }
  },
  { immediate: true }
)

async function confirmarNuevaPassword() {
  if (!nuevaPassword.value || nuevaPassword.value.length < 6) {
    error.value = 'La contraseña tiene que tener al menos 6 caracteres.'
    return
  }
  if (nuevaPassword.value !== confirmarPassword.value) {
    error.value = 'Las contraseñas no coinciden.'
    return
  }
  error.value = null
  guardandoPassword.value = true
  try {
    await auth.completarRecoveryPassword(nuevaPassword.value)
    router.replace(route.query.redirect || { name: auth.rutaInicioSesion(esPantallaMobile()) })
  } catch (e) {
    error.value = e.message
    // completarRecoveryPassword() ya reseteó el store si la sesión temporal del link
    // expiró o falló resolver el perfil — volver al login normal en vez de dejarlo
    // trabado repitiendo el mismo error contra una sesión muerta.
    if (!auth.estaLogueado) modo.value = 'login'
  } finally {
    guardandoPassword.value = false
  }
}
</script>

<template>
  <div class="login-bg relative flex min-h-screen items-center justify-center overflow-hidden px-4">
    <div class="login-glow pointer-events-none absolute inset-x-0 top-0 h-[480px]" />

    <form v-if="modo === 'login'" class="login-card relative w-full max-w-sm space-y-6 rounded-[20px] p-8" @submit.prevent="enviar">
      <div class="flex flex-col items-center gap-3 text-center">
        <img :src="logoVialtec" alt="VIAL-TEC S.A." class="h-16 w-auto" />
        <h1 class="text-lg font-bold text-text">Plantas</h1>
        <!-- 2026-09-08 (pedido de Federico: "algo distintivo, lindo y
             profesional"): badge con un ícono propio (silos + cinta de
             asfalto, dibujado a mano en SVG, sin librería externa) en vez de
             un emoji — mismo criterio de sobriedad que el resto del sistema.
             Es la única pieza nueva de esta pantalla: el resto de la card es
             la réplica exacta del login de Flota (ver <style> más abajo). -->
        <span class="login-badge inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-xs font-semibold text-vialtec">
          <svg viewBox="0 0 24 24" fill="none" class="h-3.5 w-3.5 shrink-0">
            <path d="M4 21V9.5L8 7v3l4-2.5V10l4-2.5V21" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" />
            <path d="M2.5 21h19" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" />
            <path d="M4 21v-3M8 21v-3M12 21v-3M16 21v-3" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-dasharray="1.6 2.2" />
          </svg>
          Producción de Asfalto y Hormigón
        </span>
      </div>

      <div v-if="error" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <div>
        <label class="mb-1 block text-sm font-medium text-text-mid">Email</label>
        <input
          v-model="email"
          type="email"
          required
          autocomplete="username"
          class="login-input w-full rounded-lg px-3 py-2 text-sm text-text focus:outline-none"
        />
      </div>

      <div>
        <label class="mb-1 block text-sm font-medium text-text-mid">Contraseña</label>
        <input
          v-model="password"
          type="password"
          required
          autocomplete="current-password"
          class="login-input w-full rounded-lg px-3 py-2 text-sm text-text focus:outline-none"
        />
      </div>

      <button type="submit" class="login-btn w-full rounded-lg px-4 py-2 text-sm font-semibold text-white disabled:opacity-50" :disabled="enviando">
        {{ enviando ? 'Ingresando…' : 'Ingresar' }}
      </button>

      <button type="button" class="w-full text-center text-xs font-medium text-vialtec hover:underline" @click="abrirOlvidePassword">
        ¿Olvidaste tu contraseña?
      </button>
    </form>

    <form v-else-if="modo === 'olvide'" class="login-card relative w-full max-w-sm space-y-6 rounded-[20px] p-8" @submit.prevent="enviarRecovery">
      <div class="flex flex-col items-center gap-3 text-center">
        <img :src="logoVialtec" alt="VIAL-TEC S.A." class="h-16 w-auto" />
        <div>
          <h1 class="text-lg font-bold text-text">Restablecer contraseña</h1>
          <p class="mt-1 text-xs text-text-soft">Ingresá tu email y te mandamos un link para elegir una nueva.</p>
        </div>
      </div>

      <div v-if="error" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>
      <div v-if="recoveryEnviado" class="rounded-lg border border-success/20 bg-success-light px-3 py-2 text-sm text-success">
        Te enviamos un link a {{ emailOlvide }} para restablecer tu contraseña.
      </div>

      <div>
        <label class="mb-1 block text-sm font-medium text-text-mid">Email</label>
        <input
          v-model="emailOlvide"
          type="email"
          autocomplete="username"
          class="login-input w-full rounded-lg px-3 py-2 text-sm text-text focus:outline-none"
        />
      </div>

      <button
        type="submit"
        class="login-btn w-full rounded-lg px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
        :disabled="enviandoRecovery"
      >
        {{ enviandoRecovery ? 'Enviando…' : 'Enviar link' }}
      </button>

      <button type="button" class="w-full text-center text-xs font-medium text-vialtec hover:underline" @click="volverAlLogin">
        ← Volver al login
      </button>
    </form>

    <form v-else class="login-card relative w-full max-w-sm space-y-6 rounded-[20px] p-8" @submit.prevent="confirmarNuevaPassword">
      <div class="flex flex-col items-center gap-3 text-center">
        <img :src="logoVialtec" alt="VIAL-TEC S.A." class="h-16 w-auto" />
        <div>
          <h1 class="text-lg font-bold text-text">Crear nueva contraseña</h1>
          <p class="mt-1 text-xs text-text-soft">Elegí una contraseña nueva para tu cuenta.</p>
        </div>
      </div>

      <div v-if="error" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <div>
        <label class="mb-1 block text-sm font-medium text-text-mid">Nueva contraseña</label>
        <input
          v-model="nuevaPassword"
          type="password"
          autocomplete="new-password"
          class="login-input w-full rounded-lg px-3 py-2 text-sm text-text focus:outline-none"
        />
      </div>

      <div>
        <label class="mb-1 block text-sm font-medium text-text-mid">Confirmar contraseña</label>
        <input
          v-model="confirmarPassword"
          type="password"
          autocomplete="new-password"
          class="login-input w-full rounded-lg px-3 py-2 text-sm text-text focus:outline-none"
        />
      </div>

      <button
        type="submit"
        class="login-btn w-full rounded-lg px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
        :disabled="guardandoPassword"
      >
        {{ guardandoPassword ? 'Guardando…' : 'Guardar contraseña' }}
      </button>
    </form>
  </div>
</template>

<style scoped>
/* Clonado 1:1 de vialtec-flota-v2/src/views/LoginView.vue (2026-09-08, pedido
   explícito de Federico de replicar esa pantalla acá) — mismos tokens de
   marca que ya usa el resto de este sistema (tailwind.config.js: vialtec
   #7B2F8E, border #EAECF0, text #101828/#344054/#667085), así que el
   violeta no es "prestado" de Flota, es el mismo acento de marca de los dos
   sistemas. */
.login-bg {
  background-color: #f9fafb;
  background-image:
    linear-gradient(rgba(123, 47, 142, 0.06) 1px, transparent 1px),
    linear-gradient(90deg, rgba(123, 47, 142, 0.06) 1px, transparent 1px);
  background-size: 48px 48px;
}

.login-glow {
  background: radial-gradient(ellipse at 50% 0%, rgba(123, 47, 142, 0.1), transparent 70%);
}

.login-card {
  background: #ffffff;
  border: 1px solid #eaecf0;
  box-shadow: 0 4px 24px rgba(16, 24, 40, 0.08);
  animation: fadeUp 0.6s ease 0.1s both;
}

.login-badge {
  background: rgba(123, 47, 142, 0.08);
  border: 1px solid rgba(123, 47, 142, 0.18);
}

.login-input {
  background: #ffffff;
  border: 1px solid #eaecf0;
  transition: border-color 0.15s;
}

.login-input:focus {
  border-color: #7b2f8e;
}

.login-btn {
  background: #7b2f8e;
  box-shadow: 0 4px 14px rgba(123, 47, 142, 0.3);
  transition: opacity 0.15s;
}

.login-btn:hover:not(:disabled) {
  opacity: 0.9;
}

@keyframes fadeUp {
  from {
    opacity: 0;
    transform: translateY(18px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
</style>
