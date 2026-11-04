<script setup>
// Aviso "Tu sesión venció" (2026-11-04, pedido de Federico). Se muestra
// arriba de la pantalla en la que estaba el usuario — no se redirige solo,
// así ve el aviso antes de perder la pantalla. "Volver a entrar" lleva al
// login y, al entrar, vuelve a la misma pantalla (?redirect=).
// Lo que estaba cargando: auth.store.js#marcarSesionVencida (borradores-sesion.js).
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth.store'

const auth = useAuthStore()
const router = useRouter()

function volverAEntrar() {
  const ruta = auth.cerrarPorVencimiento()
  router.replace({ name: 'login', query: ruta && ruta !== '/login' ? { redirect: ruta } : {} })
}
</script>

<template>
  <div
    v-if="auth.sesionVencida"
    class="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 p-4"
    role="alertdialog"
    aria-modal="true"
    aria-labelledby="sesion-vencida-titulo"
  >
    <div class="w-full max-w-sm rounded-xl bg-white p-6 shadow-xl">
      <h3 id="sesion-vencida-titulo" class="text-lg font-bold text-text">Tu sesión venció</h3>
      <p class="mt-2 text-sm text-text-mid">Volvé a entrar. Te llevamos de nuevo a esta pantalla.</p>
      <p v-if="auth.borradoresGuardados.length" class="mt-3 rounded-lg bg-success-light px-3 py-2 text-sm text-success">
        Guardamos {{ auth.borradoresGuardados.join(' y ') }}: lo vas a encontrar al volver.
      </p>
      <p v-if="auth.borradoresPerdidos.length" class="mt-3 rounded-lg bg-danger-light px-3 py-2 text-sm text-danger">
        No se guardó {{ auth.borradoresPerdidos.join(' ni ') }}: revisalo al volver y cargalo de nuevo si hace falta.
      </p>
      <button
        type="button"
        class="mt-5 w-full rounded-lg bg-vialtec px-4 py-2.5 text-sm font-semibold text-white transition-opacity duration-150 hover:opacity-90"
        @click="volverAEntrar"
      >
        Volver a entrar
      </button>
    </div>
  </div>
</template>
