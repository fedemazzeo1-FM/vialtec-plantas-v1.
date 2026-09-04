// Composable de Báscula: toda la lógica de negocio y estado de la vista
// (puertas de pesaje en paralelo, historial paginado + filtros, impresión de
// vale/remito) vive acá — BasculaView.vue queda como template puro que solo
// llama a lo que este composable expone. Nada de acceso a Supabase acá
// tampoco: todo pasa por bascula.service.js (memory/conventions.md).
//
// 3 tipos de puerta (memory/relevamiento-sistema-viejo.md §2 — "3 opciones,
// no 4 como asumíamos"): asfalto (con temperatura opcional), ingreso de
// áridos (suma stock vía plantas_ingresos) y egreso de áridos (no
// suma/resta stock todavía — mismo TODO que ya existía para el descuento de
// stock, ver memory/pending.md). No existe un 4° tipo "hormigón": la báscula
// nunca pesa hormigón (memory/business-rules.md).
//
// Fidelidad con el legado (Etapa 3 del relevamiento, sesión 2026-08-28): UNA
// sola puerta se abre con "+ Abrir puerta" y el tipo se elige/cambia con un
// select DENTRO de la card (no 3 botones que fijan el tipo al crear) —
// confirmado en vivo con form_input. Al guardar un vale de asfalto, se abre
// automáticamente el modal de impresión (Logica sis. plantas v1.rtf §2.4,
// paso 5: "se imprime automáticamente").

import { computed, reactive, ref } from 'vue'
import {
  fetchPedidosAsfaltoParaPesada,
  fetchHistorialVales,
  fetchTodosLosVales,
  registrarPesada,
  obtenerAcumuladoHastaFecha,
  obtenerProximoNumeroVale,
  calcularDiferencia,
  formatearNumeroVale,
} from '@/modules/bascula/services/bascula.service'
import { fetchObras, fetchNombresPorEmail } from '@/services/flota.service'
import { fetchFormulas } from '@/modules/maestros/services/formulas.service'
import { getPedido } from '@/modules/pedidos/services/pedidos.service'
import { patentesService, proveedoresService } from '@/modules/maestros/services/maestros.service'
// Excel con formato corporativo (2026-09-03, pedido de Federico: logo +
// estilo de colores + pie institucional en todos los exports) — reemplaza
// a src/services/excel-export.js (SheetJS, no soporta escribir estilos).
import { exportarPlanillaCorporativa, nombreArchivoConFecha } from '@/services/excel-corporativo'

export const ETIQUETA_TIPO_VALE = {
  asfalto: 'Salida asfalto',
  hormigon: 'Hormigón',
  ingreso_arido: 'Ingreso árido',
  egreso_arido: 'Egreso árido',
}
export const VARIANTE_TIPO_VALE = {
  asfalto: 'info',
  hormigon: 'default',
  ingreso_arido: 'warning',
  egreso_arido: 'danger',
}

// Códigos cortos TIPO/E-S del cuadro "Movimientos del día" (réplica exacta
// del legado, memory/relevamiento-sistema-viejo.md §2, verificado en vivo
// 2026-09-02): la columna TIPO short-codea a "ING"/"VALE" (ambos "Vale
// Asfalto" y "Vale Salida Áridos" quedan como "VALE" — el legado los
// nombra igual, la columna E/S es la que distingue entrada/salida real).
export const TIPO_CORTO_VALE = {
  asfalto: 'VALE',
  hormigon: 'VALE',
  ingreso_arido: 'ING',
  egreso_arido: 'VALE',
}
export const ENTRADA_SALIDA_VALE = {
  asfalto: 'S',
  hormigon: 'S',
  ingreso_arido: 'E',
  egreso_arido: 'S',
}

// Opciones del select de tipo dentro de cada puerta — mismo texto exacto que
// usa el legado ("Vale Asfalto" / "Ingreso Áridos" / "Vale Salida Áridos").
export const OPCIONES_TIPO_PUERTA = [
  { value: 'asfalto', label: 'Vale Asfalto' },
  { value: 'ingreso_arido', label: 'Ingreso Áridos' },
  { value: 'egreso_arido', label: 'Vale Salida Áridos' },
]

// Identificación visual por tipo de puerta (pedido de Federico, 2026-08-28):
// violeta = Vale Asfalto (mismo tono que la marca, #7B2F8E = token `vialtec`),
// verde = Ingreso de Áridos (token `success`), naranja = Egreso de Áridos
// (Tailwind `orange`, no tenemos un token semántico propio para esto todavía).
export const COLOR_PUERTA = {
  asfalto: { borde: 'border-l-vialtec', texto: 'text-vialtec' },
  ingreso_arido: { borde: 'border-l-success', texto: 'text-success' },
  egreso_arido: { borde: 'border-l-orange-500', texto: 'text-orange-600' },
}

// Mismo esquema de color que COLOR_PUERTA de arriba, pero como franja +
// fondo tenue para las FILAS del historial "Movimientos del día" (2026-09-04,
// pedido explícito de Federico: que coincida exacto con el legado — vale
// asfalto violeta, ingreso verde, egreso naranja, memory/pending.md). No se
// reusa COLOR_PUERTA tal cual porque ahí las clases son para una card con
// texto de color (borde + texto), acá es una fila de tabla con fondo tenue
// (borde + bg) — mismo criterio de color, presentación distinta.
export const COLOR_FILA_VALE = {
  asfalto: 'border-l-4 border-l-vialtec bg-vialtec/5',
  ingreso_arido: 'border-l-4 border-l-success bg-success-light',
  egreso_arido: 'border-l-4 border-l-orange-500 bg-orange-50',
}

const TAMANO_PAGINA_HISTORIAL = 50

export function useBascula() {
  const error = ref(null)

  // -------------------------------------------------------------------------
  // Datos base (pedidos para pesar, obras, patentes/proveedores conocidos,
  // fórmulas — estas últimas solo para resolver el nombre de mezcla al
  // imprimir un vale, ver abrirImpresion()).
  // -------------------------------------------------------------------------

  const cargandoBase = ref(false)
  const pedidosParaPesada = ref([])
  const obras = ref([])
  const patentes = ref([])
  const proveedores = ref([])
  const formulas = ref([])

  const obrasPorId = computed(() => Object.fromEntries(obras.value.map((o) => [o.id, o])))
  const pedidosPorId = computed(() => Object.fromEntries(pedidosParaPesada.value.map((p) => [p.id, p])))
  const formulasPorId = computed(() => Object.fromEntries(formulas.value.map((f) => [f.id, f])))

  /**
   * Nombre a mostrar para un pedido en el selector de "Vale Asfalto" (bug
   * real reportado 2026-09-04: "Obra #null" en la gran mayoría de los
   * pedidos). Causa real: una venta externa (`tipo_pedido='venta'`) nunca
   * tiene `obra_id` por diseño — el selector asumía que todo pedido lo
   * tenía. Mismo criterio que `nombreDestinoPedido()` de PlanSemanalView.vue
   * (fix 2026-09-03 análogo, no existe un helper compartido para esto —
   * conventions.md: son 3 formas ligeramente distintas de nombrar según qué
   * objeto trae cada vista, no vale la pena forzar un solo helper transversal
   * por unas pocas líneas).
   */
  function nombreDestinoPedido(p) {
    if (p.tipo_pedido === 'venta') return p.cliente_externo || 'Venta externa'
    if (p.obra_id) return obrasPorId.value[p.obra_id]?.nombre ?? `Obra #${p.obra_id}`
    // obra_id null y NO es venta -> dato huérfano real (memory/pending.md,
    // obra sin equivalente en flota_obras) — fallback legible.
    return 'Obra sin asignar'
  }

  async function cargarBase() {
    cargandoBase.value = true
    try {
      const [listaPedidos, listaObras, listaPatentes, listaProveedores, listaFormulas] = await Promise.all([
        fetchPedidosAsfaltoParaPesada(),
        fetchObras(),
        patentesService.fetch({ soloActivos: true }),
        proveedoresService.fetch({ soloActivos: true }),
        fetchFormulas({ soloActivas: true }),
      ])
      pedidosParaPesada.value = listaPedidos
      obras.value = listaObras
      patentes.value = listaPatentes
      proveedores.value = listaProveedores
      formulas.value = listaFormulas
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoBase.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Próximo N° de vale (header operativo — "X puertas abiertas · Próximo N°
  // 00009580", memory/relevamiento-sistema-viejo.md Etapa 3).
  // -------------------------------------------------------------------------

  const proximoNumeroVale = ref(null)

  async function cargarProximoNumero() {
    try {
      proximoNumeroVale.value = await obtenerProximoNumeroVale()
    } catch (e) {
      error.value = e.message
    }
  }

  // -------------------------------------------------------------------------
  // Puertas de pesaje en paralelo
  // -------------------------------------------------------------------------

  // Sin "puerta activa": el legado muestra todas las puertas abiertas como
  // cards apiladas simultáneamente, cada una colapsable de forma
  // independiente (memory/relevamiento-sistema-viejo.md Etapa 1 §2) — no es
  // un tab-bar de una sola visible a la vez, por eso no hay slotActivoId acá.
  let contadorSlot = 0
  const slots = ref([])

  const puertasAbiertas = computed(() => slots.value.length)

  function formularioVacio(tipo) {
    if (tipo === 'asfalto') {
      return reactive({
        pedido_id: '',
        patente: '',
        chofer: '',
        peso_bruto: null,
        tara: null,
        temperatura: null,
        observaciones: '',
      })
    }
    if (tipo === 'ingreso_arido') {
      // Sin chofer: el legado no lo pide para ingreso de áridos, solo para
      // Vale Asfalto (memory/relevamiento-sistema-viejo.md Etapa 3).
      return reactive({
        material: '',
        proveedor: '',
        numero_remito: '',
        cantidad_remito: null,
        patente: '',
        peso_bruto: null,
        tara: null,
        observaciones: '',
      })
    }
    // egreso_arido — obra_id (select), no destino de texto libre (migración 10).
    return reactive({
      material: '',
      obra_id: '',
      patente: '',
      peso_bruto: null,
      tara: null,
      observaciones: '',
    })
  }

  /** "+ Abrir puerta" único (ya no 3 botones por tipo) — arranca en Vale Asfalto, cambiable con el select interno. */
  function crearSlot(tipoInicial = 'asfalto') {
    contadorSlot += 1
    const slot = { id: contadorSlot, tipo: tipoInicial, form: formularioVacio(tipoInicial), guardando: false, colapsado: false }
    slots.value.push(slot)
  }

  /** Cambia el tipo de una puerta ya abierta y reinicia su formulario (los campos no son compatibles entre tipos). */
  function cambiarTipoSlot(slot, nuevoTipo) {
    if (slot.tipo === nuevoTipo) return
    slot.tipo = nuevoTipo
    slot.form = formularioVacio(nuevoTipo)
  }

  function toggleColapso(slot) {
    slot.colapsado = !slot.colapsado
  }

  function cerrarSlot(id) {
    const idx = slots.value.findIndex((s) => s.id === id)
    if (idx === -1) return
    slots.value.splice(idx, 1)
  }

  function netoSlot(slot) {
    const bruto = Number(slot.form.peso_bruto) || 0
    const tara = Number(slot.form.tara) || 0
    return (bruto - tara).toFixed(2)
  }

  function alCambiarPatente(slot) {
    const encontrada = patentes.value.find((p) => p.patente === slot.form.patente)
    if (encontrada) {
      if (encontrada.tara != null) slot.form.tara = encontrada.tara
      if (encontrada.chofer_habitual && 'chofer' in slot.form) slot.form.chofer = encontrada.chofer_habitual
    }
  }

  async function guardarPesada(slot) {
    const form = slot.form
    if (!(Number(form.peso_bruto) > 0) || form.tara == null || Number(form.tara) < 0) {
      error.value = 'Completá peso bruto y tara.'
      return
    }
    if (slot.tipo === 'asfalto' && !form.pedido_id) {
      error.value = 'Elegí un pedido de asfalto.'
      return
    }
    if (slot.tipo === 'ingreso_arido') {
      if (!form.material || !form.proveedor) {
        error.value = 'Completá material y proveedor del ingreso.'
        return
      }
      if (!form.numero_remito || !form.numero_remito.trim()) {
        error.value = 'El N° de remito es obligatorio en un ingreso de áridos.'
        return
      }
    }
    if (slot.tipo === 'egreso_arido') {
      if (!form.material) {
        error.value = 'Completá el material del egreso.'
        return
      }
      if (!form.obra_id) {
        error.value = 'Elegí la obra de destino del egreso.'
        return
      }
    }

    const pedido = slot.tipo === 'asfalto' ? pedidosParaPesada.value.find((p) => p.id === form.pedido_id) : null

    slot.guardando = true
    error.value = null
    try {
      const valeGuardado = await registrarPesada({
        tipo_vale: slot.tipo,
        pedido_id: slot.tipo === 'asfalto' ? form.pedido_id : null,
        obra_id: slot.tipo === 'egreso_arido' ? form.obra_id : (pedido?.obra_id ?? null),
        patente: form.patente || null,
        chofer: 'chofer' in form ? form.chofer || null : null,
        peso_bruto: form.peso_bruto,
        tara: form.tara,
        observaciones: form.observaciones || null,
        ...(slot.tipo === 'asfalto' ? { temperatura: form.temperatura || null } : {}),
        ...(slot.tipo === 'ingreso_arido'
          ? {
              material: form.material,
              proveedor: form.proveedor,
              numero_remito: form.numero_remito.trim(),
              cantidad_remito: form.cantidad_remito,
            }
          : {}),
        ...(slot.tipo === 'egreso_arido' ? { material: form.material } : {}),
      })
      // Al confirmar, la puerta se cierra (misma semántica que el sistema legado).
      cerrarSlot(slot.id)
      await Promise.all([cargarHistorial(), cargarBase(), cargarProximoNumero()])
      // "Se guarda el vale → se imprime automáticamente" — solo aplica a
      // asfalto: es el único tipo con impresión (memory/business-rules.md).
      if (slot.tipo === 'asfalto') {
        await abrirImpresionVale(valeGuardado)
      }
    } catch (e) {
      error.value = e.message
    } finally {
      slot.guardando = false
    }
  }

  // -------------------------------------------------------------------------
  // Historial de vales (paginado server-side) + diferencia peso/remito
  // -------------------------------------------------------------------------

  const historial = ref([])
  const totalHistorial = ref(0)
  const paginaHistorial = ref(1)
  const cargandoHistorial = ref(false)
  // Sin default de fecha (2026-09-04, override explícito de Federico esta
  // sesión — antes prellenaba "Hoy", réplica del legado confirmada
  // 2026-09-02): arranca sin filtro de fecha, mostrando el historial
  // completo más reciente primero (paginado). Los filtros ahora se aplican
  // en vivo a medida que se eligen (ver aplicarFiltrosHistorial() más abajo
  // y los @change en BasculaView.vue) — ya no hace falta un botón "Filtrar".
  const filtros = reactive({ tipoVale: '', obraId: '', patente: '', desde: '', hasta: '' })

  // Nombres de responsable (2026-09-02, réplica exacta del cuadro del
  // legado, migración 20): `responsable_email` viene crudo en cada vale —
  // se cruza una sola vez por página contra flota_usuarios_email (mismo
  // mecanismo que ya usa auth.store.js/stock.service.js, no duplicado) en
  // vez de una consulta por fila.
  const nombresPorEmail = ref({})

  /**
   * Enriquece una fila cruda de plantas_vales con los labels que arma la
   * réplica del cuadro del legado — factoreado acá (no inline en el
   * computed) porque lo reusa tal cual exportarHistorialExcel() más abajo,
   * memory/conventions.md: no duplicar la misma transformación dos veces.
   */
  function enriquecerVale(v, mapaNombres = nombresPorEmail.value) {
    const diferencia = calcularDiferencia(v)
    // 2026-09-04: columnas ya aplanadas por VISTA_BASCULA_VIVA (ver
    // bascula.service.js#queryHistorialVales) — ya no hace falta el embed
    // `plantas_ingresos`/`plantas_pedidos`, la vista resuelve `obra_id`,
    // `material` y `cliente_externo` por fila (real o legado-vivo).
    const numeroRemitoIngreso = v.numero_remito_ingreso
    const cantidadRemitoIngreso = v.cantidad_remito_ingreso
    const obraIdEfectiva = v.obra_id
    return {
      ...v,
      obraNombre: obraIdEfectiva
        ? obrasPorId.value[obraIdEfectiva]?.nombre ?? `Obra #${obraIdEfectiva}`
        : v.cliente_externo || '—',
      pesoNetoLabel: `${v.peso_neto} ${v.unidad}`,
      fechaLabel: new Date(v.fecha_pesada).toLocaleString('es-AR'),
      horaLabel: new Date(v.fecha_pesada).toLocaleTimeString('es-AR', { hour: '2-digit', minute: '2-digit' }),
      diferenciaLabel: diferencia == null ? '—' : `${diferencia > 0 ? '+' : ''}${diferencia.toFixed(2)} tn`,
      // MATERIAL/OBRA combinada (columna única en el legado): obra para
      // asfalto, material de texto libre para ingreso/egreso — ambos ya
      // vienen resueltos en `v.material` por la vista.
      materialObraLabel:
        v.tipo_vale === 'asfalto'
          ? obraIdEfectiva
            ? obrasPorId.value[obraIdEfectiva]?.nombre ?? `Obra #${obraIdEfectiva}`
            : v.cliente_externo || '—'
          : v.material || '—',
      remitoLabel: numeroRemitoIngreso || '—',
      // Responsable: email real si lo hay (cruzado contra flota_usuarios_email,
      // igual que antes); si la fila es solo-legado sin email, cae al texto
      // suelto que sí guardaba el legado (operador/responsable) antes de '—'.
      responsableLabel: v.responsable_email
        ? mapaNombres[v.responsable_email] ?? v.responsable_email
        : v.responsable_texto_legado || '—',
      // Fix 2026-09-04 (bug real: "falta el acumulado" en la tabla y el
      // Excel): antes leía `acumulado_obra_tn`, una foto guardada al pesar
      // que la migración del histórico nunca pobló (quedaba null salvo en
      // vales cargados 100% desde el sistema nuevo). Ahora usa
      // `acumulado_dia_tn`, calculado en vivo por la vista con una suma
      // corrida (ver plantas_v_bascula_viva) — mismo criterio y mismo
      // resultado que ya usaba obtenerAcumuladoHastaFecha() para imprimir,
      // ahora también disponible fila por fila sin una consulta extra.
      acumuladoLabel: v.tipo_vale === 'asfalto' && v.acumulado_dia_tn != null ? `${Number(v.acumulado_dia_tn).toFixed(2)} tn` : '—',
      // S/REMITO y DIF. (legado): solo tienen valor en filas de ingreso —
      // memory/relevamiento-sistema-viejo.md §2, verificado en vivo: vacías
      // en filas de asfalto/egreso. calcularDiferencia() ya devuelve null
      // para esos casos, mismo criterio acá.
      sRemitoLabel: cantidadRemitoIngreso != null ? `${Number(cantidadRemitoIngreso).toFixed(2)} tn` : '—',
      tipoCorto: TIPO_CORTO_VALE[v.tipo_vale] ?? v.tipo_vale,
      entradaSalida: ENTRADA_SALIDA_VALE[v.tipo_vale] ?? '—',
    }
  }

  const filasHistorial = computed(() => historial.value.map(enriquecerVale))

  async function cargarHistorial() {
    cargandoHistorial.value = true
    error.value = null
    try {
      const resultado = await fetchHistorialVales(
        {
          tipoVale: filtros.tipoVale || undefined,
          obraId: filtros.obraId || undefined,
          patente: filtros.patente || undefined,
          desde: filtros.desde || undefined,
          hasta: filtros.hasta || undefined,
        },
        { pagina: paginaHistorial.value, tamanoPagina: TAMANO_PAGINA_HISTORIAL }
      )
      historial.value = resultado.filas
      totalHistorial.value = resultado.total
      const emails = resultado.filas.map((v) => v.responsable_email).filter(Boolean)
      if (emails.length) nombresPorEmail.value = await fetchNombresPorEmail(emails)
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoHistorial.value = false
    }
  }

  /** Cualquier cambio de filtro vuelve a la página 1 (si no, se puede quedar en una página que ya no existe). */
  function aplicarFiltrosHistorial() {
    paginaHistorial.value = 1
    cargarHistorial()
  }

  function limpiarFiltrosHistorial() {
    filtros.tipoVale = ''
    filtros.obraId = ''
    filtros.patente = ''
    filtros.desde = ''
    filtros.hasta = ''
    aplicarFiltrosHistorial()
  }

  function cambiarPaginaHistorial(pagina) {
    paginaHistorial.value = pagina
    cargarHistorial()
  }

  // -------------------------------------------------------------------------
  // Exportar a Excel (2026-09-02, pedido de Federico — botón "Excel" que
  // tenía el legado sobre "Movimientos del día", memory/relevamiento-sistema-
  // viejo.md §2). Exporta TODO lo que matchea el filtro activo (no solo la
  // página de 50 en pantalla, ver fetchTodosLosVales()), mismas columnas y
  // mismo orden que la tabla — reusa enriquecerVale(), no duplica los labels.
  // -------------------------------------------------------------------------

  const exportandoHistorial = ref(false)

  async function exportarHistorialExcel() {
    exportandoHistorial.value = true
    error.value = null
    try {
      const filasCrudas = await fetchTodosLosVales({
        tipoVale: filtros.tipoVale || undefined,
        obraId: filtros.obraId || undefined,
        patente: filtros.patente || undefined,
        desde: filtros.desde || undefined,
        hasta: filtros.hasta || undefined,
      })
      const emails = filasCrudas.map((v) => v.responsable_email).filter(Boolean)
      const mapaNombres = emails.length ? await fetchNombresPorEmail(emails) : {}
      const filas = filasCrudas.map((v) => enriquecerVale(v, mapaNombres))

      await exportarPlanillaCorporativa(nombreArchivoConFecha('bascula-movimientos'), [
        {
          nombre: 'Movimientos',
          titulo: 'Báscula — Movimientos del día',
          filas,
          columnas: [
            { key: 'horaLabel', label: 'Hora' },
            { key: 'fecha_pesada', label: 'Fecha', format: (v) => new Date(v).toLocaleDateString('es-AR') },
            { key: 'tipoCorto', label: 'Tipo' },
            { key: 'materialObraLabel', label: 'Material/Obra' },
            { key: 'patente', label: 'Patente' },
            { key: 'remitoLabel', label: 'Remito' },
            { key: 'responsableLabel', label: 'Responsable' },
            { key: 'numero_vale', label: 'N° Vale', format: (v) => formatearNumeroVale(v) },
            { key: 'peso_bruto', label: 'Bruto (tn)', format: (v) => Number(v).toFixed(2) },
            { key: 'tara', label: 'Tara (tn)', format: (v) => Number(v).toFixed(2) },
            { key: 'peso_neto', label: 'Neto (tn)', format: (v) => Number(v).toFixed(2) },
            { key: 'acumuladoLabel', label: 'Acum.' },
            { key: 'sRemitoLabel', label: 'S/Remito' },
            { key: 'diferenciaLabel', label: 'Dif.' },
            { key: 'entradaSalida', label: 'E/S' },
          ],
        },
      ])
    } catch (e) {
      error.value = e.message
    } finally {
      exportandoHistorial.value = false
    }
  }

  // -------------------------------------------------------------------------
  // Impresión (vale individual / remito con acumulado dinámico)
  // -------------------------------------------------------------------------
  // REGLA: "Vale" imprime para asfalto Y para egreso de áridos (pedido de
  // Federico, 2026-09-04 — antes solo asfalto). "Remito" sigue siendo
  // exclusivo de asfalto: es el formato atado al flujo pedido/obra
  // (acumulado por pedido, rango de vales correlativos del día), egreso de
  // áridos no tiene pedido asociado. Ingreso de áridos sigue sin impresión.
  // El acumulado SIEMPRE se recalcula en vivo acá (nunca se lee
  // vale.acumulado_obra_tn como fuente de verdad) — mismo criterio para modo
  // "vale" y modo "remito" (Logica sis. plantas v1.rtf §2.4: "Tanto el
  // imprimible como el historial recalculan dinámicamente"). Ese acumulado
  // por pedido/obra solo tiene sentido para asfalto (obtenerAcumuladoHastaFecha
  // filtra tipo_vale='asfalto') — para egreso de áridos no hay un concepto de
  // "acumulado del día" definido todavía, el vale imprime sin esa línea
  // (queda "—", mismo criterio que ya usa la tabla/Excel del historial).

  const modalImpresionAbierto = ref(false)
  const modoImpresion = ref('vale')
  const valeParaImprimir = ref(null)
  const obraNombreParaImprimir = ref('')
  const mezclaNombreParaImprimir = ref('')
  const acumuladoParaImprimir = ref(null)
  // Sección "remito" (2026-09-01, contra foto real de un remito de VialTec —
  // ver ValeImprimible.vue): pedido completo (nro_remito_global, ubicacion,
  // cliente_externo) + rango de vales correlativos del acumulado del día.
  const pedidoParaImprimir = ref(null)
  const rangoValesParaImprimir = ref({ valeDesde: null, valeHasta: null, cantidadVales: 0 })

  async function abrirImpresion(vale, modo) {
    // Guarda defensiva (2026-09-04): una fila `pendiente_migracion` (todavía
    // solo en el legado, VISTA_BASCULA_VIVA) no tiene un vale real de
    // plantas_vales detrás — no hay acumulado ni numero_vale reales para
    // imprimir. La UI ya deshabilita el botón para estas filas; esto es
    // solo el resguardo por si se llama igual.
    if (vale.pendiente_migracion) {
      error.value = 'Este movimiento todavía no está migrado al sistema nuevo — no se puede imprimir desde acá.'
      return
    }
    valeParaImprimir.value = vale
    // Fix 2026-09-04 (bug real reportado por Federico: "el vale no está
    // trayendo el dato de la obra ni la mezcla"): `pedidosPorId` sale de
    // `fetchPedidosAsfaltoParaPesada()`, que desde hoy filtra solo
    // `estado = 'confirmado'` (override explícito pedido por Federico esta
    // misma sesión) — un vale de un pedido que YA se despachó (la inmensa
    // mayoría de los históricos que se imprimen) no aparece más en esa
    // lista acotada, así que pedido quedaba `null` y obra/mezcla vacías.
    // Fallback: si no está en el cache de la lista de pesada, se trae el
    // pedido puntual por id (1 sola fila, barato) — no bloquea la
    // impresión si falla, el vale se imprime igual sin obra/mezcla.
    let pedido = vale.pedido_id ? pedidosPorId.value[vale.pedido_id] : null
    if (!pedido && vale.pedido_id) {
      try {
        pedido = await getPedido(vale.pedido_id)
      } catch (e) {
        pedido = null
      }
    }
    pedidoParaImprimir.value = pedido
    // Destino: obra si la tiene; si no, venta externa -> cliente_externo del
    // pedido (una pesada de venta externa no trae obra_id, memory/business-rules.md).
    obraNombreParaImprimir.value = vale.obra_id
      ? obrasPorId.value[vale.obra_id]?.nombre ?? ''
      : pedido?.cliente_externo ?? ''
    mezclaNombreParaImprimir.value = pedido ? formulasPorId.value[pedido.formula_id]?.nombre ?? '' : ''
    modoImpresion.value = modo
    modalImpresionAbierto.value = true
    error.value = null
    // obtenerAcumuladoHastaFecha() solo tiene sentido (y solo consulta) vales
    // de asfalto — para egreso de áridos no hay acumulado del día definido,
    // el vale imprime directamente sin esa línea en vez de pedirle a esa
    // función un resultado que no puede dar (con vale.tipo_vale='egreso_arido'
    // devolvería 0/vacío igual, por el filtro fijo que tiene esa query).
    if (vale.tipo_vale === 'asfalto') {
      try {
        const { acumuladoTn, valeDesde, valeHasta, cantidadVales } = await obtenerAcumuladoHastaFecha({
          pedidoId: vale.pedido_id,
          obraId: vale.obra_id,
          fechaCorte: vale.fecha_pesada,
        })
        acumuladoParaImprimir.value = acumuladoTn
        rangoValesParaImprimir.value = { valeDesde, valeHasta, cantidadVales }
      } catch (e) {
        error.value = e.message
      }
    } else {
      acumuladoParaImprimir.value = null
      rangoValesParaImprimir.value = { valeDesde: null, valeHasta: null, cantidadVales: 0 }
    }
  }

  function abrirImpresionVale(vale) {
    return abrirImpresion(vale, 'vale')
  }

  function abrirImpresionRemito(vale) {
    return abrirImpresion(vale, 'remito')
  }

  function imprimir() {
    window.print()
  }

  // -------------------------------------------------------------------------
  // Arranque: base + próximo número + primera página de historial (filtrada
  // a hoy por default). Sin ninguna puerta abierta (2026-09-02, corrección
  // de un supuesto anterior: el comentario acá decía "una puerta de asfalto
  // abierta por default, mismo comportamiento del legado" — verificado de
  // nuevo en vivo hoy contra produccion.vialtec.app, el legado arranca en
  // "0 puertas abiertas", el operador abre la que necesita con "+ Abrir
  // puerta". El supuesto anterior era incorrecto, no un cambio de diseño.
  // -------------------------------------------------------------------------

  function iniciar() {
    cargarBase()
    cargarHistorial()
    cargarProximoNumero()
  }

  return {
    error,
    cargandoBase,
    obras,
    patentes,
    proveedores,
    pedidosParaPesada,
    nombreDestinoPedido,
    proximoNumeroVale,
    puertasAbiertas,
    slots,
    crearSlot,
    cambiarTipoSlot,
    toggleColapso,
    cerrarSlot,
    netoSlot,
    alCambiarPatente,
    guardarPesada,
    filasHistorial,
    totalHistorial,
    paginaHistorial,
    cargandoHistorial,
    filtros,
    cargarHistorial,
    aplicarFiltrosHistorial,
    limpiarFiltrosHistorial,
    cambiarPaginaHistorial,
    TAMANO_PAGINA_HISTORIAL,
    exportandoHistorial,
    exportarHistorialExcel,
    modalImpresionAbierto,
    modoImpresion,
    valeParaImprimir,
    obraNombreParaImprimir,
    mezclaNombreParaImprimir,
    acumuladoParaImprimir,
    pedidoParaImprimir,
    rangoValesParaImprimir,
    abrirImpresionVale,
    abrirImpresionRemito,
    imprimir,
    iniciar,
  }
}
