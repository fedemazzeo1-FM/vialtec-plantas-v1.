// Composable de Auditoría (etapa 5): filtros en la URL, listado paginado,
// detalle antes/después y Excel del filtro completo. La vista
// (AuditoriaView.vue) es template puro.
import { computed, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import {
  ACCIONES_AUDITORIA,
  TAMANO_PAGINA_AUDITORIA,
  fetchAuditoria,
  fetchTodaLaAuditoria,
  fetchEntidadesAuditoria,
  normalizarBusquedaAuditoria,
} from '@/modules/auditoria/services/auditoria.service'
import { fetchUsuarios } from '@/modules/usuarios/services/usuarios.service'
import { fetchNombresPorEmail } from '@/services/flota.service'

const CLAVES_FILTRO = ['usuario', 'modulo', 'accion', 'desde', 'hasta', 'q']
const USUARIO_SISTEMA = 'sistema (SQL)'

const ACCION_POR_ID = Object.fromEntries(ACCIONES_AUDITORIA.map((a) => [a.id, a]))

export function etiquetaAccion(id) {
  return ACCION_POR_ID[id]?.label ?? id
}
export function varianteAccion(id) {
  return ACCION_POR_ID[id]?.variante ?? 'default'
}

/** Fecha y hora en Argentina, sin depender de la zona del navegador. */
export function formatearFechaHoraAuditoria(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('es-AR', {
    timeZone: 'America/Argentina/Buenos_Aires',
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: false,
  })
}

/** 'cantidad_solicitada' → 'Cantidad solicitada'. */
function etiquetaCampo(clave) {
  const texto = String(clave).replace(/_/g, ' ')
  return texto.charAt(0).toUpperCase() + texto.slice(1)
}

export function formatearValorAuditoria(valor) {
  if (valor === null || valor === undefined || valor === '') return '—'
  if (typeof valor === 'boolean') return valor ? 'Sí' : 'No'
  if (typeof valor === 'object') return JSON.stringify(valor)
  return String(valor)
}

/**
 * Filas "campo | antes | después" de un registro. En altas solo hay
 * "después" y en eliminaciones solo "antes" (registro completo); en el resto
 * la base ya guardó únicamente lo que cambió.
 */
export function filasDetalleAuditoria(registro) {
  const antes = registro?.valores_antes && typeof registro.valores_antes === 'object' ? registro.valores_antes : {}
  const despues = registro?.valores_despues && typeof registro.valores_despues === 'object' ? registro.valores_despues : {}
  const claves = [...new Set([...Object.keys(antes), ...Object.keys(despues)])].sort()
  return claves.map((clave) => ({
    clave,
    campo: etiquetaCampo(clave),
    antes: clave in antes ? formatearValorAuditoria(antes[clave]) : '',
    despues: clave in despues ? formatearValorAuditoria(despues[clave]) : '',
  }))
}

function resumenValores(valores) {
  if (!valores || typeof valores !== 'object') return ''
  return Object.entries(valores)
    .map(([clave, valor]) => `${etiquetaCampo(clave)}: ${formatearValorAuditoria(valor)}`)
    .join('; ')
}

export function useAuditoria() {
  const route = useRoute()
  const router = useRouter()

  const filas = ref([])
  const total = ref(0)
  const cargando = ref(false)
  const error = ref(null)

  const entidades = ref([])
  const usuarios = ref([])

  // Estado del formulario: se inicializa desde la URL y recién se aplica
  // (y vuelve a la URL) con "Filtrar", igual que el resto de las pantallas.
  const filtros = reactive({ usuario: '', modulo: '', accion: '', desde: '', hasta: '', q: '' })
  const pagina = ref(1)

  function leerDeLaUrl() {
    for (const clave of CLAVES_FILTRO) {
      const valor = route.query[clave]
      filtros[clave] = typeof valor === 'string' ? valor : ''
    }
    const p = Number(route.query.pagina)
    pagina.value = Number.isInteger(p) && p > 0 ? p : 1
  }

  function queryDeFiltros() {
    const query = {}
    for (const clave of CLAVES_FILTRO) {
      const valor = String(filtros[clave] ?? '').trim()
      if (valor) query[clave] = valor
    }
    if (pagina.value > 1) query.pagina = String(pagina.value)
    return query
  }

  const filtrosActivos = computed(() => {
    const activos = {}
    for (const clave of CLAVES_FILTRO) {
      const valor = String(filtros[clave] ?? '').trim()
      if (valor) activos[clave] = valor
    }
    return activos
  })

  const modulos = computed(() => {
    const vistos = new Map()
    for (const e of entidades.value) if (!vistos.has(e.modulo)) vistos.set(e.modulo, e.modulo_etiqueta)
    return [...vistos].map(([id, label]) => ({ id, label }))
  })
  const etiquetaModulo = computed(() => Object.fromEntries(modulos.value.map((m) => [m.id, m.label])))
  const etiquetaEntidad = computed(() => Object.fromEntries(entidades.value.map((e) => [e.entidad, e.entidad_etiqueta])))

  async function cargar() {
    cargando.value = true
    error.value = null
    try {
      const resultado = await fetchAuditoria(filtrosActivos.value, { pagina: pagina.value })
      filas.value = resultado.filas
      total.value = resultado.total
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
  }

  async function cargarBase() {
    try {
      const [listaEntidades, listaUsuarios] = await Promise.all([fetchEntidadesAuditoria(), fetchUsuarios()])
      entidades.value = listaEntidades
      const emails = listaUsuarios.map((u) => u.email)
      let nombres = {}
      try {
        nombres = await fetchNombresPorEmail(emails)
      } catch (e) {
        nombres = {} // sin nombres se muestra el email, no es bloqueante
      }
      usuarios.value = [
        ...emails
          .map((email) => ({ email, label: nombres[email] || email }))
          .sort((a, b) => a.label.localeCompare(b.label, 'es')),
        { email: USUARIO_SISTEMA, label: 'Sistema (SQL directo)' },
      ]
    } catch (e) {
      error.value = e.message
    }
  }

  /** Sincroniza la URL (replace: no ensucia el historial) y recarga. */
  async function aplicar() {
    await router.replace({ query: queryDeFiltros() })
    await cargar()
  }

  function aplicarFiltros() {
    pagina.value = 1
    return aplicar()
  }

  function limpiarFiltros() {
    for (const clave of CLAVES_FILTRO) filtros[clave] = ''
    pagina.value = 1
    return aplicar()
  }

  function cambiarPagina(nueva) {
    pagina.value = nueva
    return aplicar()
  }

  // Atrás/adelante del navegador o un link pegado con otros filtros.
  watch(
    () => route.query,
    (nueva) => {
      if (JSON.stringify(nueva) === JSON.stringify(queryDeFiltros())) return
      leerDeLaUrl()
      cargar()
    }
  )

  // Detalle
  const modalDetalleAbierto = ref(false)
  const registroDetalle = ref(null)
  const filasDetalle = computed(() => filasDetalleAuditoria(registroDetalle.value))

  function abrirDetalle(registro) {
    registroDetalle.value = registro
    modalDetalleAbierto.value = true
  }

  // Excel: todas las filas del filtro, no solo la página.
  const exportando = ref(false)

  const resumenFiltrosLabel = computed(() => {
    const f = filtrosActivos.value
    const partes = []
    if (f.usuario) partes.push(`Usuario: ${usuarios.value.find((u) => u.email === f.usuario)?.label ?? f.usuario}`)
    if (f.modulo) partes.push(`Módulo: ${etiquetaModulo.value[f.modulo] ?? f.modulo}`)
    if (f.accion) partes.push(`Acción: ${etiquetaAccion(f.accion)}`)
    if (f.desde) partes.push(`Desde: ${f.desde}`)
    if (f.hasta) partes.push(`Hasta: ${f.hasta}`)
    if (f.q) partes.push(`N°: ${normalizarBusquedaAuditoria(f.q)}`)
    return partes.length ? partes.join(' · ') : 'Sin filtros'
  })

  async function exportarExcel() {
    exportando.value = true
    error.value = null
    try {
      const todas = await fetchTodaLaAuditoria(filtrosActivos.value)
      const { exportarPlanillaCorporativa, nombreArchivoConFecha } = await import('@/services/excel-corporativo')
      await exportarPlanillaCorporativa(nombreArchivoConFecha('Auditoria'), [
        {
          nombre: 'Auditoría',
          titulo: `Auditoría — ${resumenFiltrosLabel.value}`,
          columnas: [
            { key: 'id', label: 'N°' },
            { key: 'fecha_hora', label: 'Fecha y hora', format: (v) => formatearFechaHoraAuditoria(v) },
            { key: 'usuario_nombre', label: 'Usuario' },
            { key: 'usuario_rol', label: 'Rol' },
            { key: 'tipo_accion', label: 'Acción', format: (v) => etiquetaAccion(v) },
            { key: 'modulo', label: 'Módulo', format: (v) => etiquetaModulo.value[v] ?? v },
            { key: 'entidad', label: 'Qué', format: (v) => etiquetaEntidad.value[v] ?? v },
            { key: 'entidad_ref', label: 'Referencia' },
            { key: 'entidad_label', label: 'Detalle' },
            { key: 'motivo', label: 'Motivo' },
            { key: 'valores_antes', label: 'Antes', format: (v) => resumenValores(v) },
            { key: 'valores_despues', label: 'Después', format: (v) => resumenValores(v) },
            { key: 'dispositivo', label: 'Dispositivo' },
          ],
          filas: todas,
        },
      ])
    } catch (e) {
      error.value = e.message
    } finally {
      exportando.value = false
    }
  }

  async function iniciar() {
    leerDeLaUrl()
    await Promise.all([cargarBase(), cargar()])
  }

  return {
    filas,
    total,
    pagina,
    cargando,
    error,
    filtros,
    usuarios,
    modulos,
    etiquetaModulo,
    etiquetaEntidad,
    aplicarFiltros,
    limpiarFiltros,
    cambiarPagina,
    modalDetalleAbierto,
    registroDetalle,
    filasDetalle,
    abrirDetalle,
    exportando,
    exportarExcel,
    iniciar,
    TAMANO_PAGINA_AUDITORIA,
  }
}
