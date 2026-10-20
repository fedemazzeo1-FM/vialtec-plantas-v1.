// Detalle legible de una fila de auditoría (2026-10-19, pedido de Federico,
// mismo criterio que el detalle de flota): una frase arriba (quién hizo qué
// sobre qué), solo los campos que cambiaron con nombre legible y valor
// formateado, el motivo destacado, y en altas/bajas solo los datos
// principales. Los campos técnicos (ids, uuid, fechas de sistema, jsonb
// internos, datos_legados) no se muestran acá: quedan en "Ver datos
// técnicos" (AuditoriaDetalle.vue), que sigue mostrando la fila tal cual.
//
// Funciones puras: no leen la base. Lo externo llega en `contexto`:
// { nombres: {email: nombre}, catalogos: { formulas: Map, obras: Map } }
// (los trae useAuditoria una sola vez al abrir la pantalla).
//
// Forma de los registros: la escriben las RPC (migraciones 54 a 60, ver
// supabase/scripts/referencia_funciones_auditadas.sql) y el trigger genérico
// de la migración 61. En EDITAR/CAMBIAR_ESTADO/CORREGIR la base guarda solo
// lo que cambió; en CREAR, el registro completo en "después"; en ELIMINAR,
// el completo en "antes".
import { formatearCantidadHasta, formatearNumeroRemito, formatearNumeroPedido } from '@/services/formato-numeros'
import { TIPOS_PRODUCTO } from '@/config/tipos-producto'

const USUARIO_SISTEMA = 'sistema (SQL)'

// ---------- Formato de valores ----------

function numero(valor, decimales = 2) {
  return formatearCantidadHasta(valor, decimales)
}

function esNumero(valor) {
  return valor !== null && valor !== '' && Number.isFinite(Number(valor))
}

function fecha(valor) {
  const texto = String(valor)
  const soloFecha = /^(\d{4})-(\d{2})-(\d{2})$/.exec(texto)
  if (soloFecha) return `${soloFecha[3]}/${soloFecha[2]}/${soloFecha[1]}`
  const f = new Date(texto)
  if (!/^\d{4}-\d{2}-\d{2}[T ]/.test(texto) || Number.isNaN(f.getTime())) return texto
  return f.toLocaleString('es-AR', {
    timeZone: 'America/Argentina/Buenos_Aires',
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  })
}

const UNIDAD_TIPO = Object.fromEntries(Object.values(TIPOS_PRODUCTO).map((t) => [t.id, t.unidadLabel]))
const NOMBRE_TIPO = Object.fromEntries(Object.values(TIPOS_PRODUCTO).map((t) => [t.id, t.nombre]))

/** Insumo de fórmula: { material, cantidad, unidad } → "240 kg", "4,5 %". */
function textoInsumo(insumo) {
  if (!insumo) return '—'
  const unidad = insumo.unidad ? ` ${insumo.unidad}` : ''
  return esNumero(insumo.cantidad) ? `${numero(insumo.cantidad, 3)}${unidad}` : `${insumo.cantidad ?? '—'}${unidad}`
}

// tipo: texto | fecha | tn | m3 | kg (se muestra en tn, como el resto de la
// UI) | cantidad (unidad del pedido, contexto.unidad) | numero | si_no |
// lista (con `valores`) | catalogo | catalogo_lista | pedido | remito |
// vale_arido | temperatura
function formatear(valor, def, contexto) {
  if (valor === null || valor === undefined || valor === '') return '—'
  const tipo = def?.tipo ?? (typeof valor === 'boolean' ? 'si_no' : typeof valor === 'number' ? 'numero' : 'texto')
  switch (tipo) {
    case 'fecha':
      return fecha(valor)
    case 'tn':
      return esNumero(valor) ? `${numero(valor)} tn` : String(valor)
    case 'm3':
      return esNumero(valor) ? `${numero(valor)} m³` : String(valor)
    case 'kg':
      return esNumero(valor) ? `${numero(Number(valor) / 1000)} tn` : String(valor)
    case 'cantidad':
      return esNumero(valor) ? `${numero(valor)}${contexto.unidad ? ` ${contexto.unidad}` : ''}` : String(valor)
    case 'numero':
      return esNumero(valor) ? numero(valor) : String(valor)
    case 'temperatura':
      return esNumero(valor) ? `${numero(valor, 1)} °C` : String(valor)
    case 'si_no':
      return valor === true || valor === 'true' ? 'Sí' : 'No'
    case 'lista':
      return def.valores?.[String(valor)] ?? String(valor)
    case 'pedido':
      return formatearNumeroPedido(valor) || String(valor)
    case 'remito':
      return esNumero(valor) ? formatearNumeroRemito(valor) : String(valor)
    case 'vale_arido':
      return esNumero(valor) ? `I-${String(valor).padStart(5, '0')}` : String(valor)
    case 'catalogo': {
      const catalogo = contexto.catalogos?.[def.catalogo]
      if (!catalogo) return 'no disponible'
      return catalogo.get(String(valor)) ?? '(registro que ya no existe)'
    }
    case 'catalogo_lista': {
      if (!Array.isArray(valor)) return String(valor)
      if (!valor.length) return 'Ninguna'
      const catalogo = contexto.catalogos?.[def.catalogo]
      if (!catalogo) return `${valor.length}`
      return valor.map((id) => catalogo.get(String(id)) ?? '(registro que ya no existe)').join(', ')
    }
    default:
      return /^\d{4}-\d{2}-\d{2}([T ].*)?$/.test(String(valor)) ? fecha(valor) : String(valor)
  }
}

// ---------- Nombres de campo ----------

const ESTADOS_PEDIDO = {
  solicitado: 'Solicitado',
  confirmado: 'Confirmado',
  despachado: 'Despachado',
  postergado: 'Postergado',
  cancelado: 'Cancelado',
}
const TIPOS_VALE = {
  asfalto: 'Vale de asfalto',
  hormigon: 'Hormigón',
  ingreso_arido: 'Ingreso de áridos',
  egreso_arido: 'Salida de áridos',
}
const TIPOS_MOVIMIENTO = {
  ingreso_manual: 'Ingreso manual',
  egreso_manual: 'Salida manual',
  ingreso_proveedor: 'Ingreso de proveedor',
  egreso_despacho: 'Descuento por despacho',
  egreso_arido: 'Salida de áridos',
  ajuste: 'Ajuste',
  recalculo_despacho: 'Recálculo de despacho',
  recalculo_bascula: 'Recálculo de vale',
}

// Campos que se entienden igual en cualquier entidad. Cada entidad puede
// pisar alguno (p. ej. el nombre de los estados).
const CAMPOS_COMUNES = {
  estado: { label: 'Estado', tipo: 'lista', valores: ESTADOS_PEDIDO },
  numero: { label: 'N° de pedido', tipo: 'pedido' },
  tipo: { label: 'Producto', tipo: 'lista', valores: NOMBRE_TIPO },
  tipo_pedido: { label: 'Tipo de pedido', tipo: 'lista', valores: { obra: 'Obra', venta: 'Venta externa' } },
  formula_id: { label: 'Fórmula', tipo: 'catalogo', catalogo: 'formulas' },
  obra_id: { label: 'Obra', tipo: 'catalogo', catalogo: 'obras' },
  obra_ids: { label: 'Obras asignadas', tipo: 'catalogo_lista', catalogo: 'obras' },
  cliente_externo: { label: 'Cliente' },
  encargado: { label: 'Encargado' },
  ubicacion: { label: 'Ubicación' },
  observaciones: { label: 'Observaciones' },
  fecha_programada: { label: 'Fecha programada', tipo: 'fecha' },
  cantidad_solicitada: { label: 'Cantidad pedida', tipo: 'cantidad' },
  cantidad_despachada: { label: 'Cantidad despachada', tipo: 'cantidad' },
  archivado: { label: 'Archivado', tipo: 'si_no' },
  archivada: { label: 'Archivada', tipo: 'si_no' },
  nro_remito_global: { label: 'N° de remito' },
  nro_vale_global: { label: 'N° de vale' },
  pedido: { label: 'Pedido' },
  patente: { label: 'Patente' },
  patente_mixer: { label: 'Mixer' },
  chofer: { label: 'Chofer' },
  peso_bruto: { label: 'Peso bruto', tipo: 'tn' },
  tara: { label: 'Tara', tipo: 'tn' },
  peso_neto: { label: 'Peso neto', tipo: 'tn' },
  cantidad_remito: { label: 'Cant. s/remito', tipo: 'tn' },
  numero_remito: { label: 'N° de remito' },
  numero_vale: { label: 'N° de vale' },
  numero_vale_arido: { label: 'N° de vale', tipo: 'vale_arido' },
  tipo_vale: { label: 'Tipo de vale', tipo: 'lista', valores: TIPOS_VALE },
  proveedor: { label: 'Proveedor' },
  material: { label: 'Material' },
  temperatura: { label: 'Temperatura', tipo: 'temperatura' },
  fecha_pesada: { label: 'Fecha de la pesada', tipo: 'fecha' },
  acumulado_obra_tn: { label: 'Acumulado del día', tipo: 'tn' },
  anulado: { label: 'Anulado', tipo: 'si_no' },
  aplicado_al_vale_kg: { label: 'Stock aplicado por el vale', tipo: 'kg' },
  cantidad_tn: { label: 'Cantidad', tipo: 'tn' },
  // carga_hormigon guarda en volumen_m3 también la mezcla cemento (en tn):
  // la unidad sale del pedido.
  volumen_m3: { label: 'Cantidad', tipo: 'cantidad' },
  fecha_carga: { label: 'Fecha de la carga', tipo: 'fecha' },
  cantidad_kg: { label: 'Cantidad', tipo: 'kg' },
  nombre: { label: 'Nombre' },
  activo: { label: 'Activo', tipo: 'si_no' },
  cuit: { label: 'CUIT' },
  contacto: { label: 'Contacto' },
  telefono: { label: 'Teléfono' },
  es_externa: { label: 'Vehículo', tipo: 'lista', valores: { true: 'Externo', false: 'Propio' } },
  tipo_camion: { label: 'Tipo de camión' },
  chofer_habitual: { label: 'Chofer habitual' },
  orden_bascula: { label: 'Orden en Báscula', tipo: 'numero' },
  stock_minimo_kg: { label: 'Stock mínimo', tipo: 'kg' },
  stock_maximo_kg: { label: 'Stock máximo', tipo: 'kg' },
  controla_stock: { label: 'Controla stock', tipo: 'si_no' },
  destino: { label: 'Destino' },
  transportista: { label: 'Transportista' },
  fecha: { label: 'Fecha', tipo: 'fecha' },
  email: { label: 'Email' },
  rol: { label: 'Rol' },
  ver_todas_obras: { label: 'Ve todas las obras', tipo: 'si_no' },
  ver_ventas: { label: 'Ve ventas externas', tipo: 'si_no' },
  habilitado: { label: 'Habilitado', tipo: 'si_no' },
  modulo: { label: 'Módulo' },
  accion: { label: 'Acción' },
  descripcion: { label: 'Descripción' },
  // Cierre del pesaje en Báscula (migración 65)
  pesaje_cerrado_en: { label: 'Pesaje cerrado', tipo: 'fecha' },
  pesaje_cerrado_por: { label: 'Pesaje cerrado por' },
  pesado_tn: { label: 'Pesado al cerrar', tipo: 'tn' },
  vales_pesados: { label: 'Vales pesados', tipo: 'numero' },
}

// Nunca se muestran en el detalle legible (siguen en "Ver datos técnicos").
const CAMPOS_TECNICOS = new Set([
  'id',
  'created_at',
  'updated_at',
  'creado_por',
  'motivo_en',
  'responsable_email',
  'anulado_en',
  'anulado_por',
  'datos_legados',
  'unidad',
  'version',
])
// El motivo va destacado arriba, no como un campo más.
const CAMPOS_MOTIVO = ['motivo', 'motivo_anulacion']

function esTecnico(clave, valor) {
  const tipo = CAMPOS_COMUNES[clave]?.tipo
  if (tipo === 'catalogo' || tipo === 'catalogo_lista') return false
  if (CAMPOS_TECNICOS.has(clave) || CAMPOS_MOTIVO.includes(clave)) return true
  if (clave.endsWith('_id') || clave.endsWith('_ids')) return true
  if (valor !== null && typeof valor === 'object') return true // datos internos (jsonb)
  if (typeof valor === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-/i.test(valor)) return true // uuid suelto
  return false
}

/** 'cantidad_solicitada' → 'Cantidad solicitada'; 'nro_remito' → 'N° de remito'. */
export function nombreLegible(clave) {
  const texto = String(clave)
    .replace(/^nro_/, 'N° de ')
    .replace(/^numero_/, 'N° de ')
    .replace(/^fecha_/, 'Fecha de ')
    .replace(/_kg$/, '')
    .replace(/_/g, ' ')
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}

// ---------- Ayudas para las frases ----------

function partesEtiqueta(row) {
  return String(row.entidad_label ?? '')
    .split(' — ')
    .map((p) => p.trim())
    .filter(Boolean)
}

/** "P-0239 (Moorlands Pilar, 18 tn, 15/10/2026)". */
function conDetalle(principal, resto) {
  const detalle = resto.filter(Boolean).join(', ')
  return detalle ? `${principal} (${detalle})` : principal
}

/** Unidad del pedido: del tipo si vino en los valores, si no de la etiqueta ("… — 68 m³ — …"). */
function unidadDelRegistro(row) {
  const tipo = row.valores_despues?.tipo ?? row.valores_antes?.tipo
  if (UNIDAD_TIPO[tipo]) return UNIDAD_TIPO[tipo]
  const match = /\s(tn|m³)(?:\s—|$)/.exec(String(row.entidad_label ?? ''))
  return match ? match[1] : null
}

/** "Carga vale 10261 — P-0255 — VIAL 8 S.A — 80 tn — 17/10/2026" → { pedido, resto }. */
function pedidoDeEtiqueta(partes) {
  const i = partes.findIndex((p) => /^P-\d+$/.test(p))
  if (i === -1) return { pedido: null, resto: partes }
  return { pedido: partes[i], resto: partes.slice(i + 1) }
}

function fraseSujetoPedido(row) {
  const [numeroPedido, ...resto] = partesEtiqueta(row)
  return conDetalle(`el pedido ${numeroPedido ?? row.entidad_ref ?? ''}`.trim(), resto)
}

function tipoValeDe(row) {
  return row.valores_despues?.tipo_vale ?? row.valores_antes?.tipo_vale ?? null
}

function fraseSujetoVale(row) {
  const [primera = '', ...resto] = partesEtiqueta(row)
  const numeroVale = primera.replace(/^Vale\s+/, '') || row.entidad_ref || ''
  const nombre = {
    ingreso_arido: 'el ingreso de áridos',
    egreso_arido: 'la salida de áridos',
  }[tipoValeDe(row)] ?? 'el vale'
  return conDetalle(`${nombre} ${numeroVale}`.trim(), resto)
}

/** "Fórmula HORMIGON H-21 (hormigon)" → "HORMIGON H-21 (hormigón)". */
function nombreFormulaDeEtiqueta(row) {
  const nombre = row.valores_despues?.nombre ?? row.valores_antes?.nombre
  const tipo = row.valores_despues?.tipo ?? row.valores_antes?.tipo
  if (nombre) return tipo && NOMBRE_TIPO[tipo] ? `${nombre} (${NOMBRE_TIPO[tipo].toLowerCase()})` : nombre
  return String(row.entidad_label ?? row.entidad_ref ?? '')
    .replace(/^Fórmula\s+/, '')
    .replace(/\((asfalto|hormigon|mezcla_cemento)\)$/, (_, t) => `(${NOMBRE_TIPO[t].toLowerCase()})`)
}

function cantidadConUnidad(valor, unidad) {
  return esNumero(valor) ? `${numero(valor)} ${unidad}` : null
}

// Artículo + nombre de cada entidad de maestros/usuarios (frase genérica).
const SUJETO_MAESTRO = {
  material: 'el material',
  cliente: 'el cliente',
  proveedor: 'el proveedor',
  chofer: 'el chofer',
  patente: 'la patente',
  encargado: 'el encargado',
  obra_local: 'la obra',
  rol: 'el rol',
  permiso: 'el permiso',
}

// ---------- Diccionario por entidad ----------
//
// campos: pisan a CAMPOS_COMUNES. principales: qué mostrar en un alta/baja
// (y el orden de los cambios). frase(row, verbo): lo que va después del
// nombre de quien lo hizo. especial(antes, despues, contexto): cambios que no
// son "campo: antes → después" (insumos de una fórmula). datosEspeciales:
// datos de un alta que no son campos sueltos (ajustes de un relevamiento,
// ítems de un remito).

const ENTIDADES = {
  pedido: {
    principales: [
      'tipo',
      'formula_id',
      'tipo_pedido',
      'obra_id',
      'cliente_externo',
      'cantidad_solicitada',
      'fecha_programada',
      'estado',
      'encargado',
      'ubicacion',
      'observaciones',
    ],
    frase: (row, verbo) => {
      const sujeto = fraseSujetoPedido(row)
      const despues = row.valores_despues ?? {}
      if (row.tipo_accion === 'CAMBIAR_ESTADO') {
        // Migración 65: "¿Se terminó el pedido?" en Báscula / reabrir desde Pedidos.
        if ('pesaje_cerrado_en' in despues) return `${despues.pesaje_cerrado_en ? 'cerró' : 'reabrió'} el pesaje d${sujeto}`
        if ('archivado' in despues) return `${despues.archivado ? 'archivó' : 'desarchivó'} ${sujeto}`
        const verboEstado = { confirmado: 'confirmó', postergado: 'postergó', cancelado: 'canceló' }[despues.estado]
        if (verboEstado) return `${verboEstado} ${sujeto}`
      }
      if (row.tipo_accion === 'CREAR' && /residual|al dividir/i.test(despues.observaciones ?? '')) {
        return `creó ${sujeto} por el saldo de un despacho parcial`
      }
      return `${verbo({ CREAR: 'creó', EDITAR: 'modificó', ANULAR: 'canceló' })} ${sujeto}`
    },
  },

  despacho: {
    principales: ['estado', 'cantidad_despachada', 'nro_remito_global', 'nro_vale_global'],
    frase: (row, verbo) => {
      const sujeto = `el despacho del ${fraseSujetoPedido(row).replace(/^el /, '')}`
      if (row.tipo_accion === 'CAMBIAR_ESTADO' && row.valores_despues?.estado === 'despachado') return `finalizó ${sujeto}`
      return `${verbo({ CORREGIR: 'corrigió' })} ${sujeto}`
    },
  },

  carga_asfalto: {
    principales: ['cantidad_tn', 'patente', 'fecha_carga', 'observaciones'],
    frase: (row, verbo) => {
      const { pedido, resto } = pedidoDeEtiqueta(partesEtiqueta(row))
      const cantidad = cantidadConUnidad(row.valores_despues?.cantidad_tn, 'tn')
      const carga = conDetalle(`la carga del vale ${row.entidad_ref ?? ''}`.trim(), [cantidad])
      const destino = pedido ? ` en el ${conDetalle(`pedido ${pedido}`, resto)}` : ''
      return `${verbo({ CREAR: 'registró' })} ${carga}${destino}`
    },
  },

  carga_hormigon: {
    principales: ['volumen_m3', 'patente_mixer', 'chofer', 'fecha_carga', 'observaciones'],
    frase: (row, verbo) => {
      const { pedido, resto } = pedidoDeEtiqueta(partesEtiqueta(row))
      const cantidad = cantidadConUnidad(row.valores_despues?.volumen_m3, unidadDelRegistro(row) ?? 'm³')
      const carga = conDetalle(`la carga del remito ${row.entidad_ref ?? ''}`.trim(), [cantidad])
      const destino = pedido ? ` en el ${conDetalle(`pedido ${pedido}`, resto)}` : ''
      return `${verbo({ CREAR: 'registró' })} ${carga}${destino}`
    },
  },

  vale: {
    principales: [
      'tipo_vale',
      'pedido',
      'obra_id',
      'proveedor',
      'material',
      'numero_remito',
      'cantidad_remito',
      'patente',
      'chofer',
      'peso_bruto',
      'tara',
      'peso_neto',
      'temperatura',
      'acumulado_obra_tn',
      'fecha_pesada',
      'observaciones',
    ],
    frase: (row, verbo) =>
      `${verbo({ CREAR: 'registró', EDITAR: 'modificó', CORREGIR: 'corrigió', ANULAR: 'anuló', REASIGNAR: 'reasignó' })} ${fraseSujetoVale(row)}`,
  },

  movimiento_manual: {
    principales: ['material', 'tipo', 'cantidad_kg', 'observaciones'],
    campos: { tipo: { label: 'Tipo', tipo: 'lista', valores: TIPOS_MOVIMIENTO } },
    frase: (row, verbo) => {
      const d = row.valores_despues ?? {}
      const tipo = d.tipo === 'ingreso_manual' ? 'un ingreso manual' : d.tipo === 'egreso_manual' ? 'una salida manual' : null
      if (!tipo) return `${verbo({ CREAR: 'registró' })} ${partesEtiqueta(row).join(', ') || 'un movimiento manual de stock'}`
      const cantidad = esNumero(d.cantidad_kg) ? `${numero(Math.abs(Number(d.cantidad_kg)) / 1000)} tn` : null
      return `registró ${tipo} de stock ${conDetalle('', [d.material, cantidad]).trim()}`.trim()
    },
  },

  relevamiento: {
    frase: (row) => {
      const n = Array.isArray(row.valores_despues?.ajustes) ? row.valores_despues.ajustes.length : null
      if (n == null) return 'registró un relevamiento de stock'
      return `registró un relevamiento de stock (${n === 1 ? '1 material ajustado' : `${n} materiales ajustados`})`
    },
    datosEspeciales: (registro) => {
      if (!Array.isArray(registro?.ajustes)) return null
      return registro.ajustes.map((a) => {
        // Menos de 1 tn va en kg: en tn un ajuste de gramos se leía "+0 tn".
        const kg = Number(a.ajuste_kg)
        const signo = kg > 0 ? '+' : kg < 0 ? '−' : ''
        const magnitud = Math.abs(kg) < 1000 ? `${numero(Math.abs(kg))} kg` : `${numero(Math.abs(kg) / 1000)} tn`
        const ajuste = esNumero(a.ajuste_kg) ? ` (${kg === 0 ? 'sin cambio' : `${signo}${magnitud}`})` : ''
        return {
          campo: a.material ?? 'Material',
          valor: `${formatear(a.antes_kg, { tipo: 'kg' }, {})} → ${formatear(a.despues_kg, { tipo: 'kg' }, {})}${ajuste}`,
        }
      })
    },
  },

  remito_manual: {
    principales: ['fecha', 'destino', 'patente', 'transportista'],
    frase: (row, verbo) => {
      const [, ...resto] = partesEtiqueta(row)
      return `${verbo({ CREAR: 'generó' })} ${conDetalle(`el remito manual ${row.entidad_ref ?? ''}`.trim(), resto)}`
    },
    datosEspeciales: (registro, contexto, datosBase) => {
      const items = Array.isArray(registro?.items) ? registro.items : []
      const filasItems = items.map((item, i) => {
        const cantidad = esNumero(item.cantidad) ? `${numero(item.cantidad, 3)}${item.unidad ? ` ${item.unidad}` : ''} — ` : ''
        return { campo: items.length === 1 ? 'Ítem' : `Ítem ${i + 1}`, valor: `${cantidad}${item.descripcion ?? '—'}` }
      })
      return [...datosBase, ...filasItems]
    },
  },

  formula: {
    principales: ['nombre', 'tipo', 'activo', 'descripcion'],
    frase: (row, verbo) => {
      const nombre = nombreFormulaDeEtiqueta(row)
      const antes = row.valores_antes ?? {}
      const despues = row.valores_despues ?? {}
      if (row.tipo_accion === 'EDITAR' && 'tipo' in antes && 'tipo' in despues && antes.tipo !== despues.tipo) {
        const nombreSolo = despues.nombre ?? antes.nombre ?? nombre.replace(/\s*\([^)]*\)$/, '')
        return `cambió el tipo de la fórmula ${nombreSolo} de ${NOMBRE_TIPO[antes.tipo] ?? antes.tipo} a ${NOMBRE_TIPO[despues.tipo] ?? despues.tipo}`
      }
      if (row.tipo_accion === 'EDITAR' && Object.keys(despues).length === 1 && 'activo' in despues) {
        return `${despues.activo ? 'activó' : 'desactivó'} la fórmula ${nombre}`
      }
      return `${verbo({ CREAR: 'creó', EDITAR: 'modificó', ELIMINAR: 'eliminó', CAMBIAR_ESTADO: 'cambió el estado de' })} la fórmula ${nombre}`
    },
    especial: (antes, despues) => (Array.isArray(antes.insumos) || Array.isArray(despues.insumos) ? cambiosInsumos(antes.insumos, despues.insumos) : []),
    datosEspeciales: (registro, contexto, datosBase) => {
      const insumos = Array.isArray(registro?.insumos) ? registro.insumos : []
      return [...datosBase, ...insumos.map((i) => ({ campo: i.material ?? 'Insumo', valor: textoInsumo(i) }))]
    },
  },

  patente: {
    principales: ['patente', 'tipo_camion', 'es_externa', 'tara', 'chofer_habitual'],
  },

  // Impresión o PDF de un vale/remito (migración 65). El registro guarda lo
  // que salió en el papel: acumulado, vales, N° de remito, vez y, si cambió,
  // la impresión anterior.
  impresion: {
    frase: (row) => {
      const d = row.valores_despues ?? {}
      const papel = d.modo === 'remito' ? `el remito ${d.remito ? formatearNumeroRemito(d.remito) : 'sin número'}` : `el vale ${d.vale ?? row.entidad_ref ?? ''}`.trim()
      const accion = d.salida === 'pdf' ? 'bajó en PDF' : Number(d.vez) > 1 ? 'reimprimió' : 'imprimió'
      const pedido = d.pedido ? ` del pedido ${d.pedido}` : ''
      const cantidad = esNumero(d.acumulado_tn) ? `${numero(d.acumulado_tn)} tn` : null
      return `${accion} ${conDetalle(`${papel}${pedido}`, [cantidad, textoCantidadVales(d.vales)])}`
    },
    datosEspeciales: (registro) => {
      const d = registro ?? {}
      const datos = [
        { campo: 'Documento', valor: d.modo === 'remito' ? `Remito ${d.remito ? formatearNumeroRemito(d.remito) : 'sin número'} (desde el vale ${d.vale})` : `Vale ${d.vale}` },
      ]
      if (d.pedido) datos.push({ campo: 'Pedido', valor: d.pedido })
      if (esNumero(d.acumulado_tn)) datos.push({ campo: 'Cantidad impresa (acumulado)', valor: `${numero(d.acumulado_tn)} tn` })
      if (Array.isArray(d.vales) && d.vales.length) datos.push({ campo: 'Vales incluidos', valor: textoListaVales(d.vales) })
      datos.push({ campo: 'Desde', valor: d.origen === 'despachos' ? 'Despachos' : 'Báscula' })
      datos.push({ campo: 'Salida', valor: d.salida === 'pdf' ? 'PDF descargado' : 'Impresora' })
      datos.push({ campo: 'Vez', valor: Number(d.vez) > 1 ? `Reimpresión (${d.vez}.ª vez)` : 'Primera vez' })
      if (d.anterior) {
        const a = d.anterior
        const partes = [esNumero(a.acumulado_tn) ? `${numero(a.acumulado_tn)} tn` : null, textoCantidadVales(a.vales), a.remito && a.remito !== d.remito ? `remito ${formatearNumeroRemito(a.remito)}` : null]
        datos.push({ campo: 'La impresión anterior decía', valor: `${partes.filter(Boolean).join(', ')}${a.fecha_hora ? ` (${fecha(a.fecha_hora)})` : ''}` })
      }
      return datos
    },
  },

  usuario_rol: {
    principales: ['email', 'rol', 'activo', 'ver_todas_obras', 'ver_ventas', 'obra_ids', 'telefono'],
    frase: (row, verbo) => {
      const [email, rol] = partesEtiqueta(row)
      return `${verbo({ CREAR: 'dio de alta', EDITAR: 'modificó' })} al usuario ${conDetalle(email ?? row.entidad_ref ?? '', [rol])}`
    },
  },
}

/** "8 vales" */
function textoCantidadVales(vales) {
  if (!Array.isArray(vales) || !vales.length) return null
  return vales.length === 1 ? '1 vale' : `${vales.length} vales`
}

/** [10220, 10221, 10222, 10225] → "10220 al 10222, 10225 (4 vales)". */
function textoListaVales(vales) {
  const numeros = [...new Set(vales.map(Number))].sort((a, b) => a - b)
  const tramos = []
  for (const n of numeros) {
    const ultimo = tramos[tramos.length - 1]
    if (ultimo && n === ultimo[1] + 1) ultimo[1] = n
    else tramos.push([n, n])
  }
  const texto = tramos.map(([desde, hasta]) => (desde === hasta ? `${desde}` : `${desde} al ${hasta}`)).join(', ')
  return `${texto} (${textoCantidadVales(numeros)})`
}

/** Insumos de una fórmula antes/después, comparados por material. */
function cambiosInsumos(antes, despues) {
  const clave = (i) => String(i?.material ?? '').trim().toUpperCase()
  const mapaAntes = new Map((Array.isArray(antes) ? antes : []).map((i) => [clave(i), i]))
  const mapaDespues = new Map((Array.isArray(despues) ? despues : []).map((i) => [clave(i), i]))
  const filas = []
  for (const [material, d] of mapaDespues) {
    const a = mapaAntes.get(material)
    if (!a) filas.push({ campo: d.material, antes: null, despues: `${textoInsumo(d)} (se agregó)` })
    else if (Number(a.cantidad) !== Number(d.cantidad) || (a.unidad ?? '') !== (d.unidad ?? '')) {
      filas.push({ campo: d.material, antes: textoInsumo(a), despues: textoInsumo(d) })
    }
  }
  for (const [material, a] of mapaAntes) {
    if (!mapaDespues.has(material)) filas.push({ campo: a.material, antes: textoInsumo(a), despues: 'se quitó' })
  }
  return filas
}

// ---------- Armado del detalle ----------

const VERBOS_GENERICOS = {
  CREAR: 'creó',
  EDITAR: 'modificó',
  CAMBIAR_ESTADO: 'cambió el estado de',
  ANULAR: 'anuló',
  CORREGIR: 'corrigió',
  REASIGNAR: 'reasignó',
  ELIMINAR: 'eliminó',
  SIMULAR: 'simuló',
  IMPRIMIR: 'imprimió',
}

function fraseMaestro(row, verbo) {
  const sujeto = SUJETO_MAESTRO[row.entidad]
  const etiqueta = String(row.entidad_label ?? '')
  const despues = row.valores_despues ?? {}
  // Solo cambió activo: activó/desactivó.
  const soloActivo = row.tipo_accion !== 'CREAR' && Object.keys(despues).length === 1 && 'activo' in despues
  const accion = soloActivo
    ? despues.activo
      ? 'activó'
      : 'desactivó'
    : verbo({ CREAR: 'dio de alta', EDITAR: 'modificó', ELIMINAR: 'eliminó' })
  // La etiqueta empieza con el nombre de la entidad ("Material 0/3"): se
  // reemplaza por el artículo ("el material 0/3"). Una fila de migración
  // trae otra etiqueta ("Unificación de nombres de proveedores").
  const nombreEntidad = sujeto?.replace(/^(el|la) /, '') ?? ''
  if (sujeto && etiqueta.toLowerCase().startsWith(`${nombreEntidad} `)) {
    return `${accion} ${sujeto} ${etiqueta.slice(nombreEntidad.length + 1)}`
  }
  return `${accion}: ${etiqueta || row.entidad_ref || row.entidad}`
}

function iguales(a, b) {
  return JSON.stringify(a ?? null) === JSON.stringify(b ?? null)
}

function definicion(entidad, clave) {
  return ENTIDADES[entidad]?.campos?.[clave] ?? CAMPOS_COMUNES[clave] ?? null
}

function etiquetaCampo(entidad, clave) {
  return definicion(entidad, clave)?.label ?? nombreLegible(clave)
}

function valorLegible(entidad, clave, valor, contexto) {
  return formatear(valor, definicion(entidad, clave), contexto)
}

// En un alta, estos valores son los de siempre y no dicen nada ("Activo: Sí").
const VALORES_POR_DEFECTO_ALTA = { activo: true, anulado: false, archivado: false }
// Sin `principales`, el nombre del registro va primero.
const PRIMERAS_CLAVES = ['nombre', 'patente', 'email']

function datosPrincipales(row, registro, contexto) {
  const config = ENTIDADES[row.entidad]
  const claves =
    config?.principales ??
    Object.keys(registro ?? {}).sort((a, b) => {
      const ia = PRIMERAS_CLAVES.indexOf(a)
      const ib = PRIMERAS_CLAVES.indexOf(b)
      return (ia === -1 ? PRIMERAS_CLAVES.length : ia) - (ib === -1 ? PRIMERAS_CLAVES.length : ib)
    })
  const datos = []
  for (const clave of claves) {
    const valor = registro?.[clave]
    if (valor === null || valor === undefined || valor === '') continue
    if (esTecnico(clave, valor)) continue
    if (row.tipo_accion === 'CREAR' && VALORES_POR_DEFECTO_ALTA[clave] === valor) continue
    datos.push({ campo: etiquetaCampo(row.entidad, clave), valor: valorLegible(row.entidad, clave, valor, contexto) })
    if (datos.length >= 14) break
  }
  if (config?.datosEspeciales) {
    const especiales = config.datosEspeciales(registro, contexto, datos)
    if (especiales) return especiales
  }
  return datos
}

/** Nombre de quien hizo la acción: el directorio actual primero (si se cargó el nombre después). */
export function nombreUsuarioAuditoria(row, nombres = {}) {
  if (row.usuario_nombre === USUARIO_SISTEMA || row.usuario_email === USUARIO_SISTEMA) return 'Sistema (SQL directo)'
  return nombres[row.usuario_email] || row.usuario_nombre || row.usuario_email || 'Alguien'
}

/** Solo la frase (columna "Resumen" del Excel). */
export function fraseAuditoria(row, contexto = {}) {
  const config = ENTIDADES[row.entidad]
  const verbo = (mapa) => mapa?.[row.tipo_accion] ?? VERBOS_GENERICOS[row.tipo_accion] ?? String(row.tipo_accion ?? '').toLowerCase()
  let accion
  if (config?.frase) accion = config.frase(row, verbo)
  else if (SUJETO_MAESTRO[row.entidad]) accion = fraseMaestro(row, verbo)
  else accion = `${verbo({})} ${row.entidad_label || row.entidad_ref || row.entidad || 'un registro'}`
  return `${nombreUsuarioAuditoria(row, contexto.nombres)} ${accion}`.replace(/\s+/g, ' ').trim()
}

/**
 * row: fila de plantas_auditoria. contexto: { nombres, catalogos }.
 * Devuelve { frase, motivo, cambios: [{ campo, antes, despues }], datos: [{ campo, valor }], nota }.
 * `antes` null en un cambio = el dato no existía antes (se muestra solo el nuevo).
 */
export function presentarRegistro(row, contexto = {}) {
  const config = ENTIDADES[row.entidad]
  const ctx = { ...contexto, unidad: unidadDelRegistro(row) }
  const frase = fraseAuditoria(row, contexto)

  const esObjeto = (v) => v && typeof v === 'object' && !Array.isArray(v)
  const antes = esObjeto(row.valores_antes) ? row.valores_antes : null
  const despues = esObjeto(row.valores_despues) ? row.valores_despues : null

  let motivo = row.motivo && String(row.motivo).trim() ? String(row.motivo).trim() : null
  if (!motivo) {
    for (const clave of CAMPOS_MOTIVO) {
      const valor = despues?.[clave] ?? (row.tipo_accion === 'ELIMINAR' ? antes?.[clave] : null)
      if (valor && String(valor).trim()) {
        motivo = String(valor).trim()
        break
      }
    }
  }

  // Alta, baja o fila sin "antes": solo los datos principales del registro.
  if (!antes || !despues || row.tipo_accion === 'CREAR' || row.tipo_accion === 'ELIMINAR') {
    const registro = row.tipo_accion === 'ELIMINAR' ? antes ?? despues : despues ?? antes
    const datos = datosPrincipales(row, registro, ctx)
    let nota = null
    if (!antes && row.tipo_accion === 'EDITAR') nota = 'No se guardaron los datos anteriores: se muestran los datos que quedaron.'
    if (!datos.length) nota = 'Este registro no guarda datos visibles (ver datos técnicos).'
    return { frase, motivo, cambios: [], datos, nota }
  }

  // Orden: el de los datos principales de la entidad; el resto, como vienen.
  const orden = config?.principales ?? []
  const claves = [...new Set([...Object.keys(antes), ...Object.keys(despues)])].sort((a, b) => {
    const ia = orden.indexOf(a)
    const ib = orden.indexOf(b)
    return (ia === -1 ? orden.length : ia) - (ib === -1 ? orden.length : ib)
  })
  const cambios = config?.especial ? config.especial(antes, despues, ctx) : []
  for (const clave of claves) {
    if (esTecnico(clave, antes[clave]) || esTecnico(clave, despues[clave])) continue
    if (iguales(antes[clave], despues[clave])) continue
    cambios.push({
      campo: etiquetaCampo(row.entidad, clave),
      antes: clave in antes ? valorLegible(row.entidad, clave, antes[clave], ctx) : null,
      despues: clave in despues ? valorLegible(row.entidad, clave, despues[clave], ctx) : '—',
    })
  }
  return { frase, motivo, cambios, datos: [], nota: cambios.length ? null : 'No hay datos visibles que hayan cambiado (ver datos técnicos).' }
}
