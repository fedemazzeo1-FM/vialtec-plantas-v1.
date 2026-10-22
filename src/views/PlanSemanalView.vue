<script setup>
// Plan Semanal: matriz lunes-domingo de pedidos + KPIs de acumulado semanal
// por tipo de producto. Template puro: la lógica vive en usePlanSemanal.js
// (2026-10-22, extraída de esta vista al sumar "Despachar" desde el
// calendario). Los modales de despacho son los mismos de Pedidos.

import VCard from '@/components/shared/VCard.vue'
import VKpiCard from '@/components/shared/VKpiCard.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VSection from '@/components/shared/VSection.vue'
import VButton from '@/components/shared/VButton.vue'
import ModalDespachoAsfalto from '@/modules/pedidos/components/ModalDespachoAsfalto.vue'
import ModalDespachoMixer from '@/modules/pedidos/components/ModalDespachoMixer.vue'
import { usePlanSemanal } from '@/modules/plan-semanal/composables/usePlanSemanal'
import { usePermisosPedido } from '@/modules/pedidos/composables/usePermisosPedido'
import { tiposConTotalVisible, unidadLabelTipoProducto } from '@/config/tipos-producto'
import { useBreakpoint } from '@/composables/useBreakpoint'
import { formatearCantidad, formatearCantidadHasta } from '@/services/formato-numeros'

const { esMobile } = useBreakpoint()

// Mismos permisos de UI que Pedidos (usePermisosPedido.js): evita mostrar
// un botón que la RPC del servidor va a rechazar igual. "Confirmar" y
// "Despachar" se gatean igual en la grilla de Desktop y en la franja mobile
// (2026-10-22: antes "Confirmar" de Desktop se mostraba a todos los roles).
const { puedeConfirmar, puedeDespachar } = usePermisosPedido()

const {
  totales,
  patentes,
  cargando,
  error,
  formulasPorId,
  nombreDestinoPedido,
  nombreDestinoTotal,
  diasSemana,
  rangoLabel,
  diaSeleccionadoIso,
  diaSeleccionado,
  cargarSemana,
  semanaAnterior,
  semanaSiguiente,
  irAHoySemana,
  confirmar,
  despacho,
  cargaHormigon,
  abrirDespacho,
} = usePlanSemanal()

const VARIANTE_ESTADO = {
  solicitado: 'default',
  confirmado: 'info',
  despachado: 'success',
  cancelado: 'danger',
}

/** Los pedidos no tienen hora de entrega propia (solo `fecha_programada`,
 * columna date) — se muestra la hora de creación como referencia, mismo
 * dato que ya expone PedidoCard.vue con el ícono 🕐. */
function formatearHoraCreacion(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' })
}

cargarSemana()
</script>

<template>
  <div>
    <VSection title="Plan semanal">
      <!-- Nav de semana — versión completa en Desktop. En mobile queda una
           versión compacta (‹ / Hoy / ›) dentro de la franja de abajo, no
           hace falta duplicar el rango de fechas ahí (los propios chips de
           día ya muestran número + mes). -->
      <div v-if="!esMobile" class="mb-4 flex items-center justify-between">
        <VButton variant="ghost" size="sm" @click="semanaAnterior">‹ Semana anterior</VButton>
        <p class="text-sm font-semibold text-text">{{ rangoLabel }}</p>
        <VButton variant="ghost" size="sm" @click="semanaSiguiente">Semana siguiente ›</VButton>
      </div>

      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <!-- Totalizadores tn/m³ — ocultos en mobile (rediseño Mobile-First
           2026-09-22, mismo criterio que Pedidos: en campo importa "qué
           tengo hoy", no el acumulado semanal). Sin cambios en Desktop. -->
      <template v-if="!esMobile">
        <VCard class="mb-4">
          <p class="mb-2 text-sm font-semibold text-text-soft">Total semana — todas las obras</p>
          <div class="grid gap-3" :class="tiposConTotalVisible(totales.total).length > 2 ? 'grid-cols-3' : 'grid-cols-2'">
            <VKpiCard
              v-for="tipo in tiposConTotalVisible(totales.total)"
              :key="tipo.id"
              :label="tipo.nombre"
              :value="formatearCantidad(totales.total[tipo.total], 1)"
              :unidad="tipo.unidadLabel"
            />
          </div>
        </VCard>

        <div v-if="totales.porObra.length" class="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <VCard v-for="t in totales.porObra" :key="t.obraId ?? t.clienteExterno">
            <p class="mb-2 text-sm font-semibold text-text-soft">{{ nombreDestinoTotal(t) }}</p>
            <div class="grid grid-cols-2 gap-3">
              <VKpiCard
                v-for="tipo in tiposConTotalVisible(t)"
                :key="tipo.id"
                :label="tipo.nombre"
                :value="formatearCantidad(t[tipo.total], 1)"
                :unidad="tipo.unidadLabel"
              />
            </div>
          </VCard>
        </div>
      </template>

      <p v-if="cargando" class="text-sm text-text-soft">Cargando…</p>

      <!-- Mobile (<768px, rediseño Mobile-First 2026-09-22): franja
           horizontal táctil de los 7 días + detalle del día seleccionado
           debajo, en vez del scroll vertical continuo de antes. -->
      <template v-else-if="esMobile">
        <div class="mb-3 flex items-center justify-between gap-2">
          <VButton variant="ghost" size="sm" @click="semanaAnterior">‹</VButton>
          <VButton variant="secondary" size="sm" @click="irAHoySemana">Hoy</VButton>
          <VButton variant="ghost" size="sm" @click="semanaSiguiente">›</VButton>
        </div>

        <div class="mb-4 flex gap-2 overflow-x-auto pb-1" style="scroll-snap-type: x proximity">
          <button
            v-for="dia in diasSemana"
            :key="dia.iso"
            type="button"
            class="flex shrink-0 flex-col items-center gap-1 rounded-xl border px-3 py-2"
            style="min-width: 56px; scroll-snap-align: start"
            :class="dia.iso === diaSeleccionadoIso ? 'border-vialtec bg-vialtec/5' : 'border-border bg-white'"
            @click="diaSeleccionadoIso = dia.iso"
          >
            <span
              class="text-[10px] font-semibold uppercase tracking-wide"
              :class="dia.iso === diaSeleccionadoIso ? 'text-vialtec' : 'text-text-soft'"
            >
              {{ dia.etiquetaCorta }}
            </span>
            <span
              class="flex h-8 w-8 items-center justify-center rounded-full text-sm font-bold"
              :class="[
                dia.iso === diaSeleccionadoIso ? 'bg-vialtec text-white' : 'text-text-mid',
                dia.esHoy && dia.iso !== diaSeleccionadoIso ? 'ring-1 ring-vialtec' : '',
              ]"
            >
              {{ dia.numeroDia }}
            </span>
            <!-- Punto indicador: hay pedidos ese día (2026-09-22, pedido de Federico). -->
            <span class="h-1.5 w-1.5 rounded-full" :class="dia.pedidos.length ? 'bg-vialtec' : 'bg-transparent'" />
          </button>
        </div>

        <div v-if="diaSeleccionado" class="mb-3 flex items-baseline justify-between">
          <p class="text-sm font-bold text-text">{{ diaSeleccionado.etiqueta }} {{ diaSeleccionado.numeroDia }} de {{ diaSeleccionado.mesLabel }}</p>
          <span class="text-xs text-text-soft">
            {{ diaSeleccionado.pedidos.length }} {{ diaSeleccionado.pedidos.length === 1 ? 'pedido' : 'pedidos' }}
          </span>
        </div>

        <div class="space-y-3">
          <p
            v-if="diaSeleccionado && !diaSeleccionado.pedidos.length"
            class="rounded-xl border border-dashed border-border py-6 text-center text-sm text-text-soft"
          >
            Sin pedidos para este día.
          </p>
          <div
            v-for="p in diaSeleccionado?.pedidos ?? []"
            :key="p.id"
            class="rounded-xl border border-border bg-white p-3 shadow-sm"
          >
            <div class="flex items-start justify-between gap-2">
              <div class="min-w-0">
                <p class="truncate text-sm font-bold text-text">{{ nombreDestinoPedido(p) }}</p>
                <p class="text-xs text-text-soft">
                  {{ formulasPorId[p.formula_id]?.nombre ?? '—' }} ·
                  <span class="font-semibold text-vialtec">{{ formatearCantidadHasta(p.cantidad_solicitada) }} {{ unidadLabelTipoProducto(p.tipo) }}</span>
                </p>
              </div>
              <VBadge :variant="VARIANTE_ESTADO[p.estado]">{{ p.estado }}</VBadge>
            </div>
            <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-text-soft">
              <span v-if="p.encargado">👤 {{ p.encargado }}</span>
              <span>🕐 {{ formatearHoraCreacion(p.created_at) }}</span>
            </div>
            <div v-if="p.estado === 'solicitado' && puedeConfirmar" class="mt-2 flex justify-end">
              <VButton size="sm" @click="confirmar(p)">Confirmar</VButton>
            </div>
            <div v-else-if="puedeDespachar(p)" class="mt-2 flex justify-end">
              <VButton variant="success" size="sm" @click="abrirDespacho(p)">↑ Despachar</VButton>
            </div>
          </div>
        </div>
      </template>

      <!-- Desktop (>=768px): matriz lunes a domingo sin cambios — grilla de
           calendario real (una sola grilla con separadores internos, no 7
           cards sueltas), día actual resaltado, fin de semana con fondo
           levemente distinto. -->
      <div v-else class="overflow-hidden rounded-xl border border-border">
        <div class="grid grid-cols-1 divide-y divide-border md:grid-cols-7 md:divide-x md:divide-y-0">
          <div
            v-for="dia in diasSemana"
            :key="dia.iso"
            class="flex flex-col"
            :class="dia.esFinDeSemana && !dia.esHoy ? 'bg-panel' : ''"
          >
            <div
              class="flex items-baseline justify-between gap-2 border-b px-3 py-2"
              :class="dia.esHoy ? 'border-vialtec/30 bg-vialtec/5' : 'border-border'"
            >
              <p
                class="text-xs font-bold uppercase tracking-wide"
                :class="dia.esHoy ? 'text-vialtec' : 'text-text-soft'"
              >
                {{ dia.etiquetaCorta }}
              </p>
              <p class="flex items-center gap-1 text-xs">
                <span
                  class="flex h-5 w-5 items-center justify-center rounded-full text-[11px] font-bold"
                  :class="dia.esHoy ? 'bg-vialtec text-white' : 'text-text-mid'"
                >
                  {{ dia.numeroDia }}
                </span>
                <span class="text-text-soft">{{ dia.mesLabel }}</span>
              </p>
            </div>

            <!-- Tilde + cantidades cuando el día cerró 100% despachado
                 (2026-09-03, réplica exacta del legado pedida por Federico —
                 pill violeta debajo de la fecha, "N peds ✓ X tn · Y m³"). -->
            <div v-if="dia.todosDespachados" class="px-2 pt-2">
              <p class="rounded-full bg-vialtec/10 px-2.5 py-1 text-center text-[11px] font-semibold text-vialtec">
                {{ dia.pedidos.length }} {{ dia.pedidos.length === 1 ? 'ped.' : 'peds' }}
                ✓
                {{ dia.totalesDiaLabels.join(' · ') }}
              </p>
            </div>

            <div class="min-h-[88px] flex-1 space-y-2 p-2">
              <p v-if="!dia.pedidos.length" class="px-1 py-2 text-center text-xs text-text-soft/70">Sin pedidos</p>
              <div
                v-for="p in dia.pedidos"
                :key="p.id"
                class="rounded-lg border border-border bg-white p-2 text-xs shadow-sm transition-shadow duration-150 hover:shadow"
              >
                <p class="truncate font-semibold text-text" :title="nombreDestinoPedido(p)">{{ nombreDestinoPedido(p) }}</p>
                <p class="truncate text-text-soft">
                  {{ formulasPorId[p.formula_id]?.nombre ?? '—' }} ·
                  {{ formatearCantidadHasta(p.cantidad_solicitada) }} {{ unidadLabelTipoProducto(p.tipo) }}
                </p>
                <div class="mt-1.5 flex flex-wrap items-center justify-between gap-1">
                  <VBadge :variant="VARIANTE_ESTADO[p.estado]">{{ p.estado }}</VBadge>
                  <VButton v-if="p.estado === 'solicitado' && puedeConfirmar" variant="ghost" size="sm" @click="confirmar(p)">
                    Confirmar
                  </VButton>
                  <VButton v-else-if="puedeDespachar(p)" variant="success" size="sm" @click="abrirDespacho(p)">
                    ↑ Despachar
                  </VButton>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </VSection>

    <!-- Despacho: los mismos modales y el mismo circuito que Pedidos -->
    <ModalDespachoAsfalto :despacho="despacho" :destino="nombreDestinoPedido(despacho.pedido)" :patentes="patentes" />
    <ModalDespachoMixer :despacho="cargaHormigon" :destino="nombreDestinoPedido(cargaHormigon.pedido)" :patentes="patentes" />
  </div>
</template>
