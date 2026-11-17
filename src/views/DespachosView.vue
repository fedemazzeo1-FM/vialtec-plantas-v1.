<script setup>
// Vista de Despachos (orden del 17/11/2026, aprobado por Federico): arriba
// "Descargar informe mensual" y "Generar remito manual"; una barra de filtros
// (período con atajos, tipo, destino = obra o cliente, mezcla) que se aplica
// sola y gobierna las pestañas Despachos (totales + tabla) y Resumen por obra;
// pestaña Remitos manuales aparte. Detalle de cargas por camión, corrección
// post-despacho y remito/vale imprimible en modales. Toda la lógica de negocio vive en useDespachos()
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
import { useDespachos, PERIODOS } from '@/modules/despachos/composables/useDespachos'
import RemitoImprimible from '@/components/shared/RemitoImprimible.vue'
import ValeImprimible from '@/modules/bascula/components/ValeImprimible.vue'
import { formatearNumeroRemito, formatearNumeroPedido, formatearCantidad, formatearCantidadHasta } from '@/services/formato-numeros'
import { nextTick, ref, watch } from 'vue'
import ValesManuales from '@/modules/despachos/components/ValesManuales.vue'
import { useRoute, useRouter } from 'vue-router'
import {
  LISTA_TIPOS_PRODUCTO,
  esCircuitoBascula,
  esCircuitoMixer,
  unidadLabelTipoProducto,
} from '@/config/tipos-producto'

const columnas = [
  { key: 'numero', label: 'N°' },
  { key: 'fecha_programada', label: 'Fecha' },
  { key: 'destino', label: 'Destino' },
  { key: 'formulaNombre', label: 'Mezcla' },
  { key: 'cantidad_despachada', label: 'Despachado' },
  { key: 'acciones', label: '' },
]

const TABS = [
  { valor: 'despachos', label: 'Despachos' },
  { valor: 'obras', label: 'Resumen por obra' },
  { valor: 'remitos', label: 'Remitos manuales' },
  { valor: 'vales', label: 'Vales manuales' },
]
// Vales manuales (migración 77): simulaciones, viven en su propio componente; el botón del encabezado
// abre la pestaña y su formulario.
const refValesManuales = ref(null)
async function abrirValeManual() {
  tabActiva.value = 'vales'
  await nextTick()
  refValesManuales.value?.abrirNuevo()
}
// La pestaña vive en ?tab= (mismo patrón que Stock y Maestros): F5 y "atrás" vuelven a la misma.
const route = useRoute()
const router = useRouter()
const tabActiva = ref(TABS.some((t) => t.valor === route.query.tab) ? route.query.tab : 'despachos')
watch(tabActiva, (tab) => router.replace({ query: { ...route.query, tab } }))

const {
  error,
  obras,
  formulas,
  patentes,
  clientes,
  filas,
  totalDespachos,
  paginaActual,
  cargando,
  filtros,
  periodo,
  elegirPeriodo,
  destino,
  TAMANO_PAGINA,
  limpiarFiltros,
  cambiarPagina,
  totalesFiltro,
  tiposTotalesFiltro,
  cargandoTotalesFiltro,
  exportandoFiltro,
  exportarFiltroExcel,
  resumenObras,
  exportandoInforme,
  modalInformeAbierto,
  mesInforme,
  abrirModalInforme,
  descargarInformeDelMes,
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
  imprimir,
  remitosManuales,
  unidadesRemitoManual,
  cargandoRemitosManuales,
  modalRemitoManualAbierto,
  formRemitoManual,
  generandoRemitoManual,
  errorRemitoManual,
  abrirRemitoManual,
  agregarItemRemitoManual,
  quitarItemRemitoManual,
  guardarRemitoManual,
  remitoManualParaImprimir,
  remitoManualProps,
  verRemitoManual,
  modalSeleccionValeAbierto,
  pedidoParaSeleccionVale,
  valesDisponibles,
  modalImpresionValeAbierto,
  valeParaImprimir,
  pedidoParaImprimirVale,
  acumuladoParaImprimirVale,
  rangoValesParaImprimirVale,
  avisoImpresionVale,
  prepararImpresionVale,
  abrirImpresionVale,
  elegirVale,
  formatearNumeroVale,
  destinoDe,
  iniciar,
} = useDespachos()

iniciar()

const unidadDe = unidadLabelTipoProducto

// "Descargar PDF" (2026-09-14, pedido de Federico: al lado de "Imprimir" en
// los 3 modales de vista previa del sistema) — mismo elemento ".imprimible"
// que ya arma cada modal para imprimir, pdf-imprimible.js lo rasteriza tal
// cual. 2 modales acá (Remito Manual y Vale), cada uno con su propio
// template ref y su propio nombre de archivo.
const refImprimibleRemito = ref(null)
const descargandoPdfRemito = ref(false)

async function descargarPdfRemito() {
  descargandoPdfRemito.value = true
  error.value = null
  try {
    // Import dinámico a propósito — ver el mismo comentario en useBascula.js/
    // BasculaView.vue#descargarPdf(): html2canvas+jsPDF solo se cargan al
    // hacer clic acá, no al entrar a Despachos.
    const { descargarPdfImprimible } = await import('@/services/pdf-imprimible')
    const nombreArchivo = `Remito-${formatearNumeroRemito(remitoManualProps.value?.numeroRemito)}`
    await descargarPdfImprimible(refImprimibleRemito.value, { tipo: 'remito', nombreArchivo })
  } catch (e) {
    error.value = 'No se pudo generar el PDF: ' + e.message
  } finally {
    descargandoPdfRemito.value = false
  }
}

const refImprimibleVale = ref(null)
const descargandoPdfVale = ref(false)

async function descargarPdfVale() {
  descargandoPdfVale.value = true
  error.value = null
  try {
    const { descargarPdfImprimible } = await import('@/services/pdf-imprimible')
    // El PDF también queda en la auditoría como impresión (migración 65).
    await prepararImpresionVale('pdf')
    const nombreArchivo = `Vale-${formatearNumeroVale(valeParaImprimir.value?.numero_vale)}`
    await descargarPdfImprimible(refImprimibleVale.value, { tipo: 'vale', nombreArchivo })
  } catch (e) {
    error.value = 'No se pudo generar el PDF: ' + e.message
  } finally {
    descargandoPdfVale.value = false
  }
}
</script>

<template>
  <div>
    <VSection title="Despachos">
      <!-- Acciones de la pantalla, arriba (el informe es el mismo Excel que va adjunto al mail del día 3). -->
      <div class="mb-4 flex flex-wrap justify-end gap-2">
        <VButton variant="secondary" @click="tabActiva = 'remitos'; abrirRemitoManual()">+ Generar remito manual</VButton>
        <VButton variant="secondary" @click="abrirValeManual">+ Generar vale manual</VButton>
        <VButton @click="abrirModalInforme">
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            class="mr-1.5 inline-block h-4 w-4 align-[-3px]"
            aria-hidden="true"
          >
            <line x1="18" y1="20" x2="18" y2="10" />
            <line x1="12" y1="20" x2="12" y2="4" />
            <line x1="6" y1="20" x2="6" y2="14" />
          </svg>
          Descargar informe mensual
        </VButton>
      </div>

      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <div class="mb-4 flex gap-1 overflow-x-auto border-b border-border">
        <button
          v-for="tab in TABS"
          :key="tab.valor"
          type="button"
          class="shrink-0 whitespace-nowrap border-b-2 px-3 py-2 text-sm font-semibold transition-colors duration-150"
          :class="tab.valor === tabActiva ? 'border-vialtec text-vialtec' : 'border-transparent text-text-soft hover:text-text-mid'"
          @click="tabActiva = tab.valor"
        >
          {{ tab.label }}
        </button>
      </div>

      <!-- Filtros: período, tipo, destino y mezcla. Se aplican solos y valen para Despachos y Resumen por obra. -->
      <VCard v-if="tabActiva === 'despachos' || tabActiva === 'obras'" class="mb-4">
        <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
          <div class="flex flex-wrap gap-1.5">
            <VButton
              v-for="p in PERIODOS"
              :key="p.valor"
              size="sm"
              :variant="periodo === p.valor ? 'primary' : 'secondary'"
              @click="elegirPeriodo(p.valor)"
            >
              {{ p.label }}
            </VButton>
          </div>
          <div class="flex flex-wrap gap-1.5">
            <VButton size="sm" :variant="filtros.tipo === '' ? 'primary' : 'secondary'" @click="filtros.tipo = ''">Todos</VButton>
            <VButton
              v-for="t in LISTA_TIPOS_PRODUCTO"
              :key="t.id"
              size="sm"
              :variant="filtros.tipo === t.id ? 'primary' : 'secondary'"
              @click="filtros.tipo = t.id"
            >
              {{ t.nombre }}
            </VButton>
          </div>
        </div>
        <div class="mt-3 grid grid-cols-2 gap-3" :class="periodo === 'rango' ? 'md:grid-cols-4' : 'md:grid-cols-2'">
          <label v-if="periodo === 'rango'" class="text-sm text-text-mid">
            Desde
            <input v-model="filtros.desde" type="date" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none" />
          </label>
          <label v-if="periodo === 'rango'" class="text-sm text-text-mid">
            Hasta
            <input v-model="filtros.hasta" type="date" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none" />
          </label>
          <!-- Destino: obra propia o cliente de venta externa en un solo selector (antes, dos). -->
          <label class="text-sm text-text-mid">
            Destino
            <select v-model="destino" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none">
              <option value="">Todos</option>
              <optgroup label="Obras">
                <option v-for="o in obras" :key="o.id" :value="`obra:${o.id}`">{{ o.nombre }}</option>
              </optgroup>
              <optgroup label="Ventas externas">
                <option v-for="c in clientes" :key="c.id" :value="`cliente:${c.nombre}`">{{ c.nombre }}</option>
              </optgroup>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Mezcla
            <select v-model="filtros.formulaId" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none">
              <option value="">Todas</option>
              <option v-for="f in formulas" :key="f.id" :value="f.id">{{ f.nombre }}</option>
            </select>
          </label>
        </div>
        <div class="mt-2 flex justify-end">
          <VButton variant="ghost" size="sm" @click="limpiarFiltros">Limpiar filtros</VButton>
        </div>
      </VCard>

      <!-- Pestaña Despachos: totales del período (universo completo, no la página) pegados a la tabla.
           Asfalto, hormigón y mezcla nunca se suman entre sí. -->
      <template v-if="tabActiva === 'despachos'">
        <div class="mb-3 flex flex-wrap items-end justify-between gap-3">
          <p v-if="cargandoTotalesFiltro" class="text-sm text-text-soft">Calculando…</p>
          <div v-else class="grid flex-1 grid-cols-2 gap-3 sm:grid-cols-4">
            <VKpiCard
              v-for="t in tiposTotalesFiltro"
              :key="t.id"
              :label="`${t.nombre} despachado`"
              :value="formatearCantidad(totalesFiltro[t.total])"
              :unidad="t.unidadLabel"
            />
            <VKpiCard label="Despachos" :value="totalesFiltro.cantidadDespachos" unidad="" />
          </div>
          <VButton size="sm" variant="secondary" :disabled="exportandoFiltro || !totalesFiltro.cantidadDespachos" @click="exportarFiltroExcel">
            {{ exportandoFiltro ? 'Generando…' : '⬇ Exportar a Excel' }}
          </VButton>
        </div>

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
            <template #cell-numero="{ row }">
              <span class="whitespace-nowrap text-text-soft">{{ formatearNumeroPedido(row.numero) }}</span>
            </template>
            <template #cell-fecha_programada="{ row }">
              <p>{{ row.fecha_programada }}</p>
              <!-- Solicitante junto a la fecha (2026-09-02, réplica del legado:
                   memory/relevamiento-sistema-viejo.md §3 muestra "👤 <nombre>"
                   debajo de la fecha) — plantas_pedidos.encargado ya existía en
                   el schema, solo faltaba mostrarlo acá. -->
              <p v-if="row.encargado" class="text-xs text-text-soft">👤 {{ row.encargado }}</p>
            </template>
            <!-- Despachado y, debajo, lo pedido; si faltó, la diferencia en ámbar
                 (antes, tres columnas Pedido / Real / Diferencia). -->
            <template #cell-cantidad_despachada="{ row }">
              <p class="whitespace-nowrap font-semibold text-text">{{ formatearCantidadHasta(row.cantidad_despachada) }} {{ unidadDe(row.tipo) }}</p>
              <p class="whitespace-nowrap text-xs text-text-soft">
                de {{ formatearCantidadHasta(row.cantidad_solicitada) }} pedido<span v-if="row.diferencia > 0" class="font-semibold text-warning"> · faltó {{ formatearCantidad(row.diferencia, 2) }}</span>
              </p>
            </template>
            <template #cell-acciones="{ row }">
              <div class="flex flex-wrap gap-1.5">
                <VButton variant="secondary" size="sm" @click="abrirDetalle(row)">🚛 Cargas</VButton>
                <VButton variant="secondary" size="sm" @click="abrirCorreccion(row)">Corregir</VButton>
                <!-- Botón "Remito" removido de acá (2026-09-14, pedido de
                     Federico): la impresión de remito de un despacho queda
                     únicamente en Báscula (abrirImpresionRemito, sobre un vale
                     ya pesado) — Despachos ya no ofrece un segundo camino para
                     el mismo documento. "Remito Manual" (más arriba, sin
                     pedido asociado) es una funcionalidad distinta, no se
                     toca. -->
                <VButton v-if="esCircuitoBascula(row.tipo)" variant="ghost" size="sm" @click="abrirImpresionVale(row)">
                  🖨 Vale
                </VButton>
              </div>
            </template>
          </VTable>
          <p v-if="!cargando && !filas.length" class="py-4 text-center text-sm text-text-soft">
            No hay despachos con estos filtros.
          </p>
        </VCard>
      </template>

      <!-- Pestaña Resumen por obra: el mismo período y filtros, agrupado por obra o cliente. -->
      <template v-if="tabActiva === 'obras'">
        <p v-if="cargandoTotalesFiltro" class="text-sm text-text-soft">Cargando…</p>
        <div v-else-if="resumenObras.length" class="grid grid-cols-2 gap-3 md:grid-cols-4">
          <VCard v-for="r in resumenObras" :key="r.obraId ?? r.nombre">
            <p class="truncate text-sm font-semibold text-text">{{ r.nombre }}</p>
            <template v-for="t in LISTA_TIPOS_PRODUCTO" :key="t.id">
              <p v-if="r[t.total] > 0" class="mt-1 text-lg font-bold text-text">{{ formatearCantidad(r[t.total]) }} <span class="text-xs font-normal text-text-soft">{{ t.unidadLabel }} {{ t.nombre.toLowerCase() }}</span></p>
            </template>
            <p class="mt-1 text-xs text-text-soft">{{ r.cantidadDespachos }} despacho{{ r.cantidadDespachos === 1 ? '' : 's' }}</p>
          </VCard>
        </div>
        <p v-else class="text-sm text-text-soft">No hay despachos con estos filtros.</p>
      </template>

      <!-- Pestaña Remitos manuales (2026-09-09): remito oficial sin pedido asociado, para envío de materiales a
           obra u otro movimiento interno — N° automático, misma numeración que los remitos de asfalto. -->
      <ValesManuales
        v-if="tabActiva === 'vales'"
        ref="refValesManuales"
        :obras="obras"
        :clientes="clientes"
        :formulas="formulas"
        :patentes="patentes"
      />

      <VCard v-if="tabActiva === 'remitos'">
          <p v-if="cargandoRemitosManuales" class="text-sm text-text-soft">Cargando…</p>
          <div v-else-if="remitosManuales.length" class="overflow-x-auto">
            <table class="w-full text-left text-sm">
              <thead>
                <tr class="border-b border-border text-xs uppercase tracking-wide text-text-soft">
                  <th class="py-1.5 pr-3">N°</th>
                  <th class="py-1.5 pr-3">Fecha</th>
                  <th class="py-1.5 pr-3">Destino</th>
                  <th class="py-1.5"></th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="r in remitosManuales" :key="r.id" class="border-b border-border/60">
                  <td class="py-1.5 pr-3 font-semibold text-text">{{ formatearNumeroRemito(r.numero_remito) }}</td>
                  <td class="py-1.5 pr-3">{{ r.fecha }}</td>
                  <td class="py-1.5 pr-3 text-text-soft">{{ r.destino || '—' }}</td>
                  <td class="py-1.5">
                    <VButton variant="ghost" size="sm" @click="verRemitoManual(r)">Reimprimir</VButton>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p v-else class="text-sm text-text-soft">Todavía no se generó ningún remito manual.</p>
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
            Carga {{ i + 1 }} — {{ carga.patente || 'sin patente' }} — {{ formatearCantidad(carga.cantidad, 2) }} {{ unidadDe(pedidoDetalle.tipo) }}
            <span class="text-text-soft">— {{ esCircuitoMixer(pedidoDetalle.tipo) ? 'Remito' : 'Vale' }}: {{ carga.numeroRemitoOVale || '—' }}</span>
          </li>
        </ul>
        <p v-else class="text-sm text-text-soft">No hay cargas registradas para este despacho.</p>
        <div v-if="cargasDetalle.length" class="mt-3 rounded-lg bg-success-light px-3 py-2 text-sm font-semibold text-success">
          Total despachado: {{ formatearCantidadHasta(pedidoDetalle.cantidad_despachada) }} {{ unidadDe(pedidoDetalle.tipo) }}
          <span class="ml-2 font-normal text-text-mid">N° {{ esCircuitoMixer(pedidoDetalle.tipo) ? 'remito' : 'vale' }}: {{ rangoNumerosDetalle }}</span>
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
        <div v-if="error" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">{{ error }}</div>
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
        <label v-if="esCircuitoBascula(pedidoCorregir.tipo)" class="block text-sm text-text-mid">
          N° de vale
          <input v-model="formCorregir.nroValeGlobal" type="text" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none" />
        </label>
        <label class="block text-sm text-text-mid">
          Motivo de la corrección (obligatorio)
          <textarea v-model="formCorregir.notas" rows="2" class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"></textarea>
        </label>
        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalCorregirAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="corrigiendo">{{ corrigiendo ? 'Guardando…' : 'Guardar corrección' }}</VButton>
        </div>
      </form>
    </VModal>

    <!-- Modal: Remito Manual imprimible — Teleport a <body> (2026-09-04, mismo
         fix que Báscula: ver comentario en src/assets/main.css). Desde
         2026-09-14 este modal es EXCLUSIVO de Remito Manual (pedido de
         Federico: la impresión de remito de un despacho puntual quedó
         únicamente en Báscula) — antes también servía para el remito de un
         pedido despachado (DespachoImprimible.vue), ver historial de git. -->
    <Teleport to="body">
      <VModal :open="modalRemitoAbierto" title="Remito manual" size="xl" @update:open="modalRemitoAbierto = $event">
        <!-- modo-remito (2026-09-14): mismo criterio que el remito de Báscula
             (ver src/assets/main.css) — dimensiones A4 portrait (210×297mm)
             en vez del landscape default de .imprimible. -->
        <div ref="refImprimibleRemito" class="imprimible modo-remito">
          <RemitoImprimible v-if="remitoManualProps" v-bind="remitoManualProps" />
        </div>
        <div class="mt-4 flex justify-end gap-2">
          <VButton variant="secondary" @click="modalRemitoAbierto = false">Cerrar</VButton>
          <VButton variant="secondary" :disabled="descargandoPdfRemito" @click="descargarPdfRemito">
            {{ descargandoPdfRemito ? 'Generando…' : 'Descargar PDF' }}
          </VButton>
          <VButton @click="imprimir">Imprimir</VButton>
        </div>
      </VModal>
    </Teleport>

    <!-- Modal: generar Remito Manual/Blanco (2026-09-09, pedido de Federico) -->
    <VModal :open="modalRemitoManualAbierto" title="Generar remito manual" @update:open="modalRemitoManualAbierto = $event">
      <form class="space-y-3" @submit.prevent="guardarRemitoManual">
        <div v-if="errorRemitoManual" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
          {{ errorRemitoManual }}
        </div>
        <p class="text-xs text-text-soft">
          Para envío de materiales a obra u otro movimiento interno sin pedido asociado. El N° de remito lo asigna el
          sistema automáticamente (misma numeración correlativa que los remitos de asfalto).
        </p>

        <div class="space-y-2">
          <p class="text-xs font-semibold uppercase tracking-wide text-text-soft">Items del remito</p>
          <div
            v-for="(item, idx) in formRemitoManual.items"
            :key="idx"
            class="grid grid-cols-1 items-end gap-2 rounded-lg border border-border p-2 md:grid-cols-[1fr_1fr_2fr_auto]"
          >
            <label class="text-xs text-text-mid">
              Cantidad (opcional)
              <input
                v-model="item.cantidad"
                type="text"
                placeholder="Ej.: 20"
                class="mt-1 w-full rounded-lg border border-border px-2 py-1.5 text-sm focus:border-vialtec focus:outline-none"
              />
            </label>
            <label class="text-xs text-text-mid">
              Unidad
              <select
                v-model="item.unidad"
                class="mt-1 w-full rounded-lg border border-border px-2 py-1.5 text-sm focus:border-vialtec focus:outline-none"
              >
                <option value="">—</option>
                <option v-for="u in unidadesRemitoManual" :key="u" :value="u">{{ u }}</option>
              </select>
            </label>
            <label class="text-xs text-text-mid">
              Descripción *
              <input
                v-model="item.descripcion"
                type="text"
                placeholder="Ej.: Palets"
                class="mt-1 w-full rounded-lg border border-border px-2 py-1.5 text-sm focus:border-vialtec focus:outline-none"
              />
            </label>
            <VButton
              type="button"
              variant="ghost"
              size="sm"
              :disabled="formRemitoManual.items.length <= 1"
              @click="quitarItemRemitoManual(idx)"
            >
              ✕ Quitar
            </VButton>
          </div>
          <VButton type="button" variant="secondary" size="sm" @click="agregarItemRemitoManual">+ Agregar item</VButton>
        </div>

        <label class="block text-sm text-text-mid">
          Fecha
          <input
            v-model="formRemitoManual.fecha"
            type="date"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          />
        </label>
        <label class="block text-sm text-text-mid">
          Destino (opcional)
          <input
            v-model="formRemitoManual.destino"
            type="text"
            placeholder="Obra o lugar de entrega…"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          />
        </label>
        <div class="grid grid-cols-2 gap-3">
          <label class="text-sm text-text-mid">
            Patente (opcional)
            <input
              v-model="formRemitoManual.patente"
              list="patentes-remito-manual"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </label>
          <label class="text-sm text-text-mid">
            Transportista (opcional)
            <input
              v-model="formRemitoManual.transportista"
              type="text"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </label>
        </div>
        <p class="text-xs text-text-soft">
          Dejá Destino/Patente/Transportista en blanco si preferís completarlos a mano en el papel impreso.
        </p>
        <datalist id="patentes-remito-manual">
          <option v-for="p in patentes" :key="p.id" :value="p.patente" />
        </datalist>

        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalRemitoManualAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="generandoRemitoManual">
            {{ generandoRemitoManual ? 'Generando…' : 'Generar e imprimir' }}
          </VButton>
        </div>
      </form>
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
            <span class="text-text-soft">{{ formatearCantidad(v.pesoNetoTn, 2) }} tn</span>
          </button>
        </li>
      </ul>
      <div class="mt-4 flex justify-end">
        <VButton variant="secondary" @click="modalSeleccionValeAbierto = false">Cancelar</VButton>
      </div>
    </VModal>

    <!-- Modal: Imprimir vale (reusa ValeImprimible.vue de Báscula, mismo
         componente que useBascula.js) — Teleport a <body>, mismo fix. -->
    <Teleport to="body">
      <VModal :open="modalImpresionValeAbierto" title="Vale de pesaje" size="xl" @update:open="modalImpresionValeAbierto = $event">
        <div ref="refImprimibleVale" class="imprimible">
          <ValeImprimible
            v-if="valeParaImprimir && pedidoParaImprimirVale"
            :vale="valeParaImprimir"
            :obra-nombre="destinoDe(pedidoParaImprimirVale)"
            :mezcla-nombre="formulas.find((f) => f.id === pedidoParaImprimirVale.formula_id)?.nombre"
            :cliente-externo="pedidoParaImprimirVale.tipo_pedido === 'venta'"
            :acumulado-tn="acumuladoParaImprimirVale"
            :pedido="pedidoParaImprimirVale"
            :rango-vales="rangoValesParaImprimirVale"
            :patentes="patentes"
          />
        </div>
        <p v-if="avisoImpresionVale" class="mt-3 rounded-lg border border-warning/30 bg-warning-light px-3 py-2 text-sm text-warning">{{ avisoImpresionVale }}</p>
        <div class="mt-4 flex justify-end gap-2">
          <VButton variant="secondary" @click="modalImpresionValeAbierto = false">Cerrar</VButton>
          <VButton variant="secondary" :disabled="descargandoPdfVale" @click="descargarPdfVale">
            {{ descargandoPdfVale ? 'Generando…' : 'Descargar PDF' }}
          </VButton>
          <VButton @click="imprimir">Imprimir</VButton>
        </div>
      </VModal>
    </Teleport>

    <VModal :open="modalInformeAbierto" title="Descargar informe mensual" @update:open="modalInformeAbierto = $event">
      <label class="mb-1 block text-sm font-semibold text-text-mid">Mes *</label>
      <input
        v-model="mesInforme"
        type="month"
        class="w-full rounded-md border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
      />
      <p class="mt-1 text-xs text-text-soft">
        El Excel del informe: resumen, una hoja por obra, consumo de insumos, resumen anual y proveedores. Es el
        mismo que va adjunto en el informe que sale por mail el día 3.
      </p>
      <div class="mt-5 flex flex-wrap justify-end gap-2">
        <VButton variant="secondary" :disabled="exportandoInforme" @click="modalInformeAbierto = false">
          Cancelar
        </VButton>
        <VButton :disabled="exportandoInforme" @click="descargarInformeDelMes">
          {{ exportandoInforme ? 'Generando…' : '⬇ Descargar Excel' }}
        </VButton>
      </div>
    </VModal>

  </div>
</template>
