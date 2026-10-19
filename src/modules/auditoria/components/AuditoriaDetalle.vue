<script setup>
// Detalle de una fila de auditoría para un usuario no técnico (2026-10-19,
// mismo criterio que flota): frase arriba, motivo destacado, solo lo que
// cambió (o los datos principales en altas y bajas) y, plegado, "Ver datos
// técnicos" con la fila completa tal como se guardó (lo que mostraba esta
// pantalla antes). La lógica vive en auditoria-presentacion.js.
import { computed } from 'vue'
import VBadge from '@/components/shared/VBadge.vue'
import { presentarRegistro } from '@/modules/auditoria/services/auditoria-presentacion'
import {
  etiquetaAccion,
  varianteAccion,
  formatearFechaHoraAuditoria,
  filasDetalleAuditoria,
} from '@/modules/auditoria/composables/useAuditoria'

const props = defineProps({
  row: { type: Object, required: true },
  contexto: { type: Object, default: () => ({}) }, // { nombres, catalogos } (los trae la pantalla una vez)
  etiquetaModulo: { type: String, default: '' },
  etiquetaEntidad: { type: String, default: '' },
})

const detalle = computed(() => presentarRegistro(props.row, props.contexto))
const filasTecnicas = computed(() => filasDetalleAuditoria(props.row))
</script>

<template>
  <div class="space-y-4 text-sm">
    <div>
      <p class="font-semibold text-text">{{ detalle.frase }}</p>
      <p class="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-text-soft">
        <VBadge :variant="varianteAccion(row.tipo_accion)">{{ etiquetaAccion(row.tipo_accion) }}</VBadge>
        <span>{{ formatearFechaHoraAuditoria(row.fecha_hora) }}</span>
        <span v-if="row.usuario_rol" class="capitalize">· {{ row.usuario_rol }}</span>
        <span>· {{ etiquetaModulo || row.modulo }} / {{ etiquetaEntidad || row.entidad }}</span>
      </p>
    </div>

    <p v-if="detalle.motivo" class="rounded-lg border border-warning/30 bg-warning-light px-3 py-2 text-text">
      <span class="font-semibold">Motivo:</span> {{ detalle.motivo }}
    </p>

    <table v-if="detalle.cambios.length" class="w-full text-left">
      <tbody>
        <tr v-for="(c, i) in detalle.cambios" :key="i" class="border-b border-border align-top last:border-0">
          <td class="w-48 py-1.5 pr-3 text-text-mid">{{ c.campo }}</td>
          <td class="py-1.5">
            <template v-if="c.antes != null">
              <span class="text-text-soft line-through decoration-1">{{ c.antes }}</span>
              <span class="mx-2 text-text-soft">→</span>
            </template>
            <span class="font-semibold text-text">{{ c.despues }}</span>
          </td>
        </tr>
      </tbody>
    </table>

    <table v-if="detalle.datos.length" class="w-full text-left">
      <tbody>
        <tr v-for="(d, i) in detalle.datos" :key="i" class="border-b border-border align-top last:border-0">
          <td class="w-48 py-1.5 pr-3 text-text-mid">{{ d.campo }}</td>
          <td class="py-1.5 text-text">{{ d.valor }}</td>
        </tr>
      </tbody>
    </table>

    <p v-if="detalle.nota" class="text-text-soft">{{ detalle.nota }}</p>

    <details class="rounded-lg border border-border">
      <summary class="cursor-pointer select-none px-3 py-2 text-xs font-semibold uppercase tracking-wide text-text-soft">
        Ver datos técnicos
      </summary>
      <div class="space-y-3 border-t border-border p-3">
        <div class="grid grid-cols-1 gap-x-6 gap-y-1 text-xs text-text-mid md:grid-cols-2">
          <p><span class="font-semibold">Usuario:</span> {{ row.usuario_email || '—' }}</p>
          <p><span class="font-semibold">Referencia:</span> {{ row.entidad_ref || '—' }}</p>
          <p class="md:col-span-2"><span class="font-semibold">Etiqueta:</span> {{ row.entidad_label || '—' }}</p>
          <p class="md:col-span-2"><span class="font-semibold">Dispositivo:</span> {{ row.dispositivo || '—' }}</p>
        </div>
        <table v-if="filasTecnicas.length" class="w-full text-left text-xs">
          <thead>
            <tr class="border-b border-border uppercase tracking-wide text-text-soft">
              <th class="py-2 pr-3 font-semibold">Campo</th>
              <th class="py-2 pr-3 font-semibold">Antes</th>
              <th class="py-2 font-semibold">Después</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="f in filasTecnicas" :key="f.clave" class="border-b border-border align-top last:border-0">
              <td class="py-1.5 pr-3 font-mono text-text-mid">{{ f.clave }}</td>
              <td class="break-all py-1.5 pr-3 text-text-soft">{{ f.antes }}</td>
              <td class="break-all py-1.5 text-text">{{ f.despues }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else class="text-xs text-text-soft">Este registro no guarda valores antes/después.</p>
      </div>
    </details>
  </div>
</template>
