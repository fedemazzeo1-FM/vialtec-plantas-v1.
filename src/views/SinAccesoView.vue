<script setup>
// Login único VT360 (sesión Portal, 2026-11-18): la persona tiene sesión (es la misma cuenta de
// Flota y Obras) pero no tiene acceso a Plantas. No se cierra la sesión: se explica y se ofrece
// volver al portal o entrar con otra cuenta.
import { computed, ref } from 'vue'
import { useAuthStore } from '@/stores/auth.store'
import { appConfig } from '@/config/app.config'
import logoVialtec from '@/assets/img/logo-vialtec.png'

const auth = useAuthStore()
const saliendo = ref(false)

const motivo = computed(() => auth.sinAcceso?.motivo ?? 'sin_ficha')
const email = computed(() => auth.sinAcceso?.email ?? null)

const textos = {
  sin_ficha: {
    titulo: 'No tenés acceso a este sistema',
    detalle: 'Tu cuenta no está habilitada en Plantas. Si lo necesitás, pedíselo a un administrador.',
  },
  suspendido: {
    titulo: 'No tenés acceso a este sistema',
    detalle: 'Tu usuario está inactivo en Plantas. Contactá a un administrador.',
  },
  error: {
    titulo: 'No pudimos verificar tu acceso',
    detalle: 'Revisá la conexión y probá de nuevo.',
  },
}
const texto = computed(() => textos[motivo.value] ?? textos.sin_ficha)

function reintentar() {
  window.location.reload()
}

async function entrarConOtraCuenta() {
  saliendo.value = true
  try {
    await auth.salirDeEstaCuenta()
  } finally {
    saliendo.value = false
  }
}
</script>

<template>
  <div class="flex min-h-screen items-center justify-center bg-gray-50 px-4">
    <div class="w-full max-w-sm space-y-6 rounded-[20px] border border-border bg-white p-8 text-center shadow-sm">
      <img :src="logoVialtec" alt="VIAL-TEC S.A." class="mx-auto h-14 w-auto" />
      <div class="space-y-2">
        <h1 class="text-lg font-bold text-text">{{ texto.titulo }}</h1>
        <p class="text-sm text-text-mid">{{ texto.detalle }}</p>
        <p v-if="email" class="text-xs text-text-soft">Cuenta: {{ email }}</p>
      </div>
      <div class="space-y-3">
        <button
          v-if="motivo === 'error'"
          type="button"
          class="w-full rounded-lg bg-vialtec px-4 py-2 text-sm font-semibold text-white hover:opacity-90"
          style="min-height: 44px"
          @click="reintentar"
        >
          Probar de nuevo
        </button>
        <a
          v-if="appConfig.portalUrl"
          :href="appConfig.portalUrl"
          class="inline-flex w-full items-center justify-center rounded-lg px-4 py-2 text-sm font-semibold"
          :class="motivo === 'error' ? 'border border-border text-text-mid hover:bg-gray-50' : 'bg-vialtec text-white hover:opacity-90'"
          style="min-height: 44px"
        >
          Volver al portal VT360
        </a>
        <button
          type="button"
          class="w-full disabled:opacity-50"
          :class="appConfig.portalUrl || motivo === 'error'
            ? 'text-center text-xs font-medium text-vialtec hover:underline'
            : 'rounded-lg bg-vialtec px-4 py-2 text-sm font-semibold text-white hover:opacity-90'"
          :style="appConfig.portalUrl || motivo === 'error' ? '' : 'min-height: 44px'"
          :disabled="saliendo"
          @click="entrarConOtraCuenta"
        >
          Entrar con otra cuenta
        </button>
      </div>
    </div>
  </div>
</template>
