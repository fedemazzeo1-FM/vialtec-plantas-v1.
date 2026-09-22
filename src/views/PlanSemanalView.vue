<script setup>
// Plan Semanal: matriz lunes-domingo de pedidos + KPIs de acumulado semanal en
// dos métricas paralelas (asfalto en tn, hormigón en m³). Toda la persistencia
// pasa por pedidos.service.js — este componente no llama a Supabase
// directamente (memory/conventions.md).

import { computed, ref } from 'vue'
import VCard from '@/components/shared/VCard.vue'
import VKpiCard from '@/components/shared/VKpiCard.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VSection from '@/components/shared/VSection.vue'
import VButton from '@/components/shared/VButton.vue'
import {
  obtenerRangoSemana,
  fetchPedidosSemana,
  fetchTotalesSemana,
  confirmarPedido,
} from '@/modules/pedidos/services/pedidos.service'
import { fetchObras } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'
import { hoyISO } from '@/services/fecha'
import { useBreakpoint } from '@/composables/useBreakpoint'
import { useAuthStore } from '@/stores/auth.store'

const { esMobile } = useBreakpoint()
const auth = useAuthStore()

// Mismo criterio de permiso que PedidosView.vue (auth.store.js): evita
// mostrar un botón "Confirmar" que la RPC del servidor va a rechazar igual.
// La franja diaria de mobile (más abajo) es la única que usa esto — la
// grilla de Desktop ya lo tenía sin gatear por rol desde siempre, no se
// tocó para no cambiar comportamiento existente ahí.
const puedeConfirmar = computed(() => auth.tienePermiso('pedidos', 'aprobar'))

const NOMBRES_DIA = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo']
const VARIANTE_ESTADO = {
  solicitado: 'default',
  confirmado: 'info',
  despachado: 'success',
  cancelado: 'danger',
}

const fechaRef = ref(new Date())
const pedidos = ref([])
const totales = ref({ rango: null, porObra: [], total: { asfaltoTn: 0, hormigonM3: 0 } })
const obras = ref([])
const formulas = ref([])
const cargando = ref(false)
const error = ref(null)

const obrasPorId = computed(() => Object.fromEntries(obras.value.map((o) => [o.id, o])))
const formulasPorId = computed(() => Object.fromEntries(formulas.value.map((f) => [f.id, f])))

// Formato de mejora visual (2026-09-01, pedido de Federico: "dejalo bien
// profesional"): cada día ahora trae número de fecha + nombre de mes
// separados (para el header de la columna) y un flag `esHoy` para resaltar
// la columna del día actual, mismo criterio que un calendario semanal
// estándar.
// Nombre a mostrar por destino — venta externa vs. obra propia vs. dato
// huérfano (fix 2026-09-03, bug real reportado por Federico: "Obra #null").
// La vista asumía que TODO pedido tiene obra_id, pero una venta externa
// (tipo_pedido='venta') nunca la tiene por diseño — mismo criterio que
// `destinoDe()` ya usa PedidosView/DespachosView, replicado acá (no existía
// un helper compartido para esto, son 3 formas ligeramente distintas de
// nombrar según qué objeto trae cada vista — no vale la pena forzar un solo
// helper transversal por 3 líneas de lógica).
function nombreDestinoPedido(p) {
  if (p.tipo_pedido === 'venta') return p.cliente_externo || 'Venta externa'
  if (p.obra_id) return obrasPorId.value[p.obra_id]?.nombre ?? `Obra #${p.obra_id}`
  // obra_id null y NO es venta -> dato huérfano real de la migración del
  // histórico legado (memory/pending.md, "Municipalidad Exaltación de la
  // Cruz" sin equivalente en flota_obras) — fallback legible en vez de
  // "Obra #null" literal, pero sigue señalando que falta resolverlo.
  return 'Obra sin asignar'
}

/** Los pedidos no tienen hora de entrega propia (solo `fecha_programada`,
 * columna date) — se muestra la hora de creación como referencia, mismo
 * dato que ya expone PedidoCard.vue con el ícono 🕐. */
function formatearHoraCreacion(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' })
}

function nombreDestinoTotal(t) {
  if (t.obraId) return obrasPorId.value[t.obraId]?.nombre ?? `Obra #${t.obraId}`
  return t.clienteExterno || 'Obra sin asignar'
}

const diasSemana = computed(() => {
  const { lunes } = obtenerRangoSemana(fechaRef.value)
  const hoy = hoyISO()
  return Array.from({ length: 7 }, (_, i) => {
    const fecha = new Date(lunes)
    fecha.setDate(lunes.getDate() + i)
    const iso = fecha.toISOString().slice(0, 10)
    const pedidosDia = pedidos.value.filter((p) => p.fecha_programada === iso)

    // Tilde + cantidades cuando el día cerró 100% despachado (2026-09-03,
    // réplica del legado pedida por Federico: "como tiene el sistema
    // viejo, abajo de la fecha"). asfaltoTn/hormigonM3 usan cantidad_despachada
    // (cantidadReal) — mismo criterio de "fuente de verdad" que el resto de
    // la app (memory/business-rules.md), no cantidad_solicitada.
    const todosDespachados = pedidosDia.length > 0 && pedidosDia.every((p) => p.estado === 'despachado')
    const asfaltoTnDia = pedidosDia
      .filter((p) => p.tipo !== 'hormigon' && p.estado === 'despachado')
      .reduce((acc, p) => acc + (Number(p.cantidad_despachada) || 0), 0)
    const hormigonM3Dia = pedidosDia
      .filter((p) => p.tipo === 'hormigon' && p.estado === 'despachado')
      .reduce((acc, p) => acc + (Number(p.cantidad_despachada) || 0), 0)

    return {
      etiqueta: NOMBRES_DIA[i],
      etiquetaCorta: NOMBRES_DIA[i].slice(0, 3),
      numeroDia: fecha.getDate(),
      mesLabel: fecha.toLocaleDateString('es-AR', { month: 'short' }).replace('.', ''),
      iso,
      esHoy: iso === hoy,
      esFinDeSemana: i >= 5,
      pedidos: pedidosDia,
      todosDespachados,
      asfaltoTnDia,
      hormigonM3Dia,
    }
  })
})

const rangoLabel = computed(() =>
  diasSemana.value.length ? `${diasSemana.value[0].iso} — ${diasSemana.value[6].iso}` : ''
)

// Franja diaria mobile (rediseño Mobile-First 2026-09-22, reemplaza la
// grilla apilada de 7 días que tenía mobile antes): día seleccionado en la
// franja horizontal de arriba, cuyo detalle se despliega abajo. Se
// recalcula cada vez que cambia la semana cargada — no tiene sentido
// arrastrar el ISO de la semana anterior a la nueva.
const diaSeleccionadoIso = ref(null)

const diaSeleccionado = computed(
  () => diasSemana.value.find((d) => d.iso === diaSeleccionadoIso.value) ?? diasSemana.value[0] ?? null
)

function seleccionarDiaPorDefecto() {
  const hoy = hoyISO()
  diaSeleccionadoIso.value = diasSemana.value.some((d) => d.iso === hoy) ? hoy : diasSemana.value[0]?.iso ?? null
}

async function cargarSemana() {
  cargando.value = true
  error.value = null
  try {
    const [listaPedidos, totalesSemana, listaObras, listaFormulas] = await Promise.all([
      fetchPedidosSemana(fechaRef.value),
      fetchTotalesSemana(fechaRef.value),
      fetchObras(),
      fetchFormulas({ soloActivas: true }),
    ])
    pedidos.value = listaPedidos
    totales.value = totalesSemana
    obras.value = listaObras
    formulas.value = listaFormulas
    seleccionarDiaPorDefecto()
  } catch (e) {
    error.value = e.message
  } finally {
    cargando.value = false
  }
}

function semanaAnterior() {
  const f = new Date(fechaRef.value)
  f.setDate(f.getDate() - 7)
  fechaRef.value = f
  cargarSemana()
}

function semanaSiguiente() {
  const f = new Date(fechaRef.value)
  f.setDate(f.getDate() + 7)
  fechaRef.value = f
  cargarSemana()
}

/** "Hoy" (rediseño Mobile-First 2026-09-22, pedido explícito de Federico:
 * volver rápido al día actual desde la franja) — salta directo a la semana
 * en curso, sea cual sea la que esté cargada, y selecciona el día de hoy. */
function irAHoySemana() {
  fechaRef.value = new Date()
  cargarSemana()
}

async function confirmar(pedido) {
  error.value = null
  try {
    await confirmarPedido(pedido.id)
    await cargarSemana()
  } catch (e) {
    error.value = e.message
  }
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
          <div class="grid grid-cols-2 gap-3">
            <VKpiCard label="Asfalto" :value="totales.total.asfaltoTn.toFixed(1)" unidad="tn" />
            <VKpiCard label="Hormigón" :value="totales.total.hormigonM3.toFixed(1)" unidad="m³" />
          </div>
        </VCard>

        <div v-if="totales.porObra.length" class="mb-6 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <VCard v-for="t in totales.porObra" :key="t.obraId ?? t.clienteExterno">
            <p class="mb-2 text-sm font-semibold text-text-soft">{{ nombreDestinoTotal(t) }}</p>
            <div class="grid grid-cols-2 gap-3">
              <VKpiCard label="Asfalto" :value="t.asfaltoTn.toFixed(1)" unidad="tn" />
              <VKpiCard label="Hormigón" :value="t.hormigonM3.toFixed(1)" unidad="m³" />
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
                  <span class="font-semibold text-vialtec">{{ p.cantidad_solicitada }} {{ p.tipo === 'hormigon' ? 'm³' : 'tn' }}</span>
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
            :class="dia.esFinDeSemana && !dia.esHoy ? 'bg-gray-50/60' : ''"
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
                <template v-if="dia.asfaltoTnDia > 0">{{ dia.asfaltoTnDia.toFixed(1) }} tn</template>
                <template v-if="dia.asfaltoTnDia > 0 && dia.hormigonM3Dia > 0"> · </template>
                <template v-if="dia.hormigonM3Dia > 0">{{ dia.hormigonM3Dia.toFixed(1) }} m³</template>
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
                  {{ p.cantidad_solicitada }} {{ p.tipo === 'hormigon' ? 'm³' : 'tn' }}
                </p>
                <div class="mt-1.5 flex items-center justify-between gap-1">
                  <VBadge :variant="VARIANTE_ESTADO[p.estado]">{{ p.estado }}</VBadge>
                  <VButton v-if="p.estado === 'solicitado'" variant="ghost" size="sm" @click="confirmar(p)">
                    Confirmar
                  </VButton>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </VSection>
  </div>
</template>
