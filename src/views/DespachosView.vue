<script setup>
// Vista de Despachos: historial de pedidos despachados con KPIs, resumen por
// obra, filtros, detalle de cargas por camión, corrección post-despacho y
// remito imprimible. Toda la lógica de negocio vive en useDespachos()
// (memory/conventions.md: esta vista es template puro).
//
// Despachos es una vista SOBRE plantas_pedidos (estado='despachado'), no una
// tabla propia — memory/relevamiento-sistema-viejo.md §3.

import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VSection from '@/components/shared/VSection.vue'
import VButton from '@/components/shared/VButton.vue'
import VKpiCard from '@/components/shared/VKpiCard.vue'
import { useDespachos } from '@/modules/despachos/composables/useDespachos'
import DespachoImprimible from '@/modules/despachos/components/DespachoImprimible.vue'
import ValeImprimible from '@/modules/bascula/components/ValeImprimible.vue'

const MESES = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic']
const mesActualLabel = MESES[new Date().getMonth()]

const columnas = [
  { key: 'fecha_programada', label: 'Fecha' },
  { key: 'destino', label: 'Obra' },
  { key: 'formulaNombre', label: 'Mezcla' },
  { key: 'cantidad_solicitada', label: 'Pedido' },
  { key: 'cantidad_despachada', label: 'Real' },
  { key: 'diferencia', label: 'Diferencia' },
  { key: 'acciones', label: '' },
]

const {
  error,
  obras,
  formulas,
  patentes,
  kpisMes,
  kpisHistorico,
  filas,
  totalDespachos,
  paginaActual,
  cargando,
  filtros,
  TAMANO_PAGINA,
  aplicarFiltros,
  limpiarFiltros,
  cambiarPagina,
  mesResumen,
  resumenObras,
  cargandoResumen,
  cargarResumenPorObra,
  exportandoInforme,
  exportarInformeMensual,
  modalDetalleAbierto,
  pedidoDetalle,
  cargasDetalle,
  cargandoDetalle,
  rangoNumerosDetalle,
  abrirDetalle,
  modalCorregirAbierto,
  pedidoCorregir,
  formCorregir,
  corrigiendo,
  abrirCorreccion,
  guardarCorreccion,
  modalRemitoAbierto,
  pedidoRemito,
  cargasRemito,
  cargandoRemito,
  abrirRemito,
  imprimir,
  modalSeleccionValeAbierto,
  pedidoParaSeleccionVale,
  valesDisponibles,
  modalImpresionValeAbierto,
  valeParaImprimir,
  pedidoParaImprimirVale,
  acumuladoParaImprimirVale,
  rangoValesParaImprimirVale,
  abrirImpresionVale,
  elegirVale,
  formatearNumeroVale,
  destinoDe,
  iniciar,
} = useDespachos()

iniciar()

function unidadDe(tipo) {
  return tipo === 'hormigon' ? 'm³' : 'tn'
}
</script>

<template>
  <div>
    <VSection title="Despachos">
      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <!-- KPIs: mes en curso + acumulado histórico completo -->
      <div class="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
        <VKpiCard :label="`Asfalto ${mesActualLabel}`" :value="kpisMes.asfaltoTn.toFixed(1)" unidad="tn" />
        <VKpiCard :label="`Hormigón ${mesActualLabel}`" :value="kpisMes.hormigonM3.toFixed(1)" unidad="m³" />
        <VKpiCard label="Total asfalto acumulado" :value="kpisHistorico.asfaltoTn.toFixed(1)" unidad="tn" />
        <VKpiCard label="Total hormigón acumulado" :value="kpisHistorico.hormigonM3.toFixed(1)" unidad="m³" />
      </div>

      <!-- Filtros -->
      <VCard class="mb-4">
        <div class="flex flex-wrap gap-1.5">
          <VButton size="sm" :variant="filtros.tipo === '' ? 'primary' : 'secondary'" @click="filtros.tipo = ''; aplicarFiltros()">
            Todos
          </VButton>
          <VButton size="sm" :variant="filtros.tipo === 'asfalto' ? 'primary' : 'secondary'" @click="filtros.tipo = 'asfalto'; aplicarFiltros()">
            Asfalto
          </VButton>
          <VButton size="sm" :variant="filtros.tipo === 'hormigon' ? 'primary' : 'secondary'" @click="filtros.tipo = 'hormigon'; aplicarFiltros()">
            Hormigón
          </VButton>
        </div>
        <div class="mt-3 grid grid-cols-2 gap-3 md:grid-cols-4">
          <label class="text-sm text-text-mid">
            Mezcla
            <select v-model="filtros.formulaId" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none">
              <option value="">Todas</option>
              <option v-for="f in formulas" :key="f.id" :value="f.id">{{ f.nombre }}</option>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Obra
            <select v-model="filtros.obraId" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none">
              <option value="">Todas</option>
              <option v-for="o in obras" :key="o.id" :value="o.id">{{ o.nombre }}</option>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Desde
            <input v-model="filtros.desde" type="date" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none" />
          </label>
          <label class="text-sm text-text-mid">
            Hasta
            <input v-model="filtros.hasta" type="date" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none" />
          </label>
        </div>
        <div class="mt-3 flex gap-2">
          <VButton size="sm" @click="aplicarFiltros">Filtrar</VButton>
          <VButton variant="ghost" size="sm" @click="limpiarFiltros">Limpiar</VButton>
        </div>
      </VCard>

      <!-- Resumen por obra -->
      <VCard class="mb-4">
        <div class="mb-3 flex flex-wrap items-center justify-between gap-3">
          <p class="text-sm font-bold text-text">Resumen por obra</p>
          <div class="flex flex-wrap items-center gap-3">
            <label class="text-sm text-text-mid">
              Mes
              <input
                v-model="mesResumen"
                type="month"
                class="ml-2 rounded-lg border border-border px-2 py-1 text-sm focus:border-vialtec focus:outline-none"
                @change="cargarResumenPorObra"
              />
            </label>
            <!-- Informe mensual (2026-09-02, pedido de Federico): arma el
                 .xlsx completo del mes elegido arriba — Resumen mensual +
                 Resumen anual + una hoja por obra/cliente, mismo formato
                 que el Excel de referencia que compartió. -->
            <VButton size="sm" :disabled="exportandoInforme" @click="exportarInformeMensual">
              {{ exportandoInforme ? 'Generando…' : '📧 Exportar informe mensual' }}
            </VButton>
          </div>
        </div>
        <p v-if="cargandoResumen" class="text-sm text-text-soft">Cargando…</p>
        <div v-else-if="resumenObras.length" class="grid grid-cols-2 gap-3 md:grid-cols-4">
          <VCard v-for="r in resumenObras" :key="r.obraId ?? r.nombre">
            <p class="truncate text-sm font-semibold text-text">{{ r.nombre }}</p>
            <p v-if="r.asfaltoTn > 0" class="mt-1 text-lg font-bold text-text">{{ r.asfaltoTn.toFixed(1) }} <span class="text-xs font-normal text-text-soft">tn asfalto</span></p>
            <p v-if="r.hormigonM3 > 0" class="mt-1 text-lg font-bold text-text">{{ r.hormigonM3.toFixed(1) }} <span class="text-xs font-normal text-text-soft">m³ hormigón</span></p>
            <p class="mt-1 text-xs text-text-soft">{{ r.cantidadDespachos }} despacho{{ r.cantidadDespachos === 1 ? '' : 's' }}</p>
          </VCard>
        </div>
        <p v-else class="text-sm text-text-soft">No hay despachos en el mes seleccionado.</p>
      </VCard>

      <VCard>
        <p v-if="cargando" class="text-sm text-text-soft">Cargando…</p>
        <VTable
          v-else
          :columns="columnas"
          :rows="filas"
          :page="paginaActual"
          :page-size="TAMANO_PAGINA"
          :total="totalDespachos"
          @update:page="cambiarPagina"
        >
          <template #cell-fecha_programada="{ row }">
            <p>{{ row.fecha_programada }}</p>
            <!-- Solicitante junto a la fecha (2026-09-02, réplica del legado:
                 memory/relevamiento-sistema-viejo.md §3 muestra "👤 <nombre>"
                 debajo de la fecha) — plantas_pedidos.encargado ya existía en
                 el schema, solo faltaba mostrarlo acá. -->
            <p v-if="row.encargado" class="text-xs text-text-soft">👤 {{ row.encargado }}</p>
          </template>
          <template #cell-cantidad_solicitada="{ row }">
            {{ row.cantidad_solicitada }} {{ unidadDe(row.tipo) }}
          </template>
          <template #cell-cantidad_despachada="{ row }">
            {{ row.cantidad_despachada }} {{ unidadDe(row.tipo) }}
          </template>
          <template #cell-diferencia="{ row }">
            <span :class="row.diferencia > 0 ? 'text-warning' : 'text-text-soft'">
              {{ row.diferencia.toFixed(2) }} {{ unidadDe(row.tipo) }}
            </span>
          </template>
          <template #cell-acciones="{ row }">
            <div class="flex flex-wrap gap-1.5">
              <VButton variant="secondary" size="sm" @click="abrirDetalle(row)">🚛 Detalle de cargas</VButton>
              <VButton variant="secondary" size="sm" @click="abrirCorreccion(row)">Corregir</VButton>
              <!-- Selector Vale/Remito (2026-09-02, pedido de Federico): 2
                   botones en vez de un <select> — más claro en mobile, el
                   "Vale" internamente pregunta cuál si el despacho tuvo más
                   de un camión pesado en báscula. -->
              <VButton variant="ghost" size="sm" @click="abrirRemito(row)">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" class="h-3.5 w-3.5 shrink-0">
                  <path d="M1 12s4-7 11-7 11 7 11 7-4 7-11 7-11-7-11-7z" />
                  <circle cx="12" cy="12" r="3" />
                </svg>
                Remito
              </VButton>
              <VButton v-if="row.tipo === 'asfalto'" variant="ghost" size="sm" @click="abrirImpresionVale(row)">
                🖨 Vale
              </VButton>
            </div>
          </template>
        </VTable>
        <p v-if="!cargando && !filas.length" class="py-4 text-center text-sm text-text-soft">
          No hay despachos que coincidan con el filtro.
        </p>
      </VCard>
    </VSection>

    <!-- Modal: Detalle de cargas -->
    <VModal :open="modalDetalleAbierto" title="Detalle del despacho" @update:open="modalDetalleAbierto = $event">
      <div v-if="pedidoDetalle">
        <p class="mb-3 text-sm text-text-mid">
          <strong>{{ destinoDe(pedidoDetalle) }}</strong> — {{ pedidoDetalle.fecha_programada }} — {{ formulas.find((f) => f.id === pedidoDetalle.formula_id)?.nombre }}
        </p>
        <p v-if="cargandoDetalle" class="text-sm text-text-soft">Cargando…</p>
        <p
          v-else-if="cargasDetalle.length && cargasDetalle[0].fuente === 'bascula'"
          class="mb-2 rounded-lg bg-info-light px-3 py-2 text-xs text-info"
        >
          Este despacho no tiene cargas registradas en Pedidos (típico de despachos migrados del histórico
          anterior) — el detalle de abajo sale de los vales de báscula asociados, a título de auditoría.
        </p>
        <ul v-if="cargasDetalle.length" class="space-y-1.5">
          <li v-for="(carga, i) in cargasDetalle" :key="carga.id" class="rounded-lg border border-border px-3 py-2 text-sm">
            Carga {{ i + 1 }} — {{ carga.patente || 'sin patente' }} — {{ Number(carga.cantidad).toFixed(2) }} {{ unidadDe(pedidoDetalle.tipo) }}
            <span class="text-text-soft">— {{ pedidoDetalle.tipo === 'hormigon' ? 'Remito' : 'Vale' }}: {{ carga.numeroRemitoOVale || '—' }}</span>
          </li>
        </ul>
        <p v-else class="text-sm text-text-soft">No hay cargas registradas para este despacho.</p>
        <div v-if="cargasDetalle.length" class="mt-3 rounded-lg bg-success-light px-3 py-2 text-sm font-semibold text-success">
          Total despachado: {{ pedidoDetalle.cantidad_despachada }} {{ unidadDe(pedidoDetalle.tipo) }}
          <span class="ml-2 font-normal text-text-mid">N° {{ pedidoDetalle.tipo === 'hormigon' ? 'remito' : 'vale' }}: {{ rangoNumerosDetalle }}</span>
        </div>
      </div>
      <div class="mt-4 flex justify-end">
        <VButton variant="secondary" @click="modalDetalleAbierto = false">Cerrar</VButton>
      </div>
    </VModal>

    <!-- Modal: Corregir despacho -->
    <VModal :open="modalCorregirAbierto" title="Corregir despacho" @update:open="modalCorregirAbierto = $event">
      <form v-if="pedidoCorregir" class="space-y-3" @submit.prevent="guardarCorreccion">
        <p class="text-sm text-text-mid">
          <strong>{{ destinoDe(pedidoCorregir) }}</strong> — {{ pedidoCorregir.fecha_programada }}
        </p>
        <label class="block text-sm text-text-mid">
          Cantidad real ({{ unidadDe(pedidoCorregir.tipo) }})
          <input
            v-model.number="formCorregir.cantidadDespachada"
            type="number"
            step="0.01"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          />
        </label>
        <label class="block text-sm text-text-mid">
          N° de remito
          <input v-model="formCorregir.nroRemitoGlobal" type="text" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none" />
        </label>
        <label v-if="pedidoCorregir.tipo === 'asfalto'" class="block text-sm text-text-mid">
          N° de vale
          <input v-model="formCorregir.nroValeGlobal" type="text" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none" />
        </label>
        <label class="block text-sm text-text-mid">
          Notas (motivo de la corrección)
          <textarea v-model="formCorregir.notas" rows="2" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"></textarea>
        </label>
        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalCorregirAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="corrigiendo">{{ corrigiendo ? 'Guardando…' : 'Guardar corrección' }}</VButton>
        </div>
      </form>
    </VModal>

    <!-- Modal: Ver remito imprimible -->
    <VModal :open="modalRemitoAbierto" title="Remito de despacho" @update:open="modalRemitoAbierto = $event">
      <p v-if="cargandoRemito" class="text-sm text-text-soft">Cargando…</p>
      <div v-else class="imprimible">
        <DespachoImprimible
          v-if="pedidoRemito"
          :pedido="pedidoRemito"
          :obra-nombre="destinoDe(pedidoRemito)"
          :formula-nombre="formulas.find((f) => f.id === pedidoRemito.formula_id)?.nombre"
          :cargas="cargasRemito"
        />
      </div>
      <div class="mt-4 flex justify-end gap-2">
        <VButton variant="secondary" @click="modalRemitoAbierto = false">Cerrar</VButton>
        <VButton @click="imprimir">Imprimir</VButton>
      </div>
    </VModal>

    <!-- Modal: elegir cuál vale imprimir (solo cuando el despacho tuvo más de un camión pesado en báscula) -->
    <VModal
      :open="modalSeleccionValeAbierto"
      title="Elegir vale a imprimir"
      @update:open="modalSeleccionValeAbierto = $event"
    >
      <p class="mb-3 text-sm text-text-mid">
        Este despacho tiene {{ valesDisponibles.length }} vales de báscula asociados — elegí cuál imprimir:
      </p>
      <ul class="space-y-1.5">
        <li v-for="v in valesDisponibles" :key="v.id">
          <button
            type="button"
            class="flex w-full items-center justify-between rounded-lg border border-border px-3 py-2.5 text-left text-sm hover:border-vialtec"
            @click="elegirVale(v.id)"
          >
            <span>N° {{ formatearNumeroVale(v.numeroVale) }} — {{ v.patente || 'sin patente' }}</span>
            <span class="text-text-soft">{{ v.pesoNetoTn.toFixed(2) }} tn</span>
          </button>
        </li>
      </ul>
      <div class="mt-4 flex justify-end">
        <VButton variant="secondary" @click="modalSeleccionValeAbierto = false">Cancelar</VButton>
      </div>
    </VModal>

    <!-- Modal: Imprimir vale (reusa ValeImprimible.vue de Báscula, mismo componente que useBascula.js) -->
    <VModal :open="modalImpresionValeAbierto" title="Vale de pesaje" @update:open="modalImpresionValeAbierto = $event">
      <div class="imprimible">
        <ValeImprimible
          v-if="valeParaImprimir && pedidoParaImprimirVale"
          :vale="valeParaImprimir"
          :obra-nombre="destinoDe(pedidoParaImprimirVale)"
          :mezcla-nombre="formulas.find((f) => f.id === pedidoParaImprimirVale.formula_id)?.nombre"
          modo="vale"
          :acumulado-tn="acumuladoParaImprimirVale"
          :pedido="pedidoParaImprimirVale"
          :rango-vales="rangoValesParaImprimirVale"
          :patentes="patentes"
        />
      </div>
      <div class="mt-4 flex justify-end gap-2">
        <VButton variant="secondary" @click="modalImpresionValeAbierto = false">Cerrar</VButton>
        <VButton @click="imprimir">Imprimir</VButton>
      </div>
    </VModal>
  </div>
</template>
