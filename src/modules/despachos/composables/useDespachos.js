// Composable de Despachos: listado paginado + filtros, resumen por obra,
// modal de detalle de cargas, corrección post-despacho y remito imprimible.
// DespachosView.vue queda como template puro (memory/conventions.md).
//
// Orden del 17/11/2026 (propuesta aprobada por Federico): un solo período
// (atajos Este mes / Mes anterior / Todo / Rango) y un solo selector de
// destino (obra o cliente) que gobiernan la tabla, sus totales y el Resumen
// por obra; los filtros se aplican solos. Se fueron los KPIs del mes, el
// acumulado histórico y la producción de asfalto del año (están en Home) y el
// segundo selector de mes del Resumen por obra.
//
// Despachos es una vista SOBRE plantas_pedidos (estado='despachado'), no una
// entidad propia — memory/relevamiento-sistema-viejo.md §3 / Logica sist
// plantas v2.rtf §3.5. La cantidad REAL/DIFERENCIA de cada fila es siempre
// cantidad_despachada del pedido (cantidadReal del remito final cargado en
// Pedidos) — memory/business-rules.md, "Fuente de verdad según el tipo de
// transacción".

import { computed, nextTick, reactive, ref, watch } from 'vue'
import {
  fetchDespachos,
  fetchTodosLosDespachosFiltrados,
  rangoDelMes,
  fetchCargasDelPedido,
  fetchValesDelPedido,
  fetchValeCompleto,
  corregirDespacho,
} from '@/services/despachos.service'
import { fetchObras } from '@/services/flota.service'
import { useAvisoPisoStock, inicioVentanaRecortes } from '@/modules/stock/composables/useAvisoPisoStock'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'
// Catálogo de clientes de venta externa (2026-09-14, filtro "Cliente externo"
// pedido por Federico) — mismo catálogo que ya usa el <select> de Pedidos
// (migración 35), no se duplica la query.
import { clientesService } from '@/modules/maestros/services/maestros.service'
import { LISTA_TIPOS_PRODUCTO, magnitudTotales, nombreTipoProducto, sumarEnTotal, totalesVacios } from '@/config/tipos-producto'
import { patentesService } from '@/modules/maestros/services/maestros.service'
// Reuso de Báscula (memory/conventions.md: no duplicar lógica compartida
// entre módulos) — el acumulado dinámico del día y el formato de N° de vale
// son exactamente los mismos que usa ValeImprimible.vue desde BasculaView.
import { obtenerAcumuladoHastaFecha, registrarImpresion, formatearNumeroVale } from '@/modules/bascula/services/bascula.service'
import { fetchDatosInformeMensual } from '@/modules/despachos/services/informe-mensual.service'
import {
  generarRemitoManual,
  fetchRemitosManuales,
  fetchItemsDeRemitoManual,
  UNIDADES_REMITO_MANUAL,
} from '@/modules/despachos/services/remitos-manuales.service'

const TAMANO_PAGINA = 20

/** 'YYYY-MM' del mes actual (desplazamiento 0) o del anterior (-1), en hora local. */
function claveMes(desplazamiento = 0) {
  const hoy = new Date()
  const d = new Date(hoy.getFullYear(), hoy.getMonth() + desplazamiento, 1)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}

/** Atajos de período (17/11/2026). `rango` deja editar desde/hasta a mano. */
export const PERIODOS = [
  { valor: 'mes', label: 'Este mes' },
  { valor: 'anterior', label: 'Mes anterior' },
  { valor: 'todo', label: 'Todo' },
  { valor: 'rango', label: 'Rango' },
]

export function useDespachos() {
  const { revisarRecortesPorPiso } = useAvisoPisoStock()
  const error = ref(null)

  // -------------------------------------------------------------------------
  // Datos base (obras + fórmulas, para filtros y para resolver nombres)
  // -------------------------------------------------------------------------

  const obras = ref([])
  const formulas = ref([])
  // Patentes: solo para resolver Propio/Tercero en el remito/vale imprimible
  // (ValeImprimible.vue#transporteLabel, mismo criterio que Báscula) — no se
  // usa en ningún otro lado de esta vista.
  const patentes = ref([])
  // Clientes de venta externa (2026-09-14): solo para el filtro "Cliente
  // externo" de abajo — a diferencia de Pedidos, acá no hace falta el
  // fallback "(no está en el catálogo)" porque es un filtro, no un campo que
  // se guarda (un cliente_externo que no está en el catálogo simplemente no
  // aparece como opción de filtro, no hay nada que perder).
  const clientes = ref([])
  const obrasPorId = computed(() => Object.fromEntries(obras.value.map((o) => [o.id, o])))
  const formulasPorId = computed(() => Object.fromEntries(formulas.value.map((f) => [f.id, f])))

  function destinoDe(pedido) {
    if (!pedido) return ''
    return pedido.tipo_pedido === 'venta' ? pedido.cliente_externo || '—' : obrasPorId.value[pedido.obra_id]?.nombre || '—'
  }

  async function cargarBase() {
    // Fix 2026-09-01: sin try/catch acá, un fallo de red rechazaba la
    // promesa que consume iniciar() sin `.catch()` — error no manejado en
    // consola, cargarDespachos()/cargarResumenPorObra() nunca se llamaban,
    // y la vista quedaba mostrando "No hay despachos que coincidan con el
    // filtro" (falso estado vacío, `cargando` nunca pasaba a `true`) en vez
    // del error real. Mismo patrón que ya usan cargarBase() en
    // useBascula.js/useSimulador.js.
    try {
      const [listaObras, listaFormulas, listaPatentes, listaClientes] = await Promise.all([
        fetchObras(),
        fetchFormulas({ soloActivas: false }),
        patentesService.fetch(),
        clientesService.fetch(),
      ])
      obras.value = listaObras
      formulas.value = listaFormulas
      patentes.value = listaPatentes
      clientes.value = listaClientes
    } catch (e) {
      error.value = e.message
    }
  }

  // -------------------------------------------------------------------------
  // Listado + filtros + paginación
  // -------------------------------------------------------------------------

  const filas = ref([])
  const totalDespachos = ref(0)
  const paginaActual = ref(1)
  const cargando = ref(false)
  const filtros = reactive({ tipo: '', obraId: '', formulaId: '', clienteExterno: '', desde: '', hasta: '' })

  // Período: por defecto, el mes en curso. Los atajos completan desde/hasta;
  // "Rango" los deja como estén para editarlos.
  const periodo = ref('mes')

  function fechasDelPeriodo(valor) {
    if (valor === 'mes') return rangoDelMes(claveMes(0))
    if (valor === 'anterior') return rangoDelMes(claveMes(-1))
    if (valor === 'todo') return { desde: '', hasta: '' }
    return null
  }

  function elegirPeriodo(valor) {
    periodo.value = valor
    const fechas = fechasDelPeriodo(valor)
    if (fechas) Object.assign(filtros, fechas)
  }
  elegirPeriodo('mes')

  // Destino: un solo selector para obra propia o cliente de venta externa
  // (antes eran dos). Valor 'obra:<id>' o 'cliente:<nombre>'; '' = todos.
  const destino = computed({
    get: () => (filtros.obraId ? `obra:${filtros.obraId}` : filtros.clienteExterno ? `cliente:${filtros.clienteExterno}` : ''),
    set: (valor) => {
      filtros.obraId = valor.startsWith('obra:') ? valor.slice(5) : ''
      filtros.clienteExterno = valor.startsWith('cliente:') ? valor.slice(8) : ''
    },
  })

  function enriquecerFila(p) {
    return {
      ...p,
      destino: destinoDe(p),
      formulaNombre: formulasPorId.value[p.formula_id]?.nombre ?? '—',
      diferencia: Number(p.cantidad_solicitada) - Number(p.cantidad_despachada ?? 0),
    }
  }

  const filasConNombres = computed(() => filas.value.map(enriquecerFila))

  function filtrosParaService() {
    return {
      tipo: filtros.tipo || undefined,
      obraId: filtros.obraId || undefined,
      formulaId: filtros.formulaId || undefined,
      clienteExterno: filtros.clienteExterno || undefined,
      desde: filtros.desde || undefined,
      hasta: filtros.hasta || undefined,
    }
  }

  // -------------------------------------------------------------------------
  // Totales consolidados del filtro + "Exportar filtro a Excel" (2026-09-22,
  // pedido explícito de Federico): a diferencia de `filas` (una página de
  // `fetchDespachos`), acá se trae el universo COMPLETO que matchea el
  // filtro actual — necesario para que el total no quede acotado a lo que
  // se ve en pantalla, y para que el Excel exportado tenga todas las filas,
  // no solo la página visible. Se recarga junto con `cargarDespachos()`
  // (mismos filtros, un fetch más, no se comparte con el paginado porque
  // Supabase no devuelve "todas las filas + count" en una sola llamada).
  // -------------------------------------------------------------------------

  const cargandoTotalesFiltro = ref(false)
  const todosFiltrados = ref([])

  const totalesFiltro = computed(() => {
    const totales = totalesVacios()
    for (const p of todosFiltrados.value) sumarEnTotal(totales, p.tipo, p.cantidad_despachada)
    return { ...totales, cantidadDespachos: todosFiltrados.value.length }
  })

  // Una tarjeta por tipo (config/tipos-producto.js): con un tipo elegido en el
  // filtro, solo ese (aunque dé 0); con "Todos", los que tengan producción.
  const tiposTotalesFiltro = computed(() =>
    filtros.tipo
      ? LISTA_TIPOS_PRODUCTO.filter((t) => t.id === filtros.tipo)
      : LISTA_TIPOS_PRODUCTO.filter((t) => totalesFiltro.value[t.total] > 0)
  )

  async function cargarTotalesFiltro() {
    cargandoTotalesFiltro.value = true
    try {
      const todos = await fetchTodosLosDespachosFiltrados(filtrosParaService())
      todosFiltrados.value = todos.map(enriquecerFila)
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoTotalesFiltro.value = false
    }
  }

  const exportandoFiltro = ref(false)

  /** Línea legible de qué filtros estaban activos — va dentro del Excel
   * (excel-despachos-filtro.js) para que el archivo se explique solo. */
  const resumenFiltrosLabel = computed(() => {
    const partes = []
    if (filtros.tipo) partes.push(`Tipo: ${nombreTipoProducto(filtros.tipo)}`)
    if (filtros.obraId) partes.push(`Obra: ${obrasPorId.value[filtros.obraId]?.nombre ?? filtros.obraId}`)
    if (filtros.formulaId) partes.push(`Mezcla: ${formulasPorId.value[filtros.formulaId]?.nombre ?? filtros.formulaId}`)
    if (filtros.clienteExterno) partes.push(`Cliente: ${filtros.clienteExterno}`)
    if (filtros.desde) partes.push(`Desde: ${filtros.desde}`)
    if (filtros.hasta) partes.push(`Hasta: ${filtros.hasta}`)
    return partes.length ? partes.join(' · ') : 'Sin filtros (todos los despachos)'
  })

  async function exportarFiltroExcel() {
    exportandoFiltro.value = true
    error.value = null
    try {
      const { exportarDespachosFiltroExcel } = await import('@/modules/despachos/services/excel-despachos-filtro')
      // Si `todosFiltrados` quedó desactualizado (no debería, se recarga en
      // cada aplicarFiltros/limpiarFiltros/iniciar) se refresca antes de
      // exportar — más seguro que confiar en el estado en memoria del
      // cliente para un archivo que se va a guardar.
      await cargarTotalesFiltro()
      await exportarDespachosFiltroExcel(todosFiltrados.value, resumenFiltrosLabel.value)
    } catch (e) {
      error.value = e.message
    } finally {
      exportandoFiltro.value = false
    }
  }

  async function cargarPaginaDespachos() {
    cargando.value = true
    error.value = null
    try {
      const resultado = await fetchDespachos(filtrosParaService(), {
        pagina: paginaActual.value,
        tamanoPagina: TAMANO_PAGINA,
      })
      filas.value = resultado.filas
      totalDespachos.value = resultado.total
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
  }

  // Trae la página actual + recalcula los totales del filtro completo — los
  // totales solo dependen de `filtros`, no de `paginaActual`, así que
  // cambiar de página (cambiarPagina()) no hace falta que los vuelva a
  // pedir (ver más abajo).
  async function cargarDespachos() {
    await Promise.all([cargarPaginaDespachos(), cargarTotalesFiltro()])
  }

  function aplicarFiltros() {
    paginaActual.value = 1
    cargarDespachos()
  }

  // Los filtros se aplican solos (sin botón "Filtrar"). Pausa corta para no
  // pedir datos con cada tecla de una fecha a medio escribir.
  let pausa = null
  let filtrosListos = false
  watch(
    () => ({ ...filtros }),
    () => {
      if (!filtrosListos) return
      clearTimeout(pausa)
      pausa = setTimeout(aplicarFiltros, 300)
    },
  )

  function limpiarFiltros() {
    filtros.tipo = ''
    filtros.obraId = ''
    filtros.formulaId = ''
    filtros.clienteExterno = ''
    elegirPeriodo('mes')
  }

  function cambiarPagina(pagina) {
    paginaActual.value = pagina
    cargarPaginaDespachos()
  }

  // -------------------------------------------------------------------------
  // Resumen por obra: el mismo universo que la tabla y sus totales (período,
  // tipo, destino y mezcla de los filtros), agrupado por obra o cliente —
  // mismo agrupamiento que fetchResumenPorObra (despachos.service.js), sin un
  // segundo selector de mes ni otra consulta.
  // -------------------------------------------------------------------------

  const resumenObras = computed(() => {
    const porDestino = new Map()
    for (const p of todosFiltrados.value) {
      const clave = p.obra_id ?? `venta:${p.cliente_externo || 'sin nombre'}`
      if (!porDestino.has(clave)) {
        porDestino.set(clave, {
          obraId: p.obra_id,
          nombre: p.obra_id ? obrasPorId.value[p.obra_id]?.nombre || `Obra #${p.obra_id}` : p.cliente_externo || 'Venta externa',
          ...totalesVacios(),
          cantidadDespachos: 0,
        })
      }
      const acc = porDestino.get(clave)
      sumarEnTotal(acc, p.tipo, p.cantidad_despachada)
      acc.cantidadDespachos += 1
    }
    return Array.from(porDestino.values()).sort((a, b) => magnitudTotales(b) - magnitudTotales(a))
  })

  // -------------------------------------------------------------------------
  // Informe mensual en Excel (2026-09-02; desde el 17/11/2026 solo desde el
  // botón "Descargar informe mensual" de arriba, con su propio mes): .xlsx
  // completo (Resumen mensual + Resumen anual + una hoja por obra/cliente),
  // el mismo que va adjunto en el informe por mail.
  // Import dinámico de exceljs (misma razón que xlsx en Báscula/Stock: no
  // inflar el chunk de Despachos con una librería pesada que no todos usan).
  // -------------------------------------------------------------------------

  const exportandoInforme = ref(false)

  async function exportarInformeMensual(mes) {
    exportandoInforme.value = true
    error.value = null
    try {
      const [datos, { generarInformeMensualExcel }] = await Promise.all([
        fetchDatosInformeMensual(mes),
        import('@/modules/despachos/services/excel-informe-mensual'),
      ])
      await generarInformeMensualExcel(datos)
    } catch (e) {
      error.value = e.message
    } finally {
      exportandoInforme.value = false
    }
  }

  // -------------------------------------------------------------------------
  // "Descargar informe mensual" (2026-11-02, pedido de Federico: botón arriba
  // de todo, igual al de Combustible en Flota). Mes por defecto: el anterior
  // (el último cerrado).
  // -------------------------------------------------------------------------

  const modalInformeAbierto = ref(false)
  const mesInforme = ref('')

  function abrirModalInforme() {
    mesInforme.value = claveMes(-1)
    modalInformeAbierto.value = true
  }

  async function descargarInformeDelMes() {
    if (!mesInforme.value) {
      error.value = 'Elegí el mes del informe.'
      return
    }
    await exportarInformeMensual(mesInforme.value)
    if (!error.value) modalInformeAbierto.value = false
  }

  // -------------------------------------------------------------------------
  // Modal "Ver detalle de cargas" (🚛) — patente + cantidad + remito/vale por
  // camión, rango de N° al pie (memory/relevamiento-sistema-viejo.md Etapa 3).
  // -------------------------------------------------------------------------

  const modalDetalleAbierto = ref(false)
  const pedidoDetalle = ref(null)
  const cargasDetalle = ref([])
  const cargandoDetalle = ref(false)

  const rangoNumerosDetalle = computed(() => {
    const numeros = cargasDetalle.value.map((c) => c.numeroRemitoOVale).filter(Boolean)
    if (!numeros.length) return '—'
    return numeros.length === 1 ? numeros[0] : `${numeros[0]}…${numeros[numeros.length - 1]}`
  })

  async function abrirDetalle(pedido) {
    pedidoDetalle.value = pedido
    modalDetalleAbierto.value = true
    cargandoDetalle.value = true
    error.value = null
    try {
      cargasDetalle.value = await fetchCargasDelPedido(pedido.id, pedido.tipo)
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoDetalle.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Modal "Corregir despacho" — Logica sis. plantas v1.rtf §5: solo sobre un
  // despacho ya cerrado, edita cantidadReal/remito/vale/notas.
  // -------------------------------------------------------------------------

  const modalCorregirAbierto = ref(false)
  const pedidoCorregir = ref(null)
  const formCorregir = reactive({ cantidadDespachada: null, nroRemitoGlobal: '', nroValeGlobal: '', notas: '' })
  const corrigiendo = ref(false)

  function abrirCorreccion(pedido) {
    pedidoCorregir.value = pedido
    formCorregir.cantidadDespachada = pedido.cantidad_despachada
    formCorregir.nroRemitoGlobal = pedido.nro_remito_global || ''
    formCorregir.nroValeGlobal = pedido.nro_vale_global || ''
    formCorregir.notas = ''
    error.value = null
    modalCorregirAbierto.value = true
  }

  async function guardarCorreccion() {
    if (!(Number(formCorregir.cantidadDespachada) > 0)) {
      error.value = 'La cantidad corregida debe ser mayor a 0.'
      return
    }
    // Motivo obligatorio (migración 60): la RPC lo exige y queda en la auditoría.
    if (!formCorregir.notas.trim()) {
      error.value = 'Indicá el motivo de la corrección.'
      return
    }
    corrigiendo.value = true
    error.value = null
    try {
      const desde = inicioVentanaRecortes()
      await corregirDespacho(pedidoCorregir.value.id, {
        cantidadDespachada: Number(formCorregir.cantidadDespachada),
        nroRemitoGlobal: formCorregir.nroRemitoGlobal.trim() || null,
        nroValeGlobal: formCorregir.nroValeGlobal.trim() || null,
        notas: formCorregir.notas.trim() || null,
      })
      // Aviso si el piso en 0 recortó el descuento de la corrección.
      revisarRecortesPorPiso(pedidoCorregir.value, desde)
      modalCorregirAbierto.value = false
      await cargarDespachos()
    } catch (e) {
      error.value = e.message
    } finally {
      corrigiendo.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Modal "Ver remito" imprimible — SOLO para Remito Manual desde acá
  // (2026-09-14, pedido de Federico: el botón "Remito" por pedido despachado
  // se removió de esta vista, esa impresión queda únicamente en Báscula
  // sobre un vale ya pesado — abrirImpresionRemito). Antes este modal
  // también servía para el remito de un despacho puntual (abrirRemito(),
  // DespachoImprimible.vue) — ver historial de git si hace falta esa
  // versión.
  // -------------------------------------------------------------------------

  const modalRemitoAbierto = ref(false)

  // Fix 2026-09-14 (pedido de Federico: el Remito Manual salía en horizontal,
  // tenía que ser vertical "para mantener la misma línea visual que el resto
  // de los remitos del sistema"). Mismo mecanismo ya usado por
  // useBascula.js#imprimir() para su propio remito: se inyecta un <style>
  // con `@page { size: A4 portrait }` justo antes de imprimir — como es la
  // última regla `@page` del documento, gana por cascada sobre el `@page
  // landscape` global de main.css — y se remueve enseguida después de
  // `window.print()` para no afectar el modal de "Imprimir vale" (asfalto,
  // sigue landscape, 2 copias lado a lado), que reusa esta misma función.
  // Se activa solo cuando el modal abierto es el del remito (de despacho o
  // manual, los dos usan RemitoImprimible.vue con la clase `modo-remito` en
  // DespachosView.vue) — el de vale no toca este ref.
  async function imprimir() {
    if (modalImpresionValeAbierto.value) await prepararImpresionVale('impresora')
    let estiloTemporal = null
    if (modalRemitoAbierto.value) {
      estiloTemporal = document.createElement('style')
      estiloTemporal.textContent = '@page { size: A4 portrait; margin: 0; }'
      document.head.appendChild(estiloTemporal)
    }
    window.print()
    estiloTemporal?.remove()
  }

  // -------------------------------------------------------------------------
  // "Remito Manual/Blanco" (migración 36+37, 2026-09-09, pedido de
  // Federico): remito oficial sin pedido asociado — envío de materiales a
  // obra u otro movimiento interno, con N items (cantidad/descripción,
  // "+ Agregar item" — mismo patrón multi-fila que useDespachoAsfalto.js/
  // useCargaHormigon.js). N° de remito automático, misma secuencia que los
  // remitos de asfalto (RemitoImprimible.vue es el mismo componente único
  // que usa el resto del sistema, ver DespachoImprimible.vue).
  // -------------------------------------------------------------------------

  // Desde el 17/11/2026 tienen su propia pestaña (antes, card plegable arriba
  // de la tabla).
  const remitosManuales = ref([])
  const cargandoRemitosManuales = ref(false)

  async function cargarRemitosManuales() {
    cargandoRemitosManuales.value = true
    try {
      remitosManuales.value = await fetchRemitosManuales()
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoRemitosManuales.value = false
    }
  }

  function itemVacio() {
    return { cantidad: null, unidad: '', descripcion: '' }
  }

  function formRemitoManualVacio() {
    return {
      items: [itemVacio()],
      destino: '',
      patente: '',
      transportista: '',
      fecha: new Date().toISOString().slice(0, 10),
    }
  }

  const modalRemitoManualAbierto = ref(false)
  const formRemitoManual = reactive(formRemitoManualVacio())
  const generandoRemitoManual = ref(false)
  const errorRemitoManual = ref(null)

  function abrirRemitoManual() {
    Object.assign(formRemitoManual, formRemitoManualVacio())
    errorRemitoManual.value = null
    modalRemitoManualAbierto.value = true
  }

  function agregarItemRemitoManual() {
    formRemitoManual.items.push(itemVacio())
  }

  function quitarItemRemitoManual(index) {
    if (formRemitoManual.items.length <= 1) return
    formRemitoManual.items.splice(index, 1)
  }

  // Impresión: reusa el mismo modal/mecanismo que el remito de un despacho
  // (modalRemitoAbierto/imprimir()) — es el mismo documento (RemitoImprimible.vue),
  // solo cambia qué props le arma la vista (ver DespachosView.vue). Forma:
  // { remito: {...fila de plantas_remitos_manuales}, items: [{cantidad, descripcion}] }.
  const remitoManualParaImprimir = ref(null)

  // Props genéricos para RemitoImprimible.vue — mismo mapeo que useBascula.js/
  // DespachoImprimible.vue, acá armado desde plantas_remitos_manuales (sin
  // pedido/obra detrás).
  const remitoManualProps = computed(() => {
    if (!remitoManualParaImprimir.value) return null
    const { remito, items } = remitoManualParaImprimir.value
    return {
      numeroRemito: remito.numero_remito,
      fecha: remito.fecha,
      destino: remito.destino,
      items: items.map((i) => ({
        // Unidad junto a la cantidad ("20 Unidades", "5 Tn") — migración 45.
        // Items anteriores no tienen unidad: salen como antes, solo el número.
        cantidad: i.cantidad != null ? [i.cantidad, i.unidad].filter(Boolean).join(' ') : '',
        detalle: i.descripcion,
      })),
      patente: remito.patente || '',
      transportista: remito.transportista || '',
      lugarEntrega: remito.destino || '',
    }
  })

  async function guardarRemitoManual() {
    const itemsValidos = formRemitoManual.items.filter((i) => i.descripcion.trim())
    if (!itemsValidos.length) {
      errorRemitoManual.value = 'Agregá al menos un item con descripción.'
      return
    }
    if (itemsValidos.some((i) => String(i.cantidad ?? '').trim() && !i.unidad)) {
      errorRemitoManual.value = 'Elegí la unidad de medida de cada item con cantidad.'
      return
    }
    generandoRemitoManual.value = true
    errorRemitoManual.value = null
    try {
      const resultado = await generarRemitoManual({ ...formRemitoManual, items: itemsValidos })
      modalRemitoManualAbierto.value = false
      remitoManualParaImprimir.value = resultado
      modalRemitoAbierto.value = true
      await cargarRemitosManuales()
    } catch (e) {
      errorRemitoManual.value = e.message
    } finally {
      generandoRemitoManual.value = false
    }
  }

  // "Reimprimir" desde el listado: ese registro no trae los items (el
  // listado solo pide la fila de plantas_remitos_manuales, liviano) — se
  // buscan acá recién cuando hace falta imprimir de nuevo.
  async function verRemitoManual(remito) {
    error.value = null
    try {
      const items = await fetchItemsDeRemitoManual(remito.id)
      remitoManualParaImprimir.value = { remito, items }
      modalRemitoAbierto.value = true
    } catch (e) {
      error.value = e.message
    }
  }

  // -------------------------------------------------------------------------
  // "Imprimir vale" (2026-09-02, roadmap Mobile/UX — selector Vale/Remito
  // pedido por Federico para las salidas de asfalto): Despachos ya tenía
  // "Ver remito" (arriba); esto agrega la otra opción, reusando
  // ValeImprimible.vue tal cual lo arma useBascula.js (mismo componente,
  // mismas props — memory/conventions.md, no duplicar el imprimible). Un
  // despacho puede tener 0 vales asociados (hormigón, o asfalto sin pesar en
  // báscula), 1 (caso típico) o varios (multi-camión) — con más de uno se
  // pide elegir cuál antes de abrir el modal de impresión.
  // -------------------------------------------------------------------------

  const modalSeleccionValeAbierto = ref(false)
  const pedidoParaSeleccionVale = ref(null)
  const valesDisponibles = ref([])

  const modalImpresionValeAbierto = ref(false)
  const valeParaImprimir = ref(null)
  const pedidoParaImprimirVale = ref(null)
  const acumuladoParaImprimirVale = ref(null)
  const rangoValesParaImprimirVale = ref({ valeDesde: null, valeHasta: null, cantidadVales: 0 })

  // Impresión auditada (migración 65, mismo criterio que Báscula): se
  // registra antes de imprimir o bajar el PDF, y lo que sale en el papel es
  // lo que devuelve la base. Si el registro falla, se imprime igual y se avisa.
  const avisoImpresionVale = ref(null)

  async function prepararImpresionVale(salida) {
    avisoImpresionVale.value = null
    if (!valeParaImprimir.value?.id) return
    try {
      const { acumulado } = await registrarImpresion(valeParaImprimir.value.id, { modo: 'vale', origen: 'despachos', salida })
      acumuladoParaImprimirVale.value = acumulado.acumuladoTn
      rangoValesParaImprimirVale.value = {
        valeDesde: acumulado.valeDesde,
        valeHasta: acumulado.valeHasta,
        cantidadVales: acumulado.cantidadVales,
      }
      await nextTick()
    } catch (e) {
      avisoImpresionVale.value = `No se pudo registrar la impresión en la auditoría (${e.message}). Se imprime igual.`
    }
  }

  async function abrirVale(valeId, pedido) {
    error.value = null
    avisoImpresionVale.value = null
    try {
      const vale = await fetchValeCompleto(valeId)
      valeParaImprimir.value = vale
      pedidoParaImprimirVale.value = pedido
      modalImpresionValeAbierto.value = true
      const { acumuladoTn, valeDesde, valeHasta, cantidadVales } = await obtenerAcumuladoHastaFecha({
        pedidoId: pedido.id,
        obraId: pedido.obra_id,
        fechaCorte: vale.fecha_pesada,
      })
      acumuladoParaImprimirVale.value = acumuladoTn
      rangoValesParaImprimirVale.value = { valeDesde, valeHasta, cantidadVales }
    } catch (e) {
      error.value = e.message
    }
  }

  async function abrirImpresionVale(pedido) {
    error.value = null
    try {
      const vales = await fetchValesDelPedido(pedido.id)
      if (!vales.length) {
        error.value = 'Este despacho no tiene vales de báscula asociados para imprimir.'
        return
      }
      if (vales.length === 1) {
        await abrirVale(vales[0].id, pedido)
      } else {
        pedidoParaSeleccionVale.value = pedido
        valesDisponibles.value = vales
        modalSeleccionValeAbierto.value = true
      }
    } catch (e) {
      error.value = e.message
    }
  }

  async function elegirVale(valeId) {
    modalSeleccionValeAbierto.value = false
    await abrirVale(valeId, pedidoParaSeleccionVale.value)
  }

  // -------------------------------------------------------------------------
  // Arranque
  // -------------------------------------------------------------------------

  function iniciar() {
    cargarBase().then(() => {
      cargarDespachos()
      filtrosListos = true
    })
    cargarRemitosManuales()
  }

  return {
    error,
    obras,
    formulas,
    patentes,
    clientes,
    obrasPorId,
    formulasPorId,
    filas: filasConNombres,
    totalDespachos,
    paginaActual,
    cargando,
    filtros,
    periodo,
    elegirPeriodo,
    destino,
    TAMANO_PAGINA,
    aplicarFiltros,
    limpiarFiltros,
    cambiarPagina,
    cargarDespachos,
    totalesFiltro,
    tiposTotalesFiltro,
    cargandoTotalesFiltro,
    exportandoFiltro,
    exportarFiltroExcel,
    resumenFiltrosLabel,
    resumenObras,
    exportandoInforme,
    exportarInformeMensual,
    modalInformeAbierto,
    mesInforme,
    abrirModalInforme,
    descargarInformeDelMes,
    modalDetalleAbierto,
    pedidoDetalle,
    cargasDetalle,
    cargandoDetalle,
    rangoNumerosDetalle,
    abrirDetalle,
    modalCorregirAbierto,
    pedidoCorregir,
    formCorregir,
    corrigiendo,
    abrirCorreccion,
    guardarCorreccion,
    modalRemitoAbierto,
    imprimir,
    remitosManuales,
    unidadesRemitoManual: UNIDADES_REMITO_MANUAL,
    cargandoRemitosManuales,
    cargarRemitosManuales,
    modalRemitoManualAbierto,
    formRemitoManual,
    generandoRemitoManual,
    errorRemitoManual,
    abrirRemitoManual,
    agregarItemRemitoManual,
    quitarItemRemitoManual,
    guardarRemitoManual,
    remitoManualParaImprimir,
    remitoManualProps,
    verRemitoManual,
    modalSeleccionValeAbierto,
    pedidoParaSeleccionVale,
    valesDisponibles,
    modalImpresionValeAbierto,
    valeParaImprimir,
    pedidoParaImprimirVale,
    acumuladoParaImprimirVale,
    avisoImpresionVale,
    prepararImpresionVale,
    rangoValesParaImprimirVale,
    abrirImpresionVale,
    elegirVale,
    formatearNumeroVale,
    destinoDe,
    iniciar,
  }
}
