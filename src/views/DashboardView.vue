<script setup>
// Home/Dashboard: "Panel de control" puro (réplica del legado, ver
// useDashboardHome.js) — KPIs rápidos y estado global, sin tablas ni
// secciones analíticas extensas (pedido explícito de Federico, 2026-09-04:
// se sacaron "Analítica de proveedores" y "Historial detallado de despachos
// por camión", que vivían acá como valor agregado propio de v2 — quedan
// disponibles en Stock → "Analítica de proveedores" y en Despachos → "Ver
// detalle de cargas" respectivamente, no se perdió la funcionalidad, solo
// se sacó de Home). Toda la persistencia pasa por services — este
// componente no llama a Supabase directamente (memory/conventions.md).

import { ref } from 'vue'
import { RouterLink } from 'vue-router'
import VCard from '@/components/shared/VCard.vue'
import VSection from '@/components/shared/VSection.vue'
import VSemaforo from '@/components/shared/VSemaforo.vue'
import { useAlertaStockSemana } from '@/modules/dashboard/composables/useAlertaStockSemana'
import { useDashboardHome } from '@/modules/dashboard/composables/useDashboardHome'

const error = ref(null)

// ---------------------------------------------------------------------------
// Panel de control (2026-09-04, réplica del legado — relevado en vivo
// contra produccion.vialtec.app, memory/pending.md)
// ---------------------------------------------------------------------------
const {
  encabezadoFecha,
  encabezadoRangoSemana,
  cargandoKpis,
  resumenSemana,
  stockActual,
  materialesAjustados,
  materialesCriticos,
  cargandoProximos,
  filasProximos,
  cargandoConsumo,
  materialesConsumo,
  materialSeleccionado,
  filasConsumo,
  iniciar: iniciarPanelControl,
} = useDashboardHome()

// ---------------------------------------------------------------------------
// Alerta de stock proyectado (semana en curso) — banner 🔴/🟡, sin bloqueo
// duro (memory/business-rules.md, memory/modules-status.md fila #1).
// ---------------------------------------------------------------------------
const { cargando: cargandoAlertaStock, alertas: alertasStock, cargar: cargarAlertaStock } = useAlertaStockSemana()

cargarAlertaStock()
iniciarPanelControl()
</script>

<template>
  <div>
    <VSection>
      <div class="mb-4">
        <h2 class="text-lg font-bold text-text">Panel de control</h2>
        <p class="text-sm capitalize text-text-soft">{{ encabezadoFecha }} · Semana del {{ encabezadoRangoSemana }}</p>
      </div>

      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <!-- Alerta de stock proyectado (semana en curso) — solo se muestra si
           hay algo en amarillo/rojo, no agrega ruido si está todo verde
           (memory/business-rules.md: alerta sin bloqueo duro). -->
      <div
        v-if="!cargandoAlertaStock && alertasStock.length"
        class="mb-4 rounded-lg border border-warning/30 bg-warning-light px-4 py-3"
      >
        <p class="mb-2 text-sm font-semibold text-text-strong">
          ⚠️ Stock proyectado ajustado para los pedidos confirmados de esta semana
        </p>
        <ul class="space-y-1">
          <li v-for="a in alertasStock" :key="a.nombre" class="flex items-center gap-2 text-sm text-text-mid">
            <VSemaforo :estado="a.estadoProyectado" />
            <span class="font-medium">{{ a.nombre }}</span>
            <span class="text-text-soft">
              — actual {{ a.stockActualTn.toFixed(1) }} tn, consumo comprometido
              {{ a.consumoSemanaTn.toFixed(1) }} tn → proyectado
              <span :class="a.estadoProyectado === 'rojo' ? 'font-semibold text-danger' : 'font-semibold text-warning'">
                {{ a.stockProyectadoTn.toFixed(1) }} tn
              </span>
            </span>
          </li>
        </ul>
      </div>

      <!-- 5 KPI (réplica exacta del legado — relevado en vivo 2026-09-04,
           memory/pending.md): franja superior de color por tarjeta, mismo
           criterio semántico que estados.js (Pedidos)/Stock. -->
      <p v-if="cargandoKpis" class="mb-4 text-sm text-text-soft">Cargando…</p>
      <div v-else class="mb-6 grid grid-cols-2 gap-3 md:grid-cols-5">
        <div class="rounded-xl border-t-4 border-t-vialtec bg-white p-4 shadow-sm">
          <p class="text-[11px] font-semibold uppercase tracking-wide text-text-soft">Pedidos activos</p>
          <p class="mt-2 text-2xl font-extrabold text-vialtec">{{ resumenSemana.pedidosActivos }}</p>
          <p class="text-xs text-text-soft">en curso</p>
        </div>
        <div class="rounded-xl border-t-4 border-t-info bg-white p-4 shadow-sm">
          <p class="text-[11px] font-semibold uppercase tracking-wide text-text-soft">Confirmados</p>
          <p class="mt-2 text-2xl font-extrabold text-info">{{ resumenSemana.confirmados }}</p>
          <p class="text-xs text-text-soft">{{ resumenSemana.confirmados }} para despachar</p>
        </div>
        <div class="rounded-xl border-t-4 border-t-success bg-white p-4 shadow-sm">
          <p class="text-[11px] font-semibold uppercase tracking-wide text-text-soft">Despachos esta semana</p>
          <p class="mt-2 text-2xl font-extrabold text-success">{{ resumenSemana.despachos.cantidad }}</p>
          <p class="text-xs text-text-soft">
            {{ resumenSemana.despachos.asfaltoTn.toFixed(1) }} tn · {{ resumenSemana.despachos.hormigonM3.toFixed(1) }} m³
          </p>
        </div>
        <div class="rounded-xl border-t-4 border-t-warning bg-white p-4 shadow-sm">
          <p class="text-[11px] font-semibold uppercase tracking-wide text-text-soft">Ajustados</p>
          <p class="mt-2 text-2xl font-extrabold text-warning">{{ materialesAjustados }}</p>
          <p class="text-xs text-text-soft">stock bajo</p>
        </div>
        <div class="rounded-xl border-t-4 border-t-danger bg-white p-4 shadow-sm">
          <p class="text-[11px] font-semibold uppercase tracking-wide text-text-soft">Críticos</p>
          <p class="mt-2 text-2xl font-extrabold text-danger">{{ materialesCriticos }}</p>
          <p class="text-xs text-text-soft">stock insuficiente</p>
        </div>
      </div>

      <!-- Consumo de material (8 semanas) + Próximos despachos -->
      <div class="mb-6 grid grid-cols-1 gap-4 lg:grid-cols-[1fr_360px]">
        <VCard>
          <h3 class="mb-3 text-sm font-bold text-text">Consumo de material</h3>
          <p v-if="cargandoConsumo" class="text-sm text-text-soft">Cargando…</p>
          <template v-else-if="materialesConsumo.length">
            <select
              v-model="materialSeleccionado"
              class="mb-3 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            >
              <option v-for="m in materialesConsumo" :key="m" :value="m">{{ m }}</option>
            </select>
            <p class="mb-1 text-xs font-semibold uppercase tracking-wide text-text-soft">Últimas 8 semanas</p>
            <ul class="divide-y divide-border">
              <li v-for="fila in filasConsumo" :key="fila.semana" class="flex items-center justify-between py-1.5 text-sm">
                <span class="text-text-soft">{{ fila.semana }}</span>
                <span class="font-medium text-text">{{ fila.valorLabel }}</span>
              </li>
            </ul>
          </template>
          <p v-else class="text-sm text-text-soft">Sin despachos en las últimas 8 semanas para graficar consumo.</p>
        </VCard>

        <VCard>
          <div class="flex items-center justify-between">
            <h3 class="text-sm font-bold text-text">Próximos despachos</h3>
            <span class="rounded-full bg-vialtec/10 px-2 py-0.5 text-xs font-bold text-vialtec">{{ filasProximos.length }}</span>
          </div>
          <p class="text-xs text-text-soft">Todos los pedidos confirmados</p>
          <p v-if="cargandoProximos" class="mt-3 text-sm text-text-soft">Cargando…</p>
          <template v-else>
            <div
              v-for="p in filasProximos"
              :key="p.id"
              class="flex items-start gap-3 border-b border-border py-3 last:border-0"
            >
              <div
                class="flex w-12 shrink-0 flex-col items-center rounded-lg px-2 py-1"
                :class="{
                  'bg-danger-light text-danger': p.etiquetaVariante === 'danger',
                  'bg-warning-light text-warning': p.etiquetaVariante === 'warning',
                  'bg-gray-50 text-text-soft': p.etiquetaVariante === 'default',
                }"
              >
                <span class="text-sm font-bold">{{ p.diaCorto }}</span>
                <span class="text-[10px] uppercase">{{ p.mesCorto }}</span>
              </div>
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-bold text-text">{{ p.destino }}</p>
                <p class="text-xs text-text-soft">{{ p.formulaNombre }} · {{ p.cantidadLabel }}</p>
              </div>
              <span
                v-if="p.etiqueta"
                class="shrink-0 text-xs font-bold"
                :class="p.etiquetaVariante === 'danger' ? 'text-danger' : 'text-warning'"
              >
                {{ p.etiqueta }}
              </span>
            </div>
            <p v-if="!filasProximos.length" class="py-4 text-center text-sm text-text-soft">
              No hay despachos confirmados próximos.
            </p>
          </template>
          <RouterLink
            to="/plan-semanal"
            class="mt-3 block rounded-lg bg-gray-50 py-2 text-center text-sm font-semibold text-vialtec hover:bg-gray-100"
          >
            Ver plan semanal →
          </RouterLink>
        </VCard>
      </div>

      <!-- Stock actual de insumos -->
      <VCard>
        <div class="mb-3 flex items-center justify-between">
          <h3 class="text-sm font-bold text-text">Stock actual de insumos</h3>
          <RouterLink to="/stock" class="text-sm font-semibold text-vialtec hover:underline">Ver detalle →</RouterLink>
        </div>
        <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div v-for="m in stockActual" :key="m.id" class="rounded-lg border border-border p-3">
            <p class="truncate text-[11px] font-semibold uppercase tracking-wide text-text-soft">{{ m.nombre }}</p>
            <p
              class="mt-1 text-lg font-bold"
              :class="{ 'text-danger': m.estado === 'rojo', 'text-warning': m.estado === 'amarillo', 'text-success': m.estado === 'verde' }"
            >
              {{ (m.cantidadKg / 1000).toFixed(2) }} t
            </p>
          </div>
        </div>
      </VCard>
    </VSection>
  </div>
</template>
