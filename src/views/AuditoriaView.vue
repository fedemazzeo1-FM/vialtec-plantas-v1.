<script setup>
// Auditoría (etapa 5, plan aprobado por Federico 2026-10-03): quién hizo
// cada acción. Solo lectura, solo admin (la base lo hace cumplir con una
// policy fija; el router y el menú solo evitan mostrar una pantalla vacía) y
// solo escritorio. Filtros en la URL, 50 por página, detalle antes/después y
// Excel de todo el filtro. Detalle legible en AuditoriaDetalle.vue. Template puro: la lógica vive en useAuditoria.js.
import VSection from '@/components/shared/VSection.vue'
import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VButton from '@/components/shared/VButton.vue'
import AuditoriaDetalle from '@/modules/auditoria/components/AuditoriaDetalle.vue'
import { ACCIONES_AUDITORIA } from '@/modules/auditoria/services/auditoria.service'
import {
  useAuditoria,
  etiquetaAccion,
  varianteAccion,
  formatearFechaHoraAuditoria,
} from '@/modules/auditoria/composables/useAuditoria'

const columnas = [
  { key: 'fecha_hora', label: 'Fecha y hora' },
  { key: 'usuario_nombre', label: 'Usuario' },
  { key: 'tipo_accion', label: 'Acción' },
  { key: 'entidad', label: 'Qué' },
  { key: 'entidad_label', label: 'Detalle' },
  { key: 'motivo', label: 'Motivo' },
  { key: 'acciones', label: '' },
]

const {
  filas,
  total,
  pagina,
  cargando,
  error,
  filtros,
  usuarios,
  modulos,
  etiquetaModulo,
  etiquetaEntidad,
  aplicarFiltros,
  limpiarFiltros,
  cambiarPagina,
  modalDetalleAbierto,
  registroDetalle,
  abrirDetalle,
  contextoDetalle,
  exportando,
  exportarExcel,
  iniciar,
  TAMANO_PAGINA_AUDITORIA,
} = useAuditoria()

iniciar()

const claseCampo =
  'mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none'
</script>

<template>
  <div>
    <VSection title="Auditoría">
      <div v-if="error" class="mb-4 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <VCard class="mb-4">
        <form class="grid grid-cols-2 gap-3 md:grid-cols-6" @submit.prevent="aplicarFiltros">
          <label class="text-sm text-text-mid">
            N° (pedido, vale o remito)
            <input v-model="filtros.q" type="text" placeholder="P-0230, 10188, 00049" :class="claseCampo" />
          </label>
          <label class="text-sm text-text-mid">
            Usuario
            <select v-model="filtros.usuario" :class="claseCampo">
              <option value="">Todos</option>
              <option v-for="u in usuarios" :key="u.email" :value="u.email">{{ u.label }}</option>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Módulo
            <select v-model="filtros.modulo" :class="claseCampo">
              <option value="">Todos</option>
              <option v-for="m in modulos" :key="m.id" :value="m.id">{{ m.label }}</option>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Acción
            <select v-model="filtros.accion" :class="claseCampo">
              <option value="">Todas</option>
              <option v-for="a in ACCIONES_AUDITORIA" :key="a.id" :value="a.id">{{ a.label }}</option>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Desde
            <input v-model="filtros.desde" type="date" :class="claseCampo" />
          </label>
          <label class="text-sm text-text-mid">
            Hasta
            <input v-model="filtros.hasta" type="date" :class="claseCampo" />
          </label>
          <div class="col-span-2 flex flex-wrap items-center gap-2 md:col-span-6">
            <VButton type="submit" size="sm">Filtrar</VButton>
            <VButton type="button" variant="ghost" size="sm" @click="limpiarFiltros">Limpiar</VButton>
            <span class="ml-auto text-xs text-text-soft">{{ total }} registro{{ total === 1 ? '' : 's' }}</span>
            <VButton type="button" variant="secondary" size="sm" :disabled="exportando || !total" @click="exportarExcel">
              {{ exportando ? 'Exportando…' : 'Exportar a Excel' }}
            </VButton>
          </div>
        </form>
      </VCard>

      <VCard>
        <p v-if="cargando" class="text-sm text-text-soft">Cargando…</p>
        <p v-else-if="!filas.length" class="text-sm text-text-soft">No hay registros que coincidan con el filtro.</p>
        <VTable
          v-else
          :columns="columnas"
          :rows="filas"
          :page="pagina"
          :page-size="TAMANO_PAGINA_AUDITORIA"
          :total="total"
          @update:page="cambiarPagina"
        >
          <template #cell-fecha_hora="{ row }">
            <span class="whitespace-nowrap">{{ formatearFechaHoraAuditoria(row.fecha_hora) }}</span>
          </template>
          <template #cell-usuario_nombre="{ row }">
            <p>{{ row.usuario_nombre }}</p>
            <p v-if="row.usuario_rol" class="text-xs capitalize text-text-soft">{{ row.usuario_rol }}</p>
          </template>
          <template #cell-tipo_accion="{ row }">
            <VBadge :variant="varianteAccion(row.tipo_accion)">{{ etiquetaAccion(row.tipo_accion) }}</VBadge>
          </template>
          <template #cell-entidad="{ row }">
            <p>{{ etiquetaEntidad[row.entidad] ?? row.entidad }}</p>
            <p class="text-xs text-text-soft">{{ etiquetaModulo[row.modulo] ?? row.modulo }}</p>
          </template>
          <template #cell-entidad_label="{ row }">
            {{ row.entidad_label || row.entidad_ref }}
          </template>
          <template #cell-motivo="{ row }">
            <span :class="row.motivo ? '' : 'text-text-soft'">{{ row.motivo || '—' }}</span>
          </template>
          <template #cell-acciones="{ row }">
            <VButton variant="secondary" size="sm" @click="abrirDetalle(row)">Ver</VButton>
          </template>
        </VTable>
      </VCard>
    </VSection>

    <VModal :open="modalDetalleAbierto" title="Detalle del registro" size="xl" @update:open="modalDetalleAbierto = $event">
      <div v-if="registroDetalle" class="space-y-4">
        <AuditoriaDetalle
          :row="registroDetalle"
          :contexto="contextoDetalle"
          :etiqueta-modulo="etiquetaModulo[registroDetalle.modulo] ?? ''"
          :etiqueta-entidad="etiquetaEntidad[registroDetalle.entidad] ?? ''"
        />
        <div class="flex justify-end">
          <VButton variant="secondary" @click="modalDetalleAbierto = false">Cerrar</VButton>
        </div>
      </div>
    </VModal>
  </div>
</template>
