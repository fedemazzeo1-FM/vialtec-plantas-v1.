// Tipos de producto de la planta (plantas_formulas.tipo / plantas_pedidos.tipo).
// ÚNICO lugar donde se nombra cada tipo: el resto del código pregunta por
// circuito, unidad o total, nunca compara contra 'asfalto'/'hormigon'/
// 'mezcla_cemento' directamente. Agregar un tipo es agregar una entrada acá
// (más el CHECK de la base y las funciones SQL gemelas, ver migración 49).
//
// No confundir con plantas_vales.tipo_vale (asfalto / ingreso_arido /
// egreso_arido): ese es el tipo de VALE de Báscula, otro concepto.

/** Cómo sale el producto de la planta. */
export const CIRCUITO = {
  // Se pesa en Báscula, un vale por camión.
  BASCULA: 'bascula',
  // No se pesa: sale con N° de remito por carga.
  MIXER: 'mixer',
}

// `total` es la clave bajo la que se acumula en los totales. Dos tipos con la
// misma unidad NO comparten total (asfalto y mezcla cemento van los dos en tn
// y nunca se suman entre sí).
// `siempreVisible`: su total (o su sección en Pedidos) se muestra aunque esté
// en 0. Los que no, solo aparecen cuando hay algo que mostrar.
// `ordenListado`: orden de las secciones de Pedidos (el legado muestra
// Hormigón primero y Asfalto después).
// `color` / `clases`: color que identifica al tipo en gráficos y leyendas
// (las clases van escritas enteras para que Tailwind las genere).
// `avisoProduccion`: título del WhatsApp al operador cuando se confirma un
// pedido que se produce en el circuito de mixer.
export const TIPOS_PRODUCTO = {
  asfalto: {
    id: 'asfalto',
    nombre: 'Asfalto',
    circuito: CIRCUITO.BASCULA,
    unidad: 'tn',
    unidadLabel: 'tn',
    total: 'asfaltoTn',
    siempreVisible: true,
    ordenListado: 2,
    color: '#2a78d6',
    clases: { barra: 'bg-[#2a78d6]', texto: 'text-[#2a78d6]', punto: 'bg-[#2a78d6]' },
  },
  hormigon: {
    id: 'hormigon',
    nombre: 'Hormigón',
    circuito: CIRCUITO.MIXER,
    unidad: 'm3',
    unidadLabel: 'm³',
    total: 'hormigonM3',
    siempreVisible: true,
    ordenListado: 1,
    color: '#eb6834',
    clases: { barra: 'bg-[#eb6834]', texto: 'text-[#eb6834]', punto: 'bg-[#eb6834]' },
    avisoProduccion: 'Hormigón confirmado para producción',
  },
  mezcla_cemento: {
    id: 'mezcla_cemento',
    nombre: 'Mezcla cemento',
    circuito: CIRCUITO.MIXER,
    unidad: 'tn',
    unidadLabel: 'tn',
    total: 'mezclaCementoTn',
    siempreVisible: false,
    ordenListado: 3,
    color: '#64748b',
    clases: { barra: 'bg-[#64748b]', texto: 'text-[#64748b]', punto: 'bg-[#64748b]' },
    avisoProduccion: 'Mezcla cemento confirmada para producción',
  },
}

/** Todos los tipos, en el orden en que se cargan (selects de alta). */
export const LISTA_TIPOS_PRODUCTO = Object.values(TIPOS_PRODUCTO)

/** Todos los tipos, en el orden de las secciones de Pedidos. */
export const TIPOS_PRODUCTO_EN_ORDEN_DE_LISTADO = [...LISTA_TIPOS_PRODUCTO].sort((a, b) => a.ordenListado - b.ordenListado)

/** Tipo con el que arranca un formulario nuevo. */
export const TIPO_PRODUCTO_INICIAL = LISTA_TIPOS_PRODUCTO[0].id

/**
 * Configuración de un tipo. Un tipo desconocido o vacío se trata como el
 * inicial (asfalto): es lo que hacía todo el código antes de que existiera
 * esta configuración ("si no es hormigón, es asfalto").
 */
export function tipoProducto(tipo) {
  return TIPOS_PRODUCTO[tipo] ?? TIPOS_PRODUCTO[TIPO_PRODUCTO_INICIAL]
}

export const nombreTipoProducto = (tipo) => tipoProducto(tipo).nombre
export const unidadTipoProducto = (tipo) => tipoProducto(tipo).unidad
export const unidadLabelTipoProducto = (tipo) => tipoProducto(tipo).unidadLabel
export const circuitoTipoProducto = (tipo) => tipoProducto(tipo).circuito
export const esCircuitoBascula = (tipo) => tipoProducto(tipo).circuito === CIRCUITO.BASCULA
export const esCircuitoMixer = (tipo) => tipoProducto(tipo).circuito === CIRCUITO.MIXER

/** Ids de los tipos de un circuito, para filtrar queries con `.in('tipo', …)`. */
export function tiposDeCircuito(circuito) {
  return LISTA_TIPOS_PRODUCTO.filter((t) => t.circuito === circuito).map((t) => t.id)
}

/** Ids de los tipos que acumulan en un total, para filtrar queries con `.in('tipo', …)`. */
export function tiposDelTotal(total) {
  return LISTA_TIPOS_PRODUCTO.filter((t) => t.total === total).map((t) => t.id)
}

/** Config del tipo dueño de un total ('hormigonM3' -> config de hormigón). */
export function tipoDelTotal(total) {
  return LISTA_TIPOS_PRODUCTO.find((t) => t.total === total)
}

// ---------------------------------------------------------------------------
// Totales: un acumulador por tipo, cada uno en su unidad.
// ---------------------------------------------------------------------------

/** { asfaltoTn: 0, hormigonM3: 0, mezclaCementoTn: 0 } */
export function totalesVacios() {
  return Object.fromEntries(LISTA_TIPOS_PRODUCTO.map((t) => [t.total, 0]))
}

/** Suma `cantidad` en el total que le corresponde al tipo. Muta y devuelve `totales`. */
export function sumarEnTotal(totales, tipo, cantidad) {
  totales[tipoProducto(tipo).total] += Number(cantidad) || 0
  return totales
}

/** Suma campo a campo dos o más objetos de totales (los campos ausentes cuentan 0). */
export function sumarTotales(...lista) {
  const resultado = totalesVacios()
  for (const totales of lista) {
    for (const clave of Object.keys(resultado)) resultado[clave] += Number(totales?.[clave]) || 0
  }
  return resultado
}

/** Suma de todos los totales, SOLO para ordenar (mezcla unidades a propósito). */
export function magnitudTotales(totales) {
  return LISTA_TIPOS_PRODUCTO.reduce((acc, t) => acc + (Number(totales?.[t.total]) || 0), 0)
}

/**
 * Tipos cuyo total hay que mostrar: los `siempreVisible` más los que tengan
 * algo cargado en `totales`.
 */
export function tiposConTotalVisible(totales) {
  return LISTA_TIPOS_PRODUCTO.filter((t) => t.siempreVisible || (Number(totales?.[t.total]) || 0) > 0)
}

/**
 * Totales como texto, uno por tipo: ['12.0 tn', '3.0 m³', '6.0 tn mezcla cemento'].
 * Los tipos que no son `siempreVisible` llevan su nombre, para no confundirse
 * con otro de la misma unidad, y solo aparecen si tienen algo.
 * @param {{ decimales?: number, soloConValor?: boolean }} opciones
 *   `soloConValor`: omite también los `siempreVisible` que estén en 0.
 */
export function etiquetasTotales(totales, { decimales = 1, soloConValor = false } = {}) {
  return LISTA_TIPOS_PRODUCTO.filter((t) => {
    const valor = Number(totales?.[t.total]) || 0
    return valor > 0 || (t.siempreVisible && !soloConValor)
  }).map((t) => {
    const valor = (Number(totales?.[t.total]) || 0).toFixed(decimales)
    return `${valor} ${t.unidadLabel}${t.siempreVisible ? '' : ` ${t.nombre.toLowerCase()}`}`
  })
}
