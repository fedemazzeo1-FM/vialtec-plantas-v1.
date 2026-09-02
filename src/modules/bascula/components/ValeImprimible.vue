<script setup>
// Documento imprimible compartido por "Imprimir vale" e "Imprimir remito".
// El wrapper .imprimible (definido en src/assets/main.css) es lo que hace que
// solo esto se vea al imprimir, ocultando el resto de la página/modal.
//
// Modo "vale": formato A4 landscape, DOS copias por página (planta + chofer)
// — Logica sis. plantas v1.rtf §2.4: "formato A4 landscape, dos copias por
// página (planta y chofer)". @page va en src/assets/main.css.
//
// Modo "remito" (rediseñado 2026-09-01 contra una foto real de un remito de
// VialTec S.A. que compartió Federico): reproduce el remito fiscal en papel
// — membrete con datos impositivos, N° de remito, Desde/Destino, tabla
// Cantidad/Detalle con el rango de vales de báscula correlativos que
// respaldan el acumulado del día, Transporte/Patente/Transportista/Lugar de
// entrega, y las dos firmas (Despacho / Recibe conforme). Una sola copia
// (la spec no pide duplicado ahí, a diferencia del vale).
//
// Los datos impositivos/dirección de EMPRESA son fijos (mismo domicilio y
// CUIT en cualquier remito) — si alguna vez cambian, se actualizan acá, no
// hay ninguna tabla para esto (es membrete, no dato operativo).

import { computed } from 'vue'
import { formatearNumeroVale } from '@/modules/bascula/services/bascula.service'
// Logo real (2026-09-01, provisto por Federico) — reemplaza el mockup en
// CSS/texto que se usaba antes (no había forma de bajar el archivo a disco
// en sesiones previas, ver memory/modules-status.md).
import logoVialtec from '@/assets/img/logo-vialtec.png'

const props = defineProps({
  vale: { type: Object, required: true },
  obraNombre: { type: String, default: '' },
  mezclaNombre: { type: String, default: '' },
  modo: { type: String, required: true }, // 'vale' | 'remito'
  acumuladoTn: { type: Number, default: null },
  // Solo se usan en modo 'remito':
  pedido: { type: Object, default: null },
  rangoVales: { type: Object, default: () => ({ valeDesde: null, valeHasta: null, cantidadVales: 0 }) },
  patentes: { type: Array, default: () => [] },
})

const EMPRESA = {
  nombre: 'VIAL-TEC S.A.',
  direccion1: 'Parque Industrial Ruta 6',
  direccion2: 'Ruta Prov. 6 Km 180',
  direccion3: 'Cardales - Exaltación de la Cruz (2814)',
  telefono: '(011) 3986-3446',
  condicionIva: 'I.V.A.: Responsable Inscripto',
  cuit: '30-69530748-5',
  ieric: '87754-8',
  iibb: '901-904193-7',
  inicioActividad: '01/03/1998',
  deposito: 'Parque Industrial Ruta N°6',
}

function formatFecha(iso) {
  const d = new Date(iso)
  return {
    fecha: d.toLocaleDateString('es-AR'),
    hora: d.toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' }),
  }
}

// Cada copia del vale lleva UNA sola firma, distinta según a quién le queda
// esa copia (ajuste pedido por Federico, 2026-08-28) — no las dos firmas
// genéricas de antes repetidas en ambas copias.
const copiasVale = [
  { titulo: 'Copia planta', firma: 'Firma del Balancero Responsable' },
  { titulo: 'Copia chofer', firma: 'Firma del Chofer que Retira' },
]

// Transporte propio/tercero (columna "Transporte" del remito real): se
// deduce de plantas_patentes.es_externa buscando la patente del vale — el
// vale en sí no guarda esta distinción. Sin match (patente no cargada en el
// catálogo), queda sin dato en vez de asumir "Propio" por default.
const esTransportePropio = computed(() => {
  const patente = props.patentes.find((p) => p.patente === props.vale?.patente)
  return patente ? !patente.es_externa : null
})

const detalleMezcla = computed(() => (props.mezclaNombre || 'Mezcla asfáltica').toUpperCase())
</script>

<template>
  <!-- ============================== MODO VALE ============================== -->
  <div v-if="modo === 'vale'" class="grid grid-cols-1 gap-4 print:grid-cols-2">
    <div v-for="copia in copiasVale" :key="copia.titulo" class="border border-gray-300 p-6 text-sm text-gray-800">
      <div class="mb-4 flex items-start justify-between border-b border-gray-300 pb-3">
        <img :src="logoVialtec" alt="VIAL-TEC S.A." class="h-12 w-auto" />
        <div class="text-right">
          <p class="text-lg font-bold">Vale de pesaje</p>
          <p class="text-gray-500">N° {{ formatearNumeroVale(vale.numero_vale) }}</p>
          <p class="text-xs font-semibold uppercase tracking-wide text-gray-400">{{ copia.titulo }}</p>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-x-6 gap-y-2">
        <p><span class="text-gray-500">Fecha:</span> {{ formatFecha(vale.fecha_pesada).fecha }}</p>
        <p><span class="text-gray-500">Hora:</span> {{ formatFecha(vale.fecha_pesada).hora }}</p>
        <p><span class="text-gray-500">Obra:</span> {{ obraNombre || '—' }}</p>
        <p><span class="text-gray-500">Mezcla:</span> {{ mezclaNombre || '—' }}</p>
        <p><span class="text-gray-500">Patente:</span> {{ vale.patente || '—' }}</p>
        <p><span class="text-gray-500">Chofer:</span> {{ vale.chofer || '—' }}</p>
        <p><span class="text-gray-500">Peso bruto:</span> {{ vale.peso_bruto }} {{ vale.unidad }}</p>
        <p><span class="text-gray-500">Tara:</span> {{ vale.tara }} {{ vale.unidad }}</p>
        <p><span class="text-gray-500">Peso neto:</span> {{ vale.peso_neto }} {{ vale.unidad }}</p>
        <p v-if="vale.temperatura != null"><span class="text-gray-500">Temperatura:</span> {{ vale.temperatura }} °C</p>
      </div>

      <div class="mt-4 border-t border-gray-300 pt-3">
        <p class="text-base font-semibold">Acumulado: {{ acumuladoTn != null ? acumuladoTn.toFixed(2) : '—' }} tn</p>
      </div>

      <div class="mt-10 text-xs text-gray-500">
        <p>{{ copia.firma }}: ______________________</p>
      </div>
    </div>
  </div>

  <!-- ============================= MODO REMITO ============================= -->
  <!-- Réplica del remito físico de VialTec S.A. (foto real, 2026-09-01): se
       imprime cuando termina el acumulado del pedido/obra del día — el
       balancero corta este remito como respaldo de todos los vales de
       báscula correlativos que se pesaron para llegar a ese acumulado. -->
  <div v-else class="border border-gray-400 p-6 text-sm text-gray-800">
    <div class="mb-4 flex items-start justify-between border-b-2 border-gray-800 pb-3">
      <div>
        <img :src="logoVialtec" alt="VIAL-TEC S.A." class="h-14 w-auto" />
        <div class="mt-2 space-y-0.5 text-[11px] leading-tight text-gray-600">
          <p>{{ EMPRESA.direccion1 }}</p>
          <p>{{ EMPRESA.direccion2 }}</p>
          <p>{{ EMPRESA.direccion3 }}</p>
          <p>Tel.: {{ EMPRESA.telefono }}</p>
          <p>{{ EMPRESA.condicionIva }}</p>
        </div>
      </div>
      <div class="text-right">
        <p class="text-base font-bold uppercase tracking-wide">Remito</p>
        <div class="mt-1 text-[11px] leading-relaxed text-gray-600">
          <p>C.U.I.T.: {{ EMPRESA.cuit }}</p>
          <p>I.E.R.I.C.: {{ EMPRESA.ieric }}</p>
          <p>II.BB.CM: {{ EMPRESA.iibb }}</p>
          <p>Inicio Act.: {{ EMPRESA.inicioActividad }}</p>
        </div>
      </div>
    </div>

    <div class="mb-3 grid grid-cols-2 gap-4">
      <div class="rounded border border-gray-300 px-3 py-1.5">
        <p class="text-[10px] uppercase text-gray-400">Remito N°</p>
        <p class="font-semibold">{{ pedido?.nro_remito_global || '—' }}</p>
      </div>
      <div class="rounded border border-gray-300 px-3 py-1.5">
        <p class="text-[10px] uppercase text-gray-400">Fecha</p>
        <p class="font-semibold">{{ formatFecha(vale.fecha_pesada).fecha }}</p>
      </div>
    </div>

    <div class="mb-3 space-y-0.5">
      <p><span class="font-semibold text-gray-500">Desde:</span> {{ EMPRESA.deposito }}</p>
      <p><span class="font-semibold text-gray-500">Destino:</span> {{ obraNombre || '—' }}</p>
    </div>

    <table class="w-full table-fixed border border-gray-400 text-left">
      <thead>
        <tr class="border-b border-gray-400 bg-gray-50">
          <th class="w-32 border-r border-gray-400 px-2 py-1 text-xs uppercase tracking-wide text-gray-500">Cantidad</th>
          <th class="px-2 py-1 text-xs uppercase tracking-wide text-gray-500">Detalle</th>
        </tr>
      </thead>
      <tbody>
        <tr class="border-b border-gray-300">
          <td class="border-r border-gray-400 px-2 py-2 align-top font-semibold">
            {{ acumuladoTn != null ? acumuladoTn.toFixed(2) : '—' }} tn
          </td>
          <td class="px-2 py-2 align-top">
            <p>{{ detalleMezcla }}</p>
            <p v-if="rangoVales?.valeDesde != null" class="mt-2 text-xs text-gray-600">
              S/Vale de báscula N° {{ formatearNumeroVale(rangoVales.valeDesde) }}
              <template v-if="rangoVales.valeHasta !== rangoVales.valeDesde">
                al {{ formatearNumeroVale(rangoVales.valeHasta) }}
              </template>
              (correlativos{{ rangoVales.cantidadVales ? ` — ${rangoVales.cantidadVales} pesada${rangoVales.cantidadVales === 1 ? '' : 's'}` : '' }})
            </p>
          </td>
        </tr>
        <!-- filas vacías, calzan con el formato físico del remito en papel -->
        <tr v-for="n in 3" :key="n" class="border-b border-gray-200">
          <td class="border-r border-gray-400 px-2 py-3">&nbsp;</td>
          <td class="px-2 py-3">&nbsp;</td>
        </tr>
      </tbody>
    </table>

    <div class="mt-3 space-y-0.5">
      <p>
        <span class="font-semibold text-gray-500">Transporte:</span>
        {{ esTransportePropio == null ? '—' : esTransportePropio ? 'Propio' : 'Tercero' }}
      </p>
      <p><span class="font-semibold text-gray-500">Patente:</span> {{ vale.patente || '—' }}</p>
      <p><span class="font-semibold text-gray-500">Transportista:</span> {{ vale.chofer || '—' }}</p>
      <p><span class="font-semibold text-gray-500">Lugar de entrega:</span> {{ pedido?.ubicacion || '—' }}</p>
    </div>

    <div class="mt-8 grid grid-cols-2 gap-8 text-xs text-gray-600">
      <div>
        <p>Despacho: ______________________</p>
        <p class="mt-1 text-gray-400">{{ EMPRESA.nombre }} — Responsable de planta</p>
      </div>
      <div>
        <p>Recibe conforme: ______________________</p>
        <p class="mt-2 text-gray-400">Aclaración: ______________________</p>
      </div>
    </div>

    <div class="mt-4 border-t border-gray-300 pt-2 text-xs text-gray-500">
      <span class="font-semibold">Depósito:</span> {{ EMPRESA.deposito }}
    </div>
  </div>
</template>
