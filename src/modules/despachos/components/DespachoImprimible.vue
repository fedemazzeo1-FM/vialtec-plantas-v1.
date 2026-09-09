<script setup>
// Wrapper de Despachos sobre el remito ÚNICO y oficial del sistema
// (`src/components/shared/RemitoImprimible.vue`) — 2026-09-09, pedido
// explícito de Federico: "el que tiene que quedar es el de báscula, en los
// dos módulos deben ser idénticos". Antes este componente tenía su propio
// layout de "slip" simple (ver historial de git si hace falta la versión
// vieja) — quedó reemplazado por completo, este archivo ahora solo mapea
// pedido/obraNombre/formulaNombre/cargas a los props genéricos del remito
// compartido. El nombre del archivo/componente se mantiene igual (Federico
// lo nombró así en su pedido) para no romper los imports existentes de
// DespachosView.vue.

import { computed } from 'vue'
import RemitoImprimible from '@/components/shared/RemitoImprimible.vue'
import { formatearNumeroVale } from '@/modules/bascula/services/bascula.service'

const props = defineProps({
  pedido: { type: Object, required: true },
  obraNombre: { type: String, default: '' },
  formulaNombre: { type: String, default: '' },
  cargas: { type: Array, default: () => [] },
  // Opcional — mismo criterio "Propio/Tercero" que ya usa Báscula (si no se
  // pasa, el remito queda sin esa deducción y muestra "—" en Transporte).
  patentes: { type: Array, default: () => [] },
})

function unidad(tipo) {
  return tipo === 'hormigon' ? 'm³' : 'tn'
}

// N° de remito: para asfalto es único por pedido y automático desde la
// primera carga (plantas_pedidos.nro_remito_global, migración 36 — antes
// era un campo opcional que el operador tipeaba a mano). Para hormigón NO
// hay remito único de pedido (memory/relevamiento: "el remito ya es por
// carga") — se muestran los N° reales de las cargas (únicos, separados por
// coma si hay más de un mixer con remito distinto).
const numeroRemito = computed(() => {
  if (props.pedido.nro_remito_global) return props.pedido.nro_remito_global
  if (props.pedido.tipo !== 'hormigon') return null
  const deCargas = [...new Set(props.cargas.map((c) => c.numeroRemitoOVale).filter(Boolean))]
  return deCargas.length ? deCargas.join(', ') : null
})

// Sub-línea "S/Vale de báscula N° X al Y" — solo asfalto (cargas trae el N°
// de VALE por camión, no de remito, ver fetchCargasDelPedido en
// despachos.service.js). Mismo formato que ya usa Báscula para su propio
// remito, por consistencia visual entre los dos módulos.
const detalleSubtexto = computed(() => {
  if (props.pedido.tipo !== 'asfalto') return null
  const vales = props.cargas.map((c) => c.numeroRemitoOVale).filter(Boolean)
  if (!vales.length) return null
  const ordenados = [...vales].sort((a, b) => Number(a) - Number(b))
  const desde = ordenados[0]
  const hasta = ordenados[ordenados.length - 1]
  return `S/Vale de báscula N° ${formatearNumeroVale(desde)}${hasta !== desde ? ` al ${formatearNumeroVale(hasta)}` : ''} (correlativos — ${vales.length} pesada${vales.length === 1 ? '' : 's'})`
})

// Transporte/Patente/Transportista: un despacho puede tener varios camiones
// con patentes distintas — sin desglose por camión en este documento (misma
// regla que el resto del remito: solo el acumulado total, nunca detalle por
// carga), se listan las patentes únicas si hay más de una. No hay dato de
// "chofer" a nivel carga en Pedidos (solo en los vales de Báscula), así que
// Transportista queda sin dato acá — es información real disponible, no un
// valor inventado.
const patentesUnicas = computed(() => [...new Set(props.cargas.map((c) => c.patente).filter(Boolean))])
const patenteLabel = computed(() => (patentesUnicas.value.length ? patentesUnicas.value.join(', ') : ''))
const transporte = computed(() => {
  if (patentesUnicas.value.length !== 1) return null
  const match = props.patentes.find((p) => p.patente === patentesUnicas.value[0])
  return match ? (match.es_externa ? 'Tercero' : 'Propio') : null
})

// Un solo "item" (mismo criterio que Báscula: solo el acumulado total del
// despacho, nunca desglose de cargas individuales — ver RemitoImprimible.vue).
// Detalle: para asfalto es SIEMPRE "MEZCLA ASFÁLTICA" fijo, nunca la fórmula
// real (2026-09-09, pedido explícito de Federico — mismo criterio que
// useBascula.js#remitoParaImprimir). Hormigón no está en ese pedido, sigue
// mostrando la fórmula real.
const items = computed(() => [
  {
    cantidad: `${props.pedido.cantidad_despachada} ${unidad(props.pedido.tipo)}`,
    detalle: props.pedido.tipo === 'asfalto' ? 'MEZCLA ASFÁLTICA' : (props.formulaNombre || '').toUpperCase(),
    subtexto: detalleSubtexto.value,
  },
])
</script>

<template>
  <RemitoImprimible
    :numero-remito="numeroRemito"
    :fecha="pedido.fecha_programada"
    :destino="obraNombre"
    :items="items"
    :transporte="transporte"
    :patente="patenteLabel"
    :lugar-entrega="pedido.ubicacion"
  />
</template>
