<script setup>
// Modal "Registrar despacho" de asfalto (circuito báscula): multi-camión con
// N° de vale por carga, cierre parcial y pedido residual. Template puro:
// el estado y el guardado viven en useDespachoAsfalto.js, que recibe la
// vista que lo abre. Extraído de PedidosView.vue (2026-10-22) para que
// Pedidos y Plan semanal despachen con el mismo modal y el mismo circuito.
import VModal from '@/components/shared/VModal.vue'
import VButton from '@/components/shared/VButton.vue'
import { formatearCantidad, formatearCantidadHasta } from '@/services/formato-numeros'

defineProps({
  // Instancia de useDespachoAsfalto() (reactive) de la vista.
  despacho: { type: Object, required: true },
  // Obra o cliente del pedido, ya resuelto por la vista.
  destino: { type: String, default: '' },
  patentes: { type: Array, default: () => [] },
})
</script>

<template>
  <VModal :open="despacho.abierto" title="Registrar despacho" @update:open="despacho.abierto = $event">
    <div class="space-y-3">
      <div v-if="despacho.error" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ despacho.error }}
      </div>
      <p class="text-sm text-text-mid">
        {{ destino }}
        — Solicitado: {{ formatearCantidadHasta(despacho.pedido?.cantidad_solicitada) }} tn · Saldo antes de este despacho: {{ formatearCantidad(despacho.saldoPendiente, 1) }} tn
      </p>

      <div class="space-y-2">
        <p class="text-xs font-semibold uppercase tracking-wide text-text-soft">Cargas / camiones</p>
        <div
          v-for="(carga, idx) in despacho.cargas"
          :key="idx"
          class="grid grid-cols-1 items-end gap-2 rounded-lg border border-border p-2 md:grid-cols-[1fr_1fr_1fr_auto]"
        >
          <label class="text-xs text-text-mid">
            Cantidad (tn) *
            <input
              v-model.number="carga.cantidad_tn"
              type="number"
              step="0.01"
              class="mt-1 w-full rounded-lg border border-border px-2 py-1.5 text-sm focus:border-vialtec focus:outline-none"
            />
          </label>
          <label class="text-xs text-text-mid">
            N° vale *
            <input
              v-model="carga.numero_vale"
              type="text"
              class="mt-1 w-full rounded-lg border border-border px-2 py-1.5 text-sm focus:border-vialtec focus:outline-none"
            />
          </label>
          <label class="text-xs text-text-mid">
            Patente (opcional)
            <input
              v-model="carga.patente"
              list="patentes-despacho"
              class="mt-1 w-full rounded-lg border border-border px-2 py-1.5 text-sm focus:border-vialtec focus:outline-none"
            />
          </label>
          <VButton
            type="button"
            variant="ghost"
            size="sm"
            :disabled="despacho.cargas.length <= 1"
            @click="despacho.quitarCarga(idx)"
          >
            ✕ Quitar carga
          </VButton>
        </div>
        <VButton type="button" variant="secondary" size="sm" @click="despacho.agregarCarga">+ Agregar carga</VButton>
      </div>

      <p class="text-sm font-semibold text-text">Total: {{ formatearCantidad(despacho.totalCargas, 2) }} tn</p>
      <!-- N° de remito: se origina en Báscula, no acá (migración 39,
           2026-09-16) — el balancero lo asigna e imprime en la primera
           pesada del pedido, el plantista lo recibe ya en papel. Esta
           línea es solo de lectura/confirmación contra ese papel. -->
      <p class="text-sm text-text-mid">
        N° de remito:
        <span v-if="despacho.pedido?.nro_remito_global" class="font-semibold text-text">
          {{ despacho.pedido.nro_remito_global }}
        </span>
        <span v-else class="text-warning">
          todavía sin asignar — falta procesar la primera pesada en Báscula
        </span>
      </p>

      <!-- Cierre parcial + pedido residual (Logica sis. plantas v1.rtf §2.2) -->
      <div v-if="despacho.residualEstimado > 0" class="rounded-lg border border-warning/30 bg-warning-light/40 p-3">
        <p class="text-sm text-text-mid">
          Con estas cargas queda un saldo de <strong>{{ formatearCantidad(despacho.residualEstimado, 2) }} tn</strong> sin despachar.
          El pedido se va a cerrar como <strong>despachado</strong> igual, con lo cargado.
        </p>
        <label class="mt-2 flex items-center gap-2 text-sm text-text-mid">
          <input v-model="despacho.dividirPedido" type="checkbox" />
          Dividir pedido: crear un pedido nuevo confirmado por el saldo
        </label>
        <label v-if="despacho.dividirPedido" class="mt-2 block text-sm text-text-mid">
          Fecha del pedido residual
          <input
            v-model="despacho.fechaResidual"
            type="date"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none md:w-1/2"
          />
        </label>
      </div>

      <datalist id="patentes-despacho">
        <option v-for="p in patentes" :key="p.id" :value="p.patente" />
      </datalist>

      <div class="flex justify-end gap-2 pt-2">
        <VButton type="button" variant="secondary" @click="despacho.abierto = false">Cancelar</VButton>
        <VButton type="button" variant="success" :disabled="despacho.guardando" @click="despacho.guardar">
          {{ despacho.guardando ? 'Guardando…' : 'Confirmar despacho' }}
        </VButton>
      </div>
    </div>
  </VModal>
</template>
