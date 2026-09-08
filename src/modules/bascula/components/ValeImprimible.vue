<script setup>
// Documento imprimible compartido por "Imprimir vale" e "Imprimir remito".
// El wrapper .imprimible (definido en src/assets/main.css) es lo que hace que
// solo esto se vea al imprimir, ocultando el resto de la página/modal.
//
// Modo "vale": formato A4 LANDSCAPE (@page único, margin:0, en
// src/assets/main.css — corregido 2026-09-03 noche: la versión de la tarde
// usaba una "named page" por componente que el diálogo de impresión de
// Chrome no terminó respetando en la práctica, ver el comentario en
// main.css), las 2 copias (Original / Duplicado) LADO A LADO en una sola
// hoja, separadas por una línea de corte VERTICAL punteada al medio del
// ancho — al cortar quedan 2 vales verticales independientes (Logica sis.
// plantas v1.rtf §2.4 pedía esta misma disposición). `h-full` en el grid y
// en cada copia (`flex flex-col` + `mt-auto` en la firma) para que ocupen
// TODO el alto real de la hoja (≈200mm útiles con el padding de
// `.imprimible`), no solo lo que ocupe el contenido — pedido explícito de
// Federico: "aprovechá toda la hoja".
//
// Modo "remito" (rediseñado 2026-09-01 contra una foto real de un remito de
// VialTec S.A. que compartió Federico; layout de página corregido 2026-09-03
// noche): reproduce el remito fiscal en papel — membrete con datos
// impositivos, N° de remito, Desde/Destino, tabla Cantidad/Detalle con SOLO
// el acumulado total + la fórmula/mezcla (nunca tuvo desglose de cargas
// individuales, a propósito), Transporte/Patente/Transportista/Lugar de
// entrega, y las dos firmas (Despacho / Recibe conforme).
//
// A DIFERENCIA del vale: acá Original y Duplicado van en 2 HOJAS
// SEPARADAS (`break-after-page` en la primera copia), cada una ocupando la
// hoja COMPLETA — no lado a lado como el vale. Pedido explícito de
// Federico ("remito va en 2 hojas distintas, los vales van los dos en 1
// sola hoja") sobre el primer intento de esta misma noche, que ponía las
// 2 copias del remito lado a lado igual que el vale (ese layout a mitad de
// ancho de hoja, con más contenido/campos que el vale, terminaba
// desbordando a varias páginas en la impresora real — con hoja completa
// por copia sobra espacio de sobra).
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

// Datos del instrumento de pesaje (2026-09-03, pedido textual de Federico:
// "Bascula Casilda 80 tn, modelo Fah 21301, balanza cert calibracion
// n°260409-272") — dato fijo del instrumento, igual que los datos
// impositivos de EMPRESA de arriba: si algún día se recalibra o se cambia
// de báscula, se actualiza acá, no hay tabla para esto (no es un dato
// operativo por vale).
const BALANZA_CERT_CALIBRACION =
  'Báscula Casilda 80 tn, modelo FAH 21301 — balanza cert. calibración N° 260409-272'

function formatFecha(iso) {
  const d = new Date(iso)
  return {
    fecha: d.toLocaleDateString('es-AR'),
    hora: d.toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' }),
  }
}

// Cada copia del vale lleva UNA sola firma, distinta según a quién le queda
// esa copia (ajuste pedido por Federico, 2026-08-28; texto de las firmas
// ajustado 2026-09-03 tarde a pedido textual de Federico: "Firma del
// responsable en balanza" / "Firma del chofer") — no las dos firmas
// genéricas de antes repetidas en ambas copias.
const copiasVale = [
  { titulo: 'Original', firma: 'Firma del responsable en balanza' },
  { titulo: 'Duplicado', firma: 'Firma del chofer' },
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
  <!-- Landscape, 2 columnas lado a lado (Original / Duplicado) — línea de
       corte VERTICAL al medio del ancho de la hoja (2026-09-03 tarde).
       Ajuste 2026-09-07 (pedido de Federico: "corto la hoja exactamente a
       la mitad y corto parte de un vale"): verificado con un harness fuera
       de la app (mismo criterio de medición que sesiones anteriores) que el
       centrado en sí ya es matemáticamente exacto (grid de 2 columnas
       iguales, línea de corte a `left-1/2` del mismo contenedor) — lo que
       faltaba era MARGEN DE SEGURIDAD real: con `gap-6` (24px ≈ 6.35mm)
       quedaban solo ~3.17mm de aire a cada lado de la línea antes de tocar
       el borde de cada vale, insuficiente para la imprecisión real de
       imprimir/cortar a mano. `gap-[14mm]` (valor en mm, no en rem, para no
       depender de ningún font-size) duplica eso a 7mm de cada lado —
       verificado que sigue perfectamente centrado (7.00mm y 7.00mm exactos)
       y que ninguna columna se achica lo suficiente como para desbordar
       contenido (pierde <4mm de ancho útil cada una, sigue sobrando lugar
       de sobra para los campos del vale). -->
  <div v-if="modo === 'vale'" class="relative grid h-full grid-cols-2 gap-[14mm]">
    <!-- Línea de corte entre copias: visual de "cortar acá" en el medio del
         ancho, mismo criterio que un talonario físico con duplicado, ahora
         vertical en vez de horizontal. -->
    <div class="pointer-events-none absolute inset-y-0 left-1/2 flex -translate-x-1/2 flex-col items-center text-gray-300">
      <span class="text-[10px] leading-none">✂</span>
      <div class="mt-1 w-0 flex-1 border-l border-dashed border-gray-300"></div>
    </div>

    <div
      v-for="copia in copiasVale"
      :key="copia.titulo"
      class="flex h-full flex-col border border-gray-300 p-6 text-base text-gray-800"
    >
      <div class="mb-4 flex items-start justify-between border-b border-gray-300 pb-3">
        <img :src="logoVialtec" alt="VIAL-TEC S.A." class="h-14 w-auto" />
        <div class="text-right">
          <p class="text-2xl font-bold">Vale de pesaje N° {{ formatearNumeroVale(vale.numero_vale) }}</p>
          <p class="text-sm font-semibold uppercase tracking-wide text-gray-400">{{ copia.titulo }}</p>
          <p class="text-[11px] leading-tight text-gray-400">{{ BALANZA_CERT_CALIBRACION }}</p>
        </div>
      </div>

      <div class="grid grid-cols-2 gap-x-6 gap-y-3">
        <p><span class="text-gray-500">Fecha:</span> {{ formatFecha(vale.fecha_pesada).fecha }}</p>
        <p><span class="text-gray-500">Hora:</span> {{ formatFecha(vale.fecha_pesada).hora }}</p>
        <p><span class="text-gray-500">Patente:</span> {{ vale.patente || '—' }}</p>
        <p><span class="text-gray-500">Chofer:</span> {{ vale.chofer || '—' }}</p>
        <!-- Obra: solo tiene sentido para asfalto/egreso de áridos — un
             ingreso de áridos (2026-09-08, pedido de Federico: sumarle el
             botón "Vale") no tiene obra asociada, va con
             Proveedor/Remito/Remito(cantidad) en su lugar. -->
        <p v-if="vale.tipo_vale !== 'ingreso_arido'" class="col-span-2"><span class="text-gray-500">Obra:</span> {{ obraNombre || '—' }}</p>
        <!-- 2026-09-04 (pedido de Federico: Vale también para egreso de
             áridos): asfalto lleva Mezcla (fórmula del pedido); egreso/
             ingreso de áridos no tienen pedido/fórmula, llevan Material
             (texto libre que cargó el balancero en la puerta) en su lugar. -->
        <p v-if="vale.tipo_vale === 'asfalto'" class="col-span-2"><span class="text-gray-500">Mezcla:</span> {{ mezclaNombre || '—' }}</p>
        <p v-else class="col-span-2"><span class="text-gray-500">Material:</span> {{ vale.material || '—' }}</p>
        <template v-if="vale.tipo_vale === 'ingreso_arido'">
          <p><span class="text-gray-500">N° Remito:</span> {{ vale.numero_remito_ingreso || '—' }}</p>
          <p>
            <span class="text-gray-500">Cantidad s/remito:</span>
            {{ vale.cantidad_remito_ingreso != null ? Number(vale.cantidad_remito_ingreso).toFixed(2) + ' tn' : '—' }}
          </p>
        </template>
        <p><span class="text-gray-500">Bruto:</span> {{ vale.peso_bruto }} {{ vale.unidad }}</p>
        <p><span class="text-gray-500">Tara:</span> {{ vale.tara }} {{ vale.unidad }}</p>
        <p><span class="text-gray-500">Neto:</span> {{ vale.peso_neto }} {{ vale.unidad }}</p>
        <p v-if="vale.temperatura != null"><span class="text-gray-500">Temp.:</span> {{ vale.temperatura }} °C</p>
      </div>

      <div class="mt-6 border-t border-gray-300 pt-3">
        <p class="text-xl font-bold">Acumulado: {{ acumuladoTn != null ? acumuladoTn.toFixed(2) : '—' }} tn</p>
      </div>

      <div class="mt-auto pt-8 text-sm text-gray-500">
        <p>{{ copia.firma }}: ________________________________</p>
      </div>
    </div>
  </div>

  <!-- ============================= MODO REMITO ============================= -->
  <!-- Réplica del remito físico de VialTec S.A. (foto real, 2026-09-01,
       formato de campos re-confirmado contra la misma foto 2026-09-03
       noche): se imprime cuando termina el acumulado del pedido/obra del
       día — el balancero corta este remito como respaldo de todos los
       vales de báscula correlativos que se pesaron para llegar a ese
       acumulado.

       2 HOJAS SEPARADAS (Original / Duplicado), cada una a hoja completa
       — `break-after-page` (Tailwind) en la primera copia fuerza el salto
       de página antes de la segunda. NO es un grid de 2 columnas como el
       vale (ver comentario arriba: pedido explícito de Federico). -->
  <div v-if="modo === 'remito'">
    <div
      v-for="(_, i) in [0, 1]"
      :key="i"
      class="flex h-full w-full flex-col p-6"
      :class="i === 0 ? 'break-after-page' : ''"
    >
      <!-- Reajuste 2026-09-07 (pedido de Federico, ya confirmado imprimiendo
           de verdad en portrait: "aprovechá más el espacio de la hoja,
           firmas con más lugar, logo más grande, CUIT/IERIC apilados").
           El ajuste de 2026-09-04 de acá abajo comprimió todo esto para
           entrar en los ~210mm de una hoja LANDSCAPE — ya no aplica, ahora
           es una hoja PORTRAIT real de 297mm de alto (ver main.css/
           useBascula.js#imprimir(), 2026-09-07) con casi 90mm más de
           margen. Se agranda paddings/espaciados/logo, se vuelve a 4 filas
           en blanco en la tabla (como el papel real, el motivo original de
           que fueran 4 antes de recortarlas a 2 por el desborde en
           landscape) y las firmas pasan a tener una caja en blanco real
           arriba de la línea (antes solo el guión bajo, sin espacio físico
           para firmar) — medido con el mismo harness de sesiones
           anteriores (clonar a un contenedor 210×297mm real): entra
           holgado en la hoja, sin desbordar a una segunda. -->
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
            <!-- Datos impositivos apilados, uno abajo del otro (2026-09-07,
                 pedido explícito de Federico) — antes iban de a 2 por
                 renglón separados por guión. -->
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
            <span class="ml-1 font-semibold">{{ pedido?.nro_remito_global || '—' }}</span>
          </div>
          <div class="rounded border border-gray-400 px-4 py-2.5">
            <span class="text-[11px] font-semibold uppercase text-gray-500">Fecha:</span>
            <span class="ml-1 font-semibold">{{ formatFecha(vale.fecha_pesada).fecha }}</span>
          </div>
        </div>
        <div class="mb-3 rounded border border-gray-400 px-4 py-2.5">
          <span class="text-[11px] font-semibold uppercase text-gray-500">Desde:</span>
          <span class="ml-1 font-semibold">{{ EMPRESA.deposito }}</span>
        </div>
        <div class="mb-4 rounded border border-gray-400 px-4 py-2.5">
          <span class="text-[11px] font-semibold uppercase text-gray-500">Destino:</span>
          <span class="ml-1 font-semibold">{{ obraNombre || '—' }}</span>
        </div>

        <!-- Solo acumulado total + fórmula (nunca desglose de cargas
             individuales — confirmado de nuevo 2026-09-03 noche contra la
             foto real del remito físico que compartió Federico). -->
        <table class="w-full table-fixed border border-gray-400 text-left">
          <thead>
            <tr class="border-b border-gray-400 bg-gray-50">
              <th class="w-32 border-r border-gray-400 px-4 py-2 text-xs uppercase tracking-wide text-gray-500">Cantidad</th>
              <th class="px-4 py-2 text-xs uppercase tracking-wide text-gray-500">Detalle</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td class="border-r border-gray-400 px-4 py-3 align-top text-lg font-bold">
                {{ acumuladoTn != null ? acumuladoTn.toFixed(2) : '—' }} tn
              </td>
              <td class="px-4 py-3 align-top">
                <p class="font-semibold">{{ detalleMezcla }}</p>
                <p v-if="rangoVales?.valeDesde != null" class="mt-1 text-xs text-gray-600">
                  S/Vale de báscula N° {{ formatearNumeroVale(rangoVales.valeDesde) }}
                  <template v-if="rangoVales.valeHasta !== rangoVales.valeDesde">
                    al {{ formatearNumeroVale(rangoVales.valeHasta) }}
                  </template>
                  (correlativos{{ rangoVales.cantidadVales ? ` — ${rangoVales.cantidadVales} pesada${rangoVales.cantidadVales === 1 ? '' : 's'}` : '' }})
                </p>
              </td>
            </tr>
            <!-- Filas en blanco (como el papel real): deja lugar para anotaciones
                 a mano, mismo criterio que la foto de referencia de Federico.
                 Vuelve a 4 (estaban en 2 desde 2026-09-04 por el desborde en
                 landscape, ya no aplica en portrait — ver comentario de
                 arriba). -->
            <tr v-for="n in 4" :key="n">
              <td class="border-r border-t border-gray-300 px-4 py-3">&nbsp;</td>
              <td class="border-t border-gray-300 px-4 py-3">&nbsp;</td>
            </tr>
          </tbody>
        </table>

        <div class="mt-4 space-y-1 text-sm">
          <p>
            <span class="font-semibold text-gray-500">Transporte:</span>
            {{ esTransportePropio == null ? '—' : esTransportePropio ? 'Propio' : 'Tercero' }}
          </p>
          <p><span class="font-semibold text-gray-500">Patente:</span> {{ vale.patente || '—' }}</p>
          <p><span class="font-semibold text-gray-500">Transportista:</span> {{ vale.chofer || '—' }}</p>
          <p><span class="font-semibold text-gray-500">Lugar de entrega:</span> {{ pedido?.ubicacion || '—' }}</p>
        </div>

        <!-- Firmas con espacio real para firmar (2026-09-07, pedido
             explícito de Federico) — antes la "línea" era solo el guión
             bajo de un renglón de texto, sin ningún lugar en blanco arriba
             para la firma en sí. Ahora cada una tiene una caja vacía
             (h-20, ~21mm) con el borde de abajo como línea. -->
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
