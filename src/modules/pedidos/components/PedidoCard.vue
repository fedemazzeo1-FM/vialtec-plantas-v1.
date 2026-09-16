<script setup>
// Card de pedido — rediseño 2026-09-04 (pedido explícito de Federico:
// "replica exactamente la vista de Pedidos" del legado, relevado en vivo
// contra produccion.vialtec.app, ver memory/pending.md). Reemplaza la fila
// de VTable que tenía PedidosView.vue: mismo contenido, layout de card
// grande. Vive en su propio componente (no inline en PedidosView.vue) para
// no inflar esa vista — es puramente presentacional, todas las acciones
// disparan eventos hacia arriba, ninguna lógica de negocio ni llamada a
// Supabase acá (memory/conventions.md).
//
// Estructura confirmada en vivo (Etapa 1 + Etapa 3 del relevamiento, y
// re-confirmada en vivo 2026-09-04): badge de estado + destino (título),
// fórmula · cantidad (con "→ real: X" si ya despachó), fila de meta
// (📅 fecha programada · 👤 encargado · 🕐 fecha de creación · "Ver
// historial"), caja de observaciones (📝) y caja de motivo (⚠, ej. el
// motivo de cancelación) si están presentes — las dos pueden convivir.
// Acciones a la derecha según estado, igual que el legado: solicitado ->
// Confirmar; confirmado -> Despachar/Registrar carga; los dos además
// Editar/Postergar/Cancelar; despachado/cancelado -> solo "Ver historial".
import VBadge from '@/components/shared/VBadge.vue'
import VButton from '@/components/shared/VButton.vue'
import { computed } from 'vue'
import {
  VARIANTE_ESTADO,
  COLOR_BORDE_ESTADO,
  ESTADOS_EDITABLES,
  ESTADOS_CONFIRMABLES,
  ESTADOS_POSTERGABLES,
  ESTADOS_CANCELABLES,
  ESTADOS_ARCHIVABLES,
} from '@/modules/pedidos/estados'

const props = defineProps({
  pedido: { type: Object, required: true },
  // RBAC (2026-09-16, pedido de Federico): Confirmar/Despachar son acciones
  // sensibles (cierran o mueven stock) — el permiso real vive en las RPC del
  // servidor (confirmar_pedido/registrar_carga_asfalto/registrar_carga_hormigon),
  // esto solo evita mostrar un botón que el servidor va a rechazar igual.
  // Se calculan en PedidosView.vue (auth.store.js), no acá — este componente
  // sigue siendo puramente presentacional (memory/conventions.md).
  puedeConfirmar: { type: Boolean, default: false },
  puedeDespacharAsfalto: { type: Boolean, default: false },
  puedeDespacharHormigon: { type: Boolean, default: false },
  // Editar/Postergar por creador (2026-09-17, migración 41): admin/plantista
  // (puedeGestionarGlobal) ven estos botones en cualquier pedido; el resto
  // solo si pedido.creado_por coincide con su propio email (usuarioActual) —
  // mismo criterio que ya valida actualizar_pedido()/postergar_pedido() del
  // lado del servidor, esto solo evita mostrar un botón que el servidor va
  // a rechazar igual. Pedidos migrados/históricos sin creado_por quedan
  // gestionables solo por admin/plantista (comportamiento ya esperado).
  puedeGestionarGlobal: { type: Boolean, default: false },
  usuarioActual: { type: String, default: null },
})

const puedeGestionarEstePedido = computed(
  () => props.puedeGestionarGlobal || (!!props.usuarioActual && props.pedido.creado_por === props.usuarioActual)
)

defineEmits(['confirmar', 'despachar', 'registrar-carga', 'editar', 'postergar', 'cancelar', 'archivar', 'ver-historial'])

const unidad = props.pedido.tipo === 'hormigon' ? 'm³' : 'tn'

/** 'Mar 1 de septiembre' — mismo formato que el legado. `fecha` es 'YYYY-MM-DD'
 * (columna date): se parsea por componentes, no con `new Date(string)` a
 * secas, para no correr el día por interpretación UTC (mismo motivo que
 * src/services/fecha.js). */
function formatearFechaLarga(fecha) {
  if (!fecha) return '—'
  const [y, m, d] = fecha.split('-').map(Number)
  return new Date(y, m - 1, d).toLocaleDateString('es-AR', { weekday: 'short', day: 'numeric', month: 'long' })
}

function formatearFechaHoraCreacion(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('es-AR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}
</script>

<template>
  <div class="rounded-xl border border-t-4 border-border bg-white p-4 shadow-sm" :class="COLOR_BORDE_ESTADO[pedido.estado]">
    <div class="flex flex-wrap items-start justify-between gap-3">
      <div class="min-w-0">
        <div class="flex flex-wrap items-center gap-2">
          <VBadge :variant="VARIANTE_ESTADO[pedido.estado]">{{ pedido.estado }}</VBadge>
          <h3 class="truncate text-base font-bold text-text">{{ pedido.destino }}</h3>
          <span v-if="pedido.archivado" class="text-xs text-text-soft">(archivado)</span>
        </div>
        <p class="mt-1 text-sm text-text-mid">
          {{ pedido.formulaNombre }} ·
          <span class="font-bold text-vialtec">{{ pedido.cantidad_solicitada }} {{ unidad }}</span>
          <span v-if="pedido.cantidad_despachada != null" class="text-text-soft">
            → real: {{ pedido.cantidad_despachada }} {{ unidad }}
          </span>
        </p>
      </div>

      <!-- Acción principal (2026-09-04, réplica del legado: botón grande
           arriba a la derecha, distinto del resto de las acciones). -->
      <VButton
        v-if="ESTADOS_CONFIRMABLES.includes(pedido.estado) && puedeConfirmar"
        size="sm"
        @click="$emit('confirmar', pedido)"
      >
        Confirmar
      </VButton>
      <VButton
        v-else-if="pedido.estado === 'confirmado' && pedido.tipo === 'asfalto' && puedeDespacharAsfalto"
        variant="success"
        size="sm"
        @click="$emit('despachar', pedido)"
      >
        ↑ Despachar
      </VButton>
      <VButton
        v-else-if="pedido.estado === 'confirmado' && pedido.tipo === 'hormigon' && puedeDespacharHormigon"
        variant="success"
        size="sm"
        @click="$emit('registrar-carga', pedido)"
      >
        ↑ Despachar
      </VButton>
    </div>

    <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-text-soft">
      <span>📅 {{ formatearFechaLarga(pedido.fecha_programada) }}</span>
      <span v-if="pedido.encargado">👤 {{ pedido.encargado }}</span>
      <span>🕐 {{ formatearFechaHoraCreacion(pedido.created_at) }}</span>
      <button type="button" class="font-semibold text-vialtec hover:underline" @click="$emit('ver-historial', pedido)">
        Ver historial
      </button>

      <!-- Resto de acciones (2026-09-04, réplica del legado: agrupadas en la
           misma fila que "Ver historial", a la derecha). -->
      <span class="ml-auto flex flex-wrap gap-1.5">
        <VButton
          v-if="ESTADOS_EDITABLES.includes(pedido.estado) && puedeGestionarEstePedido"
          variant="secondary"
          size="sm"
          @click="$emit('editar', pedido)"
        >
          Editar
        </VButton>
        <VButton
          v-if="ESTADOS_POSTERGABLES.includes(pedido.estado) && puedeGestionarEstePedido"
          variant="secondary"
          size="sm"
          @click="$emit('postergar', pedido)"
        >
          Postergar
        </VButton>
        <VButton v-if="ESTADOS_CANCELABLES.includes(pedido.estado)" variant="danger" size="sm" @click="$emit('cancelar', pedido)">
          ✕
        </VButton>
        <VButton
          v-if="ESTADOS_ARCHIVABLES.includes(pedido.estado) && !pedido.archivado"
          variant="secondary"
          size="sm"
          @click="$emit('archivar', pedido)"
        >
          Archivar
        </VButton>
      </span>
    </div>

    <!-- Observaciones (📝, cualquier estado) y motivo (⚠, ej. cancelación) —
         confirmado en vivo que pueden convivir las dos, no son excluyentes. -->
    <p v-if="pedido.observaciones" class="mt-2 rounded-lg bg-gray-50 px-3 py-2 text-sm text-text-mid">
      📝 {{ pedido.observaciones }}
    </p>
    <p v-if="pedido.motivo" class="mt-2 rounded-lg bg-vialtec/5 px-3 py-2 text-sm text-vialtec">
      ⚠ {{ pedido.motivo }}
    </p>
  </div>
</template>
