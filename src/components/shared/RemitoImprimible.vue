<script setup>
// Remito imprimible ÚNICO y OFICIAL del sistema (2026-09-09, pedido
// explícito de Federico: "el que tiene que quedar es el de báscula, en los
// dos módulos deben ser idénticos"). Antes había DOS componentes distintos
// para lo que es el mismo documento fiscal — el modo "remito" de
// ValeImprimible.vue (Báscula) y el slip propio de DespachoImprimible.vue
// (Despachos) — con layouts diferentes. Se extrae acá el diseño real
// (réplica de una foto de un remito físico de VialTec S.A., 2026-09-01,
// reajustado a portrait 2026-09-07) como un componente 100% genérico, sin
// conocer `vale` ni `pedido` — cada módulo que lo usa (Báscula, Despachos,
// y el nuevo "Remito manual") le pasa los datos ya resueltos a su forma:
//   - Báscula: useBascula.js arma los props desde valeParaImprimir/
//     pedidoParaImprimir/rangoValesParaImprimir.
//   - Despachos: DespachoImprimible.vue (quedó como wrapper fino) arma los
//     props desde pedido/obraNombre/formulaNombre/cargas.
//   - Remito manual: DespachosView.vue arma los props directo desde el
//     registro de plantas_remitos_manuales (sin pedido/obra detrás).
//
// 2 HOJAS SEPARADAS (Original / Duplicado) a hoja completa — mismo mecanismo
// que el diseño original (`break-after-page` en la primera copia).

import { computed } from 'vue'
import logoVialtec from '@/assets/img/logo-vialtec.png'

const props = defineProps({
  numeroRemito: { type: [String, Number], default: null },
  fecha: { type: [String, Date], default: null },
  destino: { type: String, default: '' },
  // Cantidad ya formateada por el caller (ej. "55.80 tn", "40.4 tn", o '' si
  // no aplica — remito manual/en blanco sin cantidad predefinida).
  cantidadLabel: { type: String, default: '' },
  // Título de la celda "Detalle" (mezcla/fórmula, o la descripción libre de
  // un remito manual) y una sub-línea opcional en gris debajo (ej. "S/Vale
  // de báscula N° X al Y") — null la omite.
  detalleTitulo: { type: String, default: '' },
  detalleSubtexto: { type: String, default: null },
  // 'Propio' | 'Tercero' | null (null => "—", no se asume nada)
  transporte: { type: String, default: null },
  patente: { type: String, default: '' },
  transportista: { type: String, default: '' },
  lugarEntrega: { type: String, default: '' },
})

const EMPRESA = {
  nombre: 'VIAL-TEC S.A.',
  direccion1: 'Parque Industrial Ruta 6',
  direccion3: 'Cardales - Exaltación de la Cruz (2814)',
  telefono: '(011) 3986-3446',
  condicionIva: 'I.V.A.: Responsable Inscripto',
  cuit: '30-69530748-5',
  ieric: '87754-8',
  iibb: '901-904193-7',
  inicioActividad: '01/03/1998',
  deposito: 'Parque Industrial Ruta N°6',
}

const fechaLabel = computed(() => {
  if (!props.fecha) return '—'
  const d = typeof props.fecha === 'string' ? new Date(props.fecha.length <= 10 ? `${props.fecha}T00:00:00` : props.fecha) : props.fecha
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString('es-AR')
})
</script>

<template>
  <div>
    <div
      v-for="(_, i) in [0, 1]"
      :key="i"
      class="flex h-full w-full flex-col p-6"
      :class="i === 0 ? 'break-after-page' : ''"
    >
      <div class="mx-auto flex h-full w-full max-w-3xl flex-col border border-gray-400 p-8 text-base text-gray-800">
        <div class="mb-4 flex items-start justify-between border-b-2 border-gray-800 pb-3">
          <div>
            <img :src="logoVialtec" alt="VIAL-TEC S.A." class="h-16 w-auto" />
            <div class="mt-1.5 space-y-0 text-xs leading-tight text-gray-600">
              <p>{{ EMPRESA.direccion1 }} — {{ EMPRESA.direccion3 }}</p>
              <p>Tel.: {{ EMPRESA.telefono }} — {{ EMPRESA.condicionIva }}</p>
            </div>
          </div>
          <div class="text-right">
            <p class="text-xl font-bold uppercase tracking-wide">Remito {{ i === 0 ? 'original' : 'duplicado' }}</p>
            <div class="mt-1.5 space-y-0 text-xs leading-tight text-gray-600">
              <p>C.U.I.T.: {{ EMPRESA.cuit }}</p>
              <p>I.E.R.I.C.: {{ EMPRESA.ieric }}</p>
              <p>II.BB.CM: {{ EMPRESA.iibb }}</p>
              <p>Inicio de actividad: {{ EMPRESA.inicioActividad }}</p>
            </div>
          </div>
        </div>

        <div class="mb-3 grid grid-cols-2 gap-5">
          <div class="rounded border border-gray-400 px-4 py-2.5">
            <span class="text-[11px] font-semibold uppercase text-gray-500">Remito N°:</span>
            <span class="ml-1 font-semibold">{{ numeroRemito || '—' }}</span>
          </div>
          <div class="rounded border border-gray-400 px-4 py-2.5">
            <span class="text-[11px] font-semibold uppercase text-gray-500">Fecha:</span>
            <span class="ml-1 font-semibold">{{ fechaLabel }}</span>
          </div>
        </div>
        <div class="mb-3 rounded border border-gray-400 px-4 py-2.5">
          <span class="text-[11px] font-semibold uppercase text-gray-500">Desde:</span>
          <span class="ml-1 font-semibold">{{ EMPRESA.deposito }}</span>
        </div>
        <div class="mb-4 rounded border border-gray-400 px-4 py-2.5">
          <span class="text-[11px] font-semibold uppercase text-gray-500">Destino:</span>
          <span class="ml-1 font-semibold">{{ destino || '—' }}</span>
        </div>

        <table class="w-full table-fixed border border-gray-400 text-left">
          <thead>
            <tr class="border-b border-gray-400 bg-gray-50">
              <th class="w-32 border-r border-gray-400 px-4 py-2 text-xs uppercase tracking-wide text-gray-500">Cantidad</th>
              <th class="px-4 py-2 text-xs uppercase tracking-wide text-gray-500">Detalle</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td class="border-r border-gray-400 px-4 py-3 align-top text-lg font-bold">{{ cantidadLabel || '' }}</td>
              <td class="px-4 py-3 align-top">
                <p class="font-semibold">{{ detalleTitulo }}</p>
                <p v-if="detalleSubtexto" class="mt-1 text-xs text-gray-600">{{ detalleSubtexto }}</p>
              </td>
            </tr>
            <!-- Filas en blanco (como el papel real): deja lugar para anotaciones
                 a mano — mismo criterio para las 3 fuentes que usan este
                 componente (incluido el remito manual, que puede necesitar
                 completar acá el detalle a mano si no se cargó descripción). -->
            <tr v-for="n in 4" :key="n">
              <td class="border-r border-t border-gray-300 px-4 py-3">&nbsp;</td>
              <td class="border-t border-gray-300 px-4 py-3">&nbsp;</td>
            </tr>
          </tbody>
        </table>

        <div class="mt-4 space-y-1 text-sm">
          <p>
            <span class="font-semibold text-gray-500">Transporte:</span>
            {{ transporte || '—' }}
          </p>
          <p><span class="font-semibold text-gray-500">Patente:</span> {{ patente || '—' }}</p>
          <p><span class="font-semibold text-gray-500">Transportista:</span> {{ transportista || '—' }}</p>
          <p><span class="font-semibold text-gray-500">Lugar de entrega:</span> {{ lugarEntrega || '—' }}</p>
        </div>

        <div class="mt-auto grid grid-cols-2 gap-10 pt-6 text-sm text-gray-600">
          <div>
            <div class="h-24 border-b border-gray-400"></div>
            <p class="mt-1.5">Despacho</p>
            <p class="text-gray-400">{{ EMPRESA.nombre }} — Responsable de planta</p>
          </div>
          <div>
            <div class="h-24 border-b border-gray-400"></div>
            <p class="mt-1.5">Recibe conforme</p>
            <p class="text-gray-400">Aclaración: ________________________________</p>
          </div>
        </div>

        <div class="mt-3 border-t border-gray-300 pt-1.5 text-xs text-gray-500">
          <span class="font-semibold">Depósito:</span> {{ EMPRESA.deposito }}
        </div>
      </div>
    </div>
  </div>
</template>
