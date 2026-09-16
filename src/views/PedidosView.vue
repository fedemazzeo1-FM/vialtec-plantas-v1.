<script setup>
// Vista de Pedidos: historial completo con filtros, alta y cambios de estado.
// Toda la lógica de negocio vive en composables (memory/conventions.md: esta
// vista es template puro, sin acceso a Supabase ni reglas de negocio):
//   - usePedidos            listado/filtros/paginación, alta, editar,
//                           confirmar, postergar, cancelar, archivar,
//                           historial, toasts de WhatsApp.
//   - useDespachoAsfalto    modal "Registrar despacho" (multi-camión, vale
//                           por carga, cierre parcial + residual).
//   - useCargaHormigon      modal "Registrar despacho" de hormigón (mismo
//                           patrón multi-carga, remito por mixer).

import VCard from '@/components/shared/VCard.vue'
import VModal from '@/components/shared/VModal.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VSection from '@/components/shared/VSection.vue'
import VButton from '@/components/shared/VButton.vue'
import VKpiCard from '@/components/shared/VKpiCard.vue'
import { usePedidos } from '@/modules/pedidos/composables/usePedidos'
import { useDespachoAsfalto } from '@/modules/pedidos/composables/useDespachoAsfalto'
import { useCargaHormigon } from '@/modules/pedidos/composables/useCargaHormigon'
import PedidoCard from '@/modules/pedidos/components/PedidoCard.vue'
import { ESTADOS, VARIANTE_ESTADO, COLOR_KPI_ESTADO } from '@/modules/pedidos/estados'
import { useBreakpoint } from '@/composables/useBreakpoint'
import { useAuthStore } from '@/stores/auth.store'
import { computed } from 'vue'

const { esMobile } = useBreakpoint()
const auth = useAuthStore()

// RBAC (2026-09-16, pedido de Federico): Confirmar/Despachar solo para
// plantista/admin — "pedidos.aprobar" en la matriz hoy resuelve exactamente
// a ese par de roles (admin por bypass total). Despachar difiere por tipo
// porque las RPC detrás (registrar_carga_asfalto/registrar_carga_hormigon)
// hardcodean roles distintos, no pasan por la matriz: asfalto queda
// admin/plantista únicamente, hormigón además admite plantista_hormigon
// (rol que existe específicamente para despachar hormigón — no se le puede
// sacar esa única acción sin romper su función real). Ver esos 2 archivos
// de migración si esto cambia algún día.
const puedeConfirmar = computed(() => auth.tienePermiso('pedidos', 'aprobar'))
const puedeDespacharAsfalto = computed(() => auth.rol === 'admin' || auth.rol === 'plantista')
const puedeDespacharHormigon = computed(
  () => auth.rol === 'admin' || auth.rol === 'plantista' || auth.rol === 'plantista_hormigon'
)

const {
  error,
  obras,
  formulas,
  patentes,
  clientes,
  cargando,
  filtros,
  conteoEstados,
  totalesPeriodo,
  pedidosPorTipo,
  aplicarFiltros,
  limpiarFiltros,
  cargarPedidos,
  vistaSemana,
  rangoSemanaLabel,
  irASemanaActual,
  verHistoricoCompleto,
  whatsappToasts,
  descartarToastWhatsapp,
  modalNuevoAbierto,
  guardandoNuevo,
  formNuevo,
  abrirNuevo,
  alSeleccionarFormula,
  guardarNuevo,
  modalEditarAbierto,
  guardandoEditar,
  formEditar,
  abrirEdicion,
  alSeleccionarFormulaEditar,
  guardarEdicion,
  confirmar,
  modalPostergarAbierto,
  pedidoPostergar,
  fechaNuevaPostergar,
  motivoPostergar,
  postergando,
  abrirPostergacion,
  confirmarPostergacion,
  modalCancelAbierto,
  pedidoCancelar,
  motivoCancelacion,
  cancelando,
  errorCancelacion,
  abrirCancelacion,
  confirmarCancelacion,
  archivar,
  modalHistorialAbierto,
  pedidoHistorial,
  eventosHistorial,
  cargandoHistorial,
  abrirHistorial,
  iniciar,
} = usePedidos()

const despacho = useDespachoAsfalto(cargarPedidos)
const cargaHormigon = useCargaHormigon(cargarPedidos)

/**
 * KPI de estado como filtro rápido (2026-09-02, roadmap Mobile/UX): click
 * en la card aplica ese estado al mismo filtro que ya existía en el
 * <select> de abajo; click de nuevo sobre la card activa lo saca (toggle).
 */
function filtrarPorEstado(estado) {
  filtros.estado = filtros.estado === estado ? '' : estado
  aplicarFiltros()
}

iniciar()
</script>

<template>
  <div>
    <!-- Toasts de WhatsApp (WppToast del legado): nunca se envía por API, se -->
    <!-- sugiere el mensaje + un link a wa.me que el usuario dispara a mano. -->
    <div v-if="whatsappToasts.length" class="mb-3 space-y-2">
      <div v-for="toast in whatsappToasts" :key="toast.id" class="flex items-start justify-between gap-3 rounded-lg border border-success/20 bg-success-light px-3 py-2 text-sm">
        <div>
          <p class="font-semibold text-success">{{ toast.titulo }}</p>
          <p class="whitespace-pre-line text-text-mid">{{ toast.mensaje }}</p>
        </div>
        <div class="flex shrink-0 items-center gap-2">
          <a :href="toast.url" target="_blank" rel="noopener" class="rounded-lg bg-success px-3 py-1.5 text-xs font-semibold text-white hover:opacity-90">
            Enviar por WhatsApp
          </a>
          <button type="button" class="text-text-soft hover:text-text-mid" @click="descartarToastWhatsapp(toast.id)">✕</button>
        </div>
      </div>
    </div>

    <VSection title="Pedidos">
      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <!-- Totales de tn/m³ del PERÍODO filtrado (2026-09-01: antes no existían
           acá; los 5 KPI de estado de abajo también pasaron de ser un conteo
           global fijo a estar acotados al mismo período — ver
           usePedidos.js#cargarResumenPeriodo).
           Ocultos en mobile (2026-09-07, pedido de Federico: "simplificar
           el uso en campo" — el foco pasa a ser crear/confirmar/despachar
           rápido, no mirar totales/conteos). Siguen en Desktop sin cambios. -->
      <div v-if="!esMobile" class="mb-3 grid grid-cols-2 gap-3">
        <VKpiCard label="Asfalto (período)" :value="totalesPeriodo.asfaltoTn.toFixed(1)" unidad="tn" />
        <VKpiCard label="Hormigón (período)" :value="totalesPeriodo.hormigonM3.toFixed(1)" unidad="m³" />
      </div>

      <!-- KPIs por estado (memory/relevamiento-sistema-viejo.md §1) — acotados
           al período filtrado (semana en curso por default), no al histórico
           completo del sistema.
           Clickeables (2026-09-02, roadmap Mobile/UX): cada card actúa como
           filtro rápido por estado — click activa filtros.estado (mismo
           <select> de abajo, ya no hace falta abrirlo para el caso más
           común) y recarga; click de nuevo sobre la misma card lo saca. La
           card activa queda resaltada con el mismo color del punto.
           Ocultas en mobile, mismo motivo que el bloque de arriba — el
           filtro por estado sigue disponible en Desktop. -->
      <div v-if="!esMobile" class="mb-4 grid grid-cols-2 gap-3 sm:grid-cols-5">
        <button
          v-for="estado in ESTADOS"
          :key="estado"
          type="button"
          class="rounded-xl border bg-white p-4 text-left shadow-sm transition-colors duration-150"
          :class="
            filtros.estado === estado
              ? 'border-vialtec ring-1 ring-vialtec'
              : 'border-border hover:border-vialtec/40'
          "
          style="min-height: 44px"
          @click="filtrarPorEstado(estado)"
        >
          <div class="flex items-center gap-2">
            <span class="h-2.5 w-2.5 rounded-full" :class="COLOR_KPI_ESTADO[estado]"></span>
            <span class="text-[11px] font-semibold uppercase tracking-wide text-text-soft">{{ estado }}</span>
          </div>
          <p class="mt-2 text-2xl font-extrabold text-text">{{ conteoEstados[estado] ?? 0 }}</p>
        </button>
      </div>

      <!-- Semana en curso (2026-09-02: se sacaron los botones de navegación
           anterior/siguiente/hoy a pedido de Federico — "simplificación de
           navegación". Sigue mostrando la semana en curso por default (no
           listar los 184 pedidos históricos de golpe); para ver otra fecha,
           "Ver histórico completo" + los filtros Desde/Hasta de abajo. -->
      <VCard class="mb-4">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <p class="text-sm font-semibold text-text">
            {{ vistaSemana ? `Semana en curso — ${rangoSemanaLabel}` : 'Histórico completo' }}
          </p>
          <VButton v-if="vistaSemana" variant="secondary" size="sm" @click="verHistoricoCompleto">
            Ver histórico completo
          </VButton>
          <VButton v-else variant="secondary" size="sm" @click="irASemanaActual">Volver a la semana actual</VButton>
        </div>
      </VCard>

      <!-- Filtros — ocultos en mobile (2026-09-07, pedido de Federico:
           "simplificar el uso en campo"). El listado sigue acotado a la
           semana en curso por default (tarjeta de arriba); para filtrar por
           estado/obra/rango o ver archivados hay que ir a Desktop. -->
      <VCard v-if="!esMobile" class="mb-4">
        <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
          <label class="text-sm text-text-mid">
            Estado
            <select
              v-model="filtros.estado"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            >
              <option value="">Todos</option>
              <option v-for="e in ESTADOS" :key="e" :value="e">{{ e }}</option>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Obra
            <select
              v-model="filtros.obraId"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            >
              <option value="">Todas</option>
              <option v-for="o in obras" :key="o.id" :value="o.id">{{ o.nombre }}</option>
            </select>
          </label>
          <template v-if="!vistaSemana">
            <label class="text-sm text-text-mid">
              Desde
              <input
                v-model="filtros.desde"
                type="date"
                class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              />
            </label>
            <label class="text-sm text-text-mid">
              Hasta
              <input
                v-model="filtros.hasta"
                type="date"
                class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              />
            </label>
          </template>
          <p v-else class="col-span-2 self-end text-xs text-text-soft">
            Fecha acotada a la semana en curso — usá "Ver histórico completo" para elegir un rango.
          </p>
        </div>
        <label class="mt-3 flex items-center gap-2 text-sm text-text-mid">
          <input v-model="filtros.incluirArchivados" type="checkbox" />
          Mostrar archivados
        </label>
        <div class="mt-3 flex gap-2">
          <VButton size="sm" @click="aplicarFiltros">Filtrar</VButton>
          <VButton variant="ghost" size="sm" @click="limpiarFiltros">Limpiar</VButton>
        </div>
      </VCard>

      <!-- Vista unificada en cards agrupadas por tipo (2026-09-04, réplica
           exacta del legado — relevado en vivo contra produccion.vialtec.app,
           memory/pending.md): ya no hay tabs Asfalto/Hormigón, las dos
           secciones conviven siempre con su propio contador ("N pedidos"),
           mismo orden Hormigón → Asfalto confirmado en vivo.
           Protagonismo del CTA en mobile (2026-09-07, pedido de Federico:
           con los KPI/filtros de arriba ocultos, este botón queda como lo
           primero que se ve — ancho completo + tamaño md para que se note). -->
      <div class="mb-3 flex justify-end">
        <VButton class="w-full md:w-auto" size="md" @click="abrirNuevo">+ Nuevo pedido</VButton>
      </div>

      <p v-if="cargando" class="text-sm text-text-soft">Cargando…</p>
      <template v-else>
        <div v-for="grupo in pedidosPorTipo" :key="grupo.tipo" class="mb-6">
          <div class="mb-3 flex items-baseline justify-between">
            <h3 class="text-lg font-bold text-text">{{ grupo.label }}</h3>
            <span class="text-sm text-text-soft">{{ grupo.filas.length }} pedido{{ grupo.filas.length === 1 ? '' : 's' }}</span>
          </div>
          <div class="space-y-3">
            <PedidoCard
              v-for="pedido in grupo.filas"
              :key="pedido.id"
              :pedido="pedido"
              :puede-confirmar="puedeConfirmar"
              :puede-despachar-asfalto="puedeDespacharAsfalto"
              :puede-despachar-hormigon="puedeDespacharHormigon"
              @confirmar="confirmar"
              @despachar="despacho.abrir"
              @registrar-carga="cargaHormigon.abrir"
              @editar="abrirEdicion"
              @postergar="abrirPostergacion"
              @cancelar="abrirCancelacion"
              @archivar="archivar"
              @ver-historial="abrirHistorial"
            />
            <p v-if="!grupo.filas.length" class="rounded-xl border border-dashed border-border py-4 text-center text-sm text-text-soft">
              No hay pedidos de {{ grupo.label.toLowerCase() }} que coincidan con el filtro.
            </p>
          </div>
        </div>
      </template>
    </VSection>

    <!-- Alta de pedido -->
    <VModal :open="modalNuevoAbierto" title="Nuevo pedido" @update:open="modalNuevoAbierto = $event">
      <form class="space-y-3" @submit.prevent="guardarNuevo">
        <label class="block text-sm text-text-mid">
          Tipo de pedido
          <select
            v-model="formNuevo.tipo_pedido"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          >
            <option value="obra">Producción interna</option>
            <option value="venta">Venta externa</option>
          </select>
        </label>

        <label v-if="formNuevo.tipo_pedido === 'obra'" class="block text-sm text-text-mid">
          Obra / Centro de costo
          <select
            v-model="formNuevo.obra_id"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          >
            <option value="" disabled>Elegir obra…</option>
            <option v-for="o in obras" :key="o.id" :value="o.id">{{ o.nombre }}</option>
          </select>
        </label>
        <label v-else class="block text-sm text-text-mid">
          Cliente externo
          <select
            v-model="formNuevo.cliente_externo"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          >
            <option value="" disabled>Elegir cliente…</option>
            <option v-for="c in clientes" :key="c.id" :value="c.nombre">{{ c.nombre }}</option>
            <!-- Fallback: un cliente cargado como texto libre antes de que existiera
                 este catálogo (Maestros → Clientes, 2026-09-09) no debe desaparecer
                 del select solo por no estar todavía en la lista. -->
            <option
              v-if="formNuevo.cliente_externo && !clientes.some((c) => c.nombre === formNuevo.cliente_externo)"
              :value="formNuevo.cliente_externo"
            >
              {{ formNuevo.cliente_externo }} (no está en el catálogo)
            </option>
          </select>
        </label>

        <label class="block text-sm text-text-mid">
          Responsable del pedido
          <input
            v-model="formNuevo.encargado"
            type="text"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          />
        </label>

        <label class="block text-sm text-text-mid">
          Mezcla
          <select
            v-model="formNuevo.formula_id"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            @change="alSeleccionarFormula"
          >
            <option value="" disabled>Elegir fórmula…</option>
            <option v-for="f in formulas" :key="f.id" :value="f.id">{{ f.nombre }}</option>
          </select>
        </label>
        <label class="block text-sm text-text-mid">
          Cantidad ({{ formNuevo.tipo === 'hormigon' ? 'm³' : 'tn' }})
          <input
            v-model.number="formNuevo.cantidad_solicitada"
            type="number"
            step="0.01"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          />
        </label>
        <label class="block text-sm text-text-mid">
          Fecha de entrega requerida
          <input
            v-model="formNuevo.fecha_programada"
            type="date"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          />
        </label>
        <label class="block text-sm text-text-mid">
          Notas (opcional)
          <textarea
            v-model="formNuevo.observaciones"
            rows="2"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          ></textarea>
        </label>
        <label class="block text-sm text-text-mid">
          Ubicación (opcional)
          <input
            v-model="formNuevo.ubicacion"
            type="text"
            placeholder="Ej.: Acceso norte, km 12…"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          />
        </label>

        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalNuevoAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="guardandoNuevo">{{ guardandoNuevo ? 'Guardando…' : 'Crear pedido' }}</VButton>
        </div>
      </form>
    </VModal>

    <!-- Edición de pedido -->
    <VModal :open="modalEditarAbierto" title="Editar pedido" @update:open="modalEditarAbierto = $event">
      <form class="space-y-3" @submit.prevent="guardarEdicion">
        <label class="block text-sm text-text-mid">
          Tipo de pedido
          <select
            v-model="formEditar.tipo_pedido"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          >
            <option value="obra">Producción interna</option>
            <option value="venta">Venta externa</option>
          </select>
        </label>

        <label v-if="formEditar.tipo_pedido === 'obra'" class="block text-sm text-text-mid">
          Obra / Centro de costo
          <select
            v-model="formEditar.obra_id"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          >
            <option value="" disabled>Elegir obra…</option>
            <option v-for="o in obras" :key="o.id" :value="o.id">{{ o.nombre }}</option>
          </select>
        </label>
        <label v-else class="block text-sm text-text-mid">
          Cliente externo
          <select
            v-model="formEditar.cliente_externo"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          >
            <option value="" disabled>Elegir cliente…</option>
            <option v-for="c in clientes" :key="c.id" :value="c.nombre">{{ c.nombre }}</option>
            <option
              v-if="formEditar.cliente_externo && !clientes.some((c) => c.nombre === formEditar.cliente_externo)"
              :value="formEditar.cliente_externo"
            >
              {{ formEditar.cliente_externo }} (no está en el catálogo)
            </option>
          </select>
        </label>

        <label class="block text-sm text-text-mid">
          Responsable del pedido
          <input
            v-model="formEditar.encargado"
            type="text"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          />
        </label>

        <label class="block text-sm text-text-mid">
          Mezcla
          <select
            v-model="formEditar.formula_id"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            @change="alSeleccionarFormulaEditar"
          >
            <option value="" disabled>Elegir fórmula…</option>
            <option v-for="f in formulas" :key="f.id" :value="f.id">{{ f.nombre }}</option>
          </select>
        </label>
        <label class="block text-sm text-text-mid">
          Cantidad ({{ formEditar.tipo === 'hormigon' ? 'm³' : 'tn' }})
          <input
            v-model.number="formEditar.cantidad_solicitada"
            type="number"
            step="0.01"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          />
        </label>
        <label class="block text-sm text-text-mid">
          Fecha de entrega requerida
          <input
            v-model="formEditar.fecha_programada"
            type="date"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          />
        </label>
        <label class="block text-sm text-text-mid">
          Notas (opcional)
          <textarea
            v-model="formEditar.observaciones"
            rows="2"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          ></textarea>
        </label>
        <label class="block text-sm text-text-mid">
          Ubicación (opcional)
          <input
            v-model="formEditar.ubicacion"
            type="text"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          />
        </label>

        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalEditarAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="guardandoEditar">{{ guardandoEditar ? 'Guardando…' : 'Guardar cambios' }}</VButton>
        </div>
      </form>
    </VModal>

    <!-- Despacho de asfalto: multi-camión con vale por carga -->
    <VModal :open="despacho.abierto" title="Registrar despacho" @update:open="despacho.abierto = $event">
      <div class="space-y-3">
        <div v-if="despacho.error" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
          {{ despacho.error }}
        </div>
        <p class="text-sm text-text-mid">
          {{ despacho.pedido?.tipo_pedido === 'venta' ? despacho.pedido?.cliente_externo : obras.find((o) => o.id === despacho.pedido?.obra_id)?.nombre }}
          — Solicitado: {{ despacho.pedido?.cantidad_solicitada }} tn · Saldo antes de este despacho: {{ despacho.saldoPendiente.toFixed(1) }} tn
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

        <p class="text-sm font-semibold text-text">Total: {{ despacho.totalCargas.toFixed(2) }} tn</p>
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
            Con estas cargas queda un saldo de <strong>{{ despacho.residualEstimado.toFixed(2) }} tn</strong> sin despachar.
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

    <!-- Despacho de hormigón: mismo patrón multi-camión, remito por carga -->
    <VModal :open="cargaHormigon.abierto" title="Registrar despacho" @update:open="cargaHormigon.abierto = $event">
      <div class="space-y-3">
        <div v-if="cargaHormigon.error" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
          {{ cargaHormigon.error }}
        </div>
        <p class="text-sm text-text-mid">
          {{ cargaHormigon.pedido?.tipo_pedido === 'venta' ? cargaHormigon.pedido?.cliente_externo : obras.find((o) => o.id === cargaHormigon.pedido?.obra_id)?.nombre }}
          — Solicitado: {{ cargaHormigon.pedido?.cantidad_solicitada }} m³ · Saldo antes de este despacho: {{ cargaHormigon.saldoPendiente.toFixed(1) }} m³
        </p>

        <div class="space-y-2">
          <p class="text-xs font-semibold uppercase tracking-wide text-text-soft">Cargas / camiones</p>
          <div
            v-for="(carga, idx) in cargaHormigon.cargas"
            :key="idx"
            class="grid grid-cols-1 items-end gap-2 rounded-lg border border-border p-2 md:grid-cols-[1fr_1fr_1fr_auto]"
          >
            <label class="text-xs text-text-mid">
              Cantidad (m³) *
              <input
                v-model.number="carga.volumen_m3"
                type="number"
                step="0.01"
                class="mt-1 w-full rounded-lg border border-border px-2 py-1.5 text-sm focus:border-vialtec focus:outline-none"
              />
            </label>
            <label class="text-xs text-text-mid">
              N° remito *
              <input
                v-model="carga.numero_remito"
                type="text"
                class="mt-1 w-full rounded-lg border border-border px-2 py-1.5 text-sm focus:border-vialtec focus:outline-none"
              />
            </label>
            <label class="text-xs text-text-mid">
              Patente (opcional)
              <input
                v-model="carga.patente_mixer"
                list="patentes-mixer"
                class="mt-1 w-full rounded-lg border border-border px-2 py-1.5 text-sm focus:border-vialtec focus:outline-none"
              />
            </label>
            <VButton
              type="button"
              variant="ghost"
              size="sm"
              :disabled="cargaHormigon.cargas.length <= 1"
              @click="cargaHormigon.quitarCarga(idx)"
            >
              ✕ Quitar carga
            </VButton>
          </div>
          <VButton type="button" variant="secondary" size="sm" @click="cargaHormigon.agregarCarga">+ Agregar carga</VButton>
        </div>

        <p class="text-sm font-semibold text-text">Total: {{ cargaHormigon.totalCargas.toFixed(2) }} m³</p>

        <div v-if="cargaHormigon.residualEstimado > 0" class="rounded-lg border border-warning/30 bg-warning-light/40 p-3">
          <p class="text-sm text-text-mid">
            Con estas cargas queda un saldo de <strong>{{ cargaHormigon.residualEstimado.toFixed(2) }} m³</strong> sin despachar.
            El pedido se va a cerrar como <strong>despachado</strong> igual, con lo cargado.
          </p>
          <label class="mt-2 flex items-center gap-2 text-sm text-text-mid">
            <input v-model="cargaHormigon.dividirPedido" type="checkbox" />
            Dividir pedido: crear un pedido nuevo confirmado por el saldo
          </label>
          <label v-if="cargaHormigon.dividirPedido" class="mt-2 block text-sm text-text-mid">
            Fecha del pedido residual
            <input
              v-model="cargaHormigon.fechaResidual"
              type="date"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none md:w-1/2"
            />
          </label>
        </div>

        <datalist id="patentes-mixer">
          <option v-for="p in patentes" :key="p.id" :value="p.patente" />
        </datalist>

        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="cargaHormigon.abierto = false">Cancelar</VButton>
          <VButton type="button" variant="success" :disabled="cargaHormigon.guardando" @click="cargaHormigon.guardar">
            {{ cargaHormigon.guardando ? 'Guardando…' : 'Confirmar despacho' }}
          </VButton>
        </div>
      </div>
    </VModal>

    <!-- Postergar -->
    <VModal :open="modalPostergarAbierto" title="Postergar pedido" @update:open="modalPostergarAbierto = $event">
      <form class="space-y-3" @submit.prevent="confirmarPostergacion">
        <div v-if="error" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">{{ error }}</div>
        <p class="text-sm text-text-mid">
          {{ pedidoPostergar?.tipo_pedido === 'venta' ? pedidoPostergar?.cliente_externo : obras.find((o) => o.id === pedidoPostergar?.obra_id)?.nombre }}
        </p>
        <label class="block text-sm text-text-mid">
          Nueva fecha de entrega (opcional)
          <input
            v-model="fechaNuevaPostergar"
            type="date"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          />
        </label>
        <label class="block text-sm text-text-mid">
          Motivo (opcional)
          <textarea
            v-model="motivoPostergar"
            rows="3"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          ></textarea>
        </label>
        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalPostergarAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="postergando">{{ postergando ? 'Guardando…' : 'Postergar pedido' }}</VButton>
        </div>
      </form>
    </VModal>

    <!-- Cancelación -->
    <VModal :open="modalCancelAbierto" title="Cancelar pedido" @update:open="modalCancelAbierto = $event">
      <form class="space-y-3" @submit.prevent="confirmarCancelacion">
        <div v-if="errorCancelacion" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
          {{ errorCancelacion }}
        </div>
        <label class="block text-sm text-text-mid">
          Motivo (obligatorio)
          <textarea
            v-model="motivoCancelacion"
            rows="3"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          ></textarea>
        </label>
        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalCancelAbierto = false">Volver</VButton>
          <VButton type="submit" variant="danger" :disabled="cancelando">
            {{ cancelando ? 'Guardando…' : 'Cancelar pedido' }}
          </VButton>
        </div>
      </form>
    </VModal>

    <!-- Historial del pedido -->
    <VModal :open="modalHistorialAbierto" title="Historial del pedido" @update:open="modalHistorialAbierto = $event">
      <p v-if="pedidoHistorial" class="mb-3 text-sm text-text-mid">
        <strong>{{ pedidoHistorial.tipo_pedido === 'venta' ? pedidoHistorial.cliente_externo : obras.find((o) => o.id === pedidoHistorial.obra_id)?.nombre }}</strong>
      </p>
      <p v-if="cargandoHistorial" class="text-sm text-text-soft">Cargando…</p>
      <ul v-else-if="eventosHistorial.length" class="space-y-3 border-l-2 border-border pl-4">
        <li v-for="evento in eventosHistorial" :key="evento.id">
          <div class="flex items-center justify-between">
            <VBadge :variant="VARIANTE_ESTADO[evento.estado]">{{ evento.estado }}</VBadge>
            <span class="text-xs text-text-soft">{{ new Date(evento.fecha_evento).toLocaleString('es-AR') }}</span>
          </div>
          <p v-if="evento.usuario_legado" class="mt-1 text-xs text-text-soft">👤 {{ evento.usuario_legado }}</p>
          <p v-if="evento.motivo" class="mt-1 text-sm text-text-mid">📝 {{ evento.motivo }}</p>
          <p v-if="evento.fecha_programada_nueva" class="mt-1 text-xs text-text-soft">
            Nueva fecha: {{ evento.fecha_programada_nueva }}
            <span v-if="evento.fecha_programada_anterior">(antes: {{ evento.fecha_programada_anterior }})</span>
          </p>
        </li>
      </ul>
      <p v-else class="text-sm text-text-soft">Todavía no hay eventos registrados para este pedido.</p>
      <div class="mt-4 flex justify-end">
        <VButton variant="secondary" @click="modalHistorialAbierto = false">Cerrar</VButton>
      </div>
    </VModal>
  </div>
</template>
