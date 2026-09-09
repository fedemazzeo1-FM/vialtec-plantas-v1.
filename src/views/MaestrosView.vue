<script setup>
// Vista de Maestros de planta: tabs para encargados, proveedores, patentes y
// choferes. Toda la persistencia pasa por maestros.service.js — este componente
// no llama a Supabase directamente (memory/conventions.md).

import { computed, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VSection from '@/components/shared/VSection.vue'
import VButton from '@/components/shared/VButton.vue'
import { maestrosService } from '@/modules/maestros/services/maestros.service'
import { fetchTodasLasObrasConResumen } from '@/services/flota.service'
import { fetchEstadoLocalObras, setObraArchivadaLocal } from '@/modules/maestros/services/obras-locales.service'
import { useAuthStore } from '@/stores/auth.store'

// Config declarativa por catálogo: columnas de tabla, campos de formulario y
// registro vacío. Evita repetir la vista 4 veces para 4 tablas casi idénticas.
const ENTIDADES = {
  encargados: {
    label: 'Encargados',
    nombreSingular: 'encargado',
    columnas: [
      { key: 'nombre', label: 'Nombre' },
      { key: 'telefono', label: 'Teléfono' },
    ],
    campos: [
      { key: 'nombre', label: 'Nombre', type: 'text', required: true },
      { key: 'telefono', label: 'Teléfono', type: 'text' },
    ],
    vacio: () => ({ nombre: '', telefono: '', activo: true }),
  },
  proveedores: {
    label: 'Proveedores',
    nombreSingular: 'proveedor',
    columnas: [
      { key: 'nombre', label: 'Nombre' },
      { key: 'material_principal', label: 'Material principal' },
    ],
    campos: [
      { key: 'nombre', label: 'Nombre', type: 'text', required: true },
      { key: 'material_principal', label: 'Material principal', type: 'text' },
    ],
    vacio: () => ({ nombre: '', material_principal: '', activo: true }),
  },
  // Separación Vehículos Propios/Externos (2026-09-01, pedido de Federico —
  // relevado contra el legado: 30 patentes propias / 21 externas reales,
  // `es_externa` ya existía en el schema pero convivían sin distinción
  // visual clara en una sola tabla). Misma `plantas_patentes`, 2 tabs con
  // filtro fijo cada una (ver patentesPropiasService/patentesExternasService
  // en maestros.service.js) — "es_externa" ya no es columna/campo visible
  // porque queda implícito por la tab en la que se está parado.
  vehiculosPropios: {
    // Renombrado 2026-09-04 (pedido de Federico) de "Vehículos propios" a
    // "Camiones propios" — mismo catálogo/service, solo la etiqueta visible.
    label: 'Camiones propios',
    nombreSingular: 'camión propio',
    columnas: [
      { key: 'patente', label: 'Patente' },
      { key: 'tipo_camion', label: 'Tipo camión' },
      { key: 'tara', label: 'Tara (tn)' },
      { key: 'chofer_habitual', label: 'Chofer habitual' },
    ],
    campos: [
      { key: 'patente', label: 'Patente', type: 'text', required: true },
      { key: 'tipo_camion', label: 'Tipo de camión', type: 'text' },
      { key: 'tara', label: 'Tara (tn)', type: 'number' },
      { key: 'chofer_habitual', label: 'Chofer habitual', type: 'text' },
    ],
    vacio: () => ({ patente: '', tipo_camion: '', tara: null, chofer_habitual: '', activo: true }),
  },
  vehiculosExternos: {
    // Renombrado 2026-09-04 (pedido de Federico) de "Vehículos externos" a
    // "Camiones externos" — mismo catálogo/service, solo la etiqueta visible.
    label: 'Camiones externos',
    nombreSingular: 'camión externo',
    columnas: [
      { key: 'patente', label: 'Patente' },
      { key: 'tipo_camion', label: 'Tipo camión' },
      { key: 'tara', label: 'Tara (tn)' },
      { key: 'chofer_habitual', label: 'Chofer / transportista' },
    ],
    campos: [
      { key: 'patente', label: 'Patente', type: 'text', required: true },
      { key: 'tipo_camion', label: 'Tipo de camión', type: 'text' },
      { key: 'tara', label: 'Tara (tn)', type: 'number' },
      { key: 'chofer_habitual', label: 'Chofer / transportista', type: 'text' },
    ],
    vacio: () => ({ patente: '', tipo_camion: '', tara: null, chofer_habitual: '', activo: true }),
  },
  choferes: {
    label: 'Choferes',
    nombreSingular: 'chofer',
    columnas: [
      { key: 'nombre', label: 'Nombre' },
      { key: 'dni', label: 'DNI' },
    ],
    campos: [
      { key: 'nombre', label: 'Nombre', type: 'text', required: true },
      { key: 'dni', label: 'DNI', type: 'text' },
    ],
    vacio: () => ({ nombre: '', dni: '', activo: true }),
  },
  // Catálogo de materiales (migración 13, módulo Stock) — gap #2 del
  // relevamiento: antes "material" era texto libre en todos lados. `nombre`
  // es la clave de matching contra fórmulas/báscula/ingresos (case-
  // insensitive, ver plantas_buscar_material_id() en la migración).
  materiales: {
    label: 'Materiales',
    nombreSingular: 'material',
    columnas: [
      { key: 'nombre', label: 'Nombre' },
      { key: 'unidad', label: 'Unidad' },
      { key: 'categoria', label: 'Categoría' },
      { key: 'controla_stock', label: 'Controla stock', format: (v) => (v ? 'Sí' : 'No') },
      { key: 'stock_minimo_kg', label: 'Mín. (kg)' },
      { key: 'stock_maximo_kg', label: 'Máx. (kg)' },
    ],
    campos: [
      { key: 'nombre', label: 'Nombre', type: 'text', required: true },
      { key: 'unidad', label: 'Unidad (referencia, ej. "TN")', type: 'text' },
      { key: 'categoria', label: 'Categoría (opcional)', type: 'text' },
      { key: 'controla_stock', label: 'Controla stock (desmarcar para Agua/Purgue)', type: 'checkbox' },
      { key: 'stock_minimo_kg', label: 'Stock mínimo de alerta (kg)', type: 'number' },
      { key: 'stock_maximo_kg', label: 'Stock máximo (kg)', type: 'number' },
    ],
    vacio: () => ({
      nombre: '',
      unidad: '',
      categoria: '',
      controla_stock: true,
      stock_minimo_kg: null,
      stock_maximo_kg: null,
      activo: true,
    }),
  },
  // Clientes de venta externa (migración 35, 2026-09-09, pedido de Federico):
  // `nombre` es lo que alimenta el <select> de "Cliente externo" en el alta/
  // edición de Pedidos (usePedidos.js) — plantas_pedidos.cliente_externo
  // sigue siendo texto libre, no hay FK nueva.
  clientes: {
    label: 'Clientes',
    nombreSingular: 'cliente',
    columnas: [
      { key: 'nombre', label: 'Nombre' },
      { key: 'cuit', label: 'CUIT' },
      { key: 'contacto', label: 'Contacto' },
      { key: 'telefono', label: 'Teléfono' },
    ],
    campos: [
      { key: 'nombre', label: 'Nombre', type: 'text', required: true },
      { key: 'cuit', label: 'CUIT (opcional)', type: 'text' },
      { key: 'contacto', label: 'Contacto (opcional)', type: 'text' },
      { key: 'telefono', label: 'Teléfono (opcional)', type: 'text' },
    ],
    vacio: () => ({ nombre: '', cuit: '', contacto: '', telefono: '', activo: true }),
  },
}

// "Obras" (2026-09-08) queda AFUERA de ENTIDADES a propósito — no es un CRUD
// más: es de solo lectura sobre flota_obras (tabla compartida, propiedad de
// Flota — Obras se sigue gestionando ahí, decisión explícita de Federico de
// no duplicar esa lógica) más un archivado LOCAL de visibilidad
// (plantas_obras_locales, migración 32). Se maneja con su propio bloque de
// carga/template más abajo en vez de forzarlo al patrón genérico de
// crear/editar/activar de los demás catálogos.
const tabs = [...Object.keys(ENTIDADES), 'obras']

// Persistencia de navegación (2026-09-01, memory/modules-status.md — "F5 /
// duplicar pestaña"): la tab activa se sincroniza con `?tab=` en la URL. Sin
// esto, recargar la página (o abrir el link desde otro lado) siempre volvía
// a "Encargados" aunque el usuario estuviera parado en "Materiales". Se usa
// `router.replace` (no `push`) para no ensuciar el historial con una entrada
// nueva por cada click de tab.
const route = useRoute()
const router = useRouter()
const tabActiva = ref(tabs.includes(route.query.tab) ? route.query.tab : tabs[0])
const entidadActual = computed(() => ENTIDADES[tabActiva.value])
const columnasConAcciones = computed(() => [
  ...entidadActual.value.columnas,
  { key: 'activo', label: 'Estado' },
  { key: 'acciones', label: '' },
])

const registros = ref([])
const cargando = ref(false)
const error = ref(null)

const modalAbierto = ref(false)
const guardando = ref(false)
const editandoId = ref(null)
const formData = reactive({})

async function cargarRegistros() {
  cargando.value = true
  error.value = null
  try {
    registros.value = await maestrosService[tabActiva.value].fetch()
  } catch (e) {
    error.value = e.message
  } finally {
    cargando.value = false
  }
}

// -------------------------------------------------------------------------
// Obras (2026-09-08) — solo lectura de flota_obras + archivado local, ver
// nota de "tabs" más arriba. `auth.user?.email` es a título informativo
// (quién archivó), no hay auditoría server-side para este catálogo liviano.
// -------------------------------------------------------------------------

const auth = useAuthStore()
const obrasTodas = ref([])
const estadoLocalObras = ref({})
const cargandoObras = ref(false)
const vistaObras = ref('activas') // 'activas' | 'archivadas'

const columnasObras = [
  { key: 'nombre', label: 'Nombre' },
  { key: 'codigo', label: 'Código' },
  { key: 'cliente', label: 'Cliente' },
  { key: 'ubicacion', label: 'Ubicación' },
  { key: 'estado', label: 'Estado (Flota)' },
  { key: 'archivadaEnLabel', label: 'Archivada acá el' },
  { key: 'acciones', label: '' },
]

const obrasConEstadoLocal = computed(() =>
  obrasTodas.value.map((o) => {
    const local = estadoLocalObras.value[o.id]
    return {
      ...o,
      archivadaLocal: local?.archivada ?? false,
      archivadaEnLabel: local?.archivada_en ? new Date(local.archivada_en).toLocaleDateString('es-AR') : '—',
    }
  })
)
const obrasFiltradas = computed(() =>
  obrasConEstadoLocal.value.filter((o) => (vistaObras.value === 'archivadas' ? o.archivadaLocal : !o.archivadaLocal))
)

async function cargarObras() {
  cargandoObras.value = true
  error.value = null
  try {
    const [listaObras, estadoLocal] = await Promise.all([fetchTodasLasObrasConResumen(), fetchEstadoLocalObras()])
    obrasTodas.value = listaObras
    estadoLocalObras.value = estadoLocal
  } catch (e) {
    error.value = e.message
  } finally {
    cargandoObras.value = false
  }
}

async function toggleArchivadaLocal(obra) {
  error.value = null
  try {
    await setObraArchivadaLocal(obra.id, !obra.archivadaLocal, auth.user?.email)
    await cargarObras()
  } catch (e) {
    error.value = e.message
  }
}

watch(
  tabActiva,
  (nueva) => {
    if (nueva === 'obras') cargarObras()
    else cargarRegistros()
    router.replace({ query: { ...route.query, tab: nueva } })
  },
  { immediate: true }
)

function abrirNuevo() {
  editandoId.value = null
  Object.keys(formData).forEach((k) => delete formData[k])
  Object.assign(formData, entidadActual.value.vacio())
  modalAbierto.value = true
}

function abrirEdicion(registro) {
  editandoId.value = registro.id
  Object.keys(formData).forEach((k) => delete formData[k])
  Object.assign(formData, registro)
  modalAbierto.value = true
}

async function guardar() {
  const campoRequerido = entidadActual.value.campos.find((c) => c.required && !String(formData[c.key] || '').trim())
  if (campoRequerido) {
    error.value = `El campo "${campoRequerido.label}" es obligatorio.`
    return
  }

  guardando.value = true
  error.value = null
  try {
    if (editandoId.value) {
      await maestrosService[tabActiva.value].actualizar(editandoId.value, formData)
    } else {
      await maestrosService[tabActiva.value].crear(formData)
    }
    modalAbierto.value = false
    await cargarRegistros()
  } catch (e) {
    error.value = e.message
  } finally {
    guardando.value = false
  }
}

async function toggleActivo(registro) {
  error.value = null
  try {
    await maestrosService[tabActiva.value].setActivo(registro.id, !registro.activo)
    await cargarRegistros()
  } catch (e) {
    error.value = e.message
  }
}
</script>

<template>
  <div>
    <VSection title="Maestros">
      <div class="mb-4 flex gap-1 overflow-x-auto border-b border-border">
        <button
          v-for="tab in tabs"
          :key="tab"
          type="button"
          class="shrink-0 whitespace-nowrap border-b-2 px-3 py-2 text-sm font-semibold transition-colors duration-150"
          :class="
            tab === tabActiva
              ? 'border-vialtec text-vialtec'
              : 'border-transparent text-text-soft hover:text-text-mid'
          "
          @click="tabActiva = tab"
        >
          {{ tab === 'obras' ? 'Obras' : ENTIDADES[tab].label }}
        </button>
      </div>

      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <!-- Obras: solo lectura de flota_obras + archivado LOCAL (migración
           32) — ver nota en <script> sobre por qué queda afuera del patrón
           genérico de abajo. -->
      <template v-if="tabActiva === 'obras'">
        <p class="mb-3 text-xs text-text-soft">
          Las obras se crean y gestionan en Flota (equipos2.vialtec.app → Maestros → Obras). Acá solo podés
          archivarlas <strong>para este sistema</strong>: dejan de aparecer en los desplegables de Pedidos, Báscula,
          Despachos, Plan Semanal y Dashboard, sin tocar nada en Flota.
        </p>

        <div class="mb-3 flex gap-1 rounded-lg border border-border p-1" style="width: fit-content">
          <button
            type="button"
            class="rounded-md px-3 py-1.5 text-sm font-semibold transition-colors duration-150"
            :class="vistaObras === 'activas' ? 'bg-vialtec text-white' : 'text-text-mid hover:bg-gray-50'"
            @click="vistaObras = 'activas'"
          >
            Activas
          </button>
          <button
            type="button"
            class="rounded-md px-3 py-1.5 text-sm font-semibold transition-colors duration-150"
            :class="vistaObras === 'archivadas' ? 'bg-vialtec text-white' : 'text-text-mid hover:bg-gray-50'"
            @click="vistaObras = 'archivadas'"
          >
            Archivadas
          </button>
        </div>

        <VCard>
          <p v-if="cargandoObras" class="text-sm text-text-soft">Cargando…</p>
          <VTable v-else :columns="columnasObras" :rows="obrasFiltradas">
            <template #cell-estado="{ row }">
              <VBadge :variant="row.estado === 'activa' ? 'success' : row.estado === 'pausada' ? 'warning' : 'default'">
                {{ row.estado }}
              </VBadge>
            </template>
            <template #cell-acciones="{ row }">
              <VButton variant="ghost" size="sm" @click="toggleArchivadaLocal(row)">
                {{ row.archivadaLocal ? 'Reactivar acá' : 'Archivar acá' }}
              </VButton>
            </template>
          </VTable>
          <p v-if="!cargandoObras && !obrasFiltradas.length" class="py-4 text-center text-sm text-text-soft">
            No hay obras {{ vistaObras === 'archivadas' ? 'archivadas' : 'activas' }}.
          </p>
        </VCard>
      </template>

      <template v-else>
        <div class="mb-3 flex justify-end">
          <VButton size="sm" @click="abrirNuevo"> + Nuevo {{ entidadActual.nombreSingular }} </VButton>
        </div>

        <VCard>
          <p v-if="cargando" class="text-sm text-text-soft">Cargando…</p>
          <VTable v-else :columns="columnasConAcciones" :rows="registros">
            <template #cell-activo="{ row }">
              <VBadge :variant="row.activo ? 'success' : 'default'">
                {{ row.activo ? 'Activo' : 'Inactivo' }}
              </VBadge>
            </template>
            <template #cell-acciones="{ row }">
              <div class="flex gap-1.5">
                <VButton variant="secondary" size="sm" @click="abrirEdicion(row)">Editar</VButton>
                <VButton variant="ghost" size="sm" @click="toggleActivo(row)">
                  {{ row.activo ? 'Desactivar' : 'Activar' }}
                </VButton>
              </div>
            </template>
          </VTable>
          <p v-if="!cargando && !registros.length" class="py-4 text-center text-sm text-text-soft">
            No hay {{ entidadActual.label.toLowerCase() }} cargados todavía.
          </p>
        </VCard>
      </template>
    </VSection>

    <!-- v-if="entidadActual": este modal es el de crear/editar de los
         catálogos genéricos (ENTIDADES) — no existe para el tab "Obras"
         (entidadActual da undefined ahí, ver comentario en <script>). Sin
         este guard, ":title" de acá abajo tira "Cannot read properties of
         undefined" apenas se entra a Obras — el :title de un componente
         siempre se evalúa al crear su VNode, aunque el modal esté cerrado
         (bug real reportado por Federico 2026-09-08: "cuando toco el tab
         obras queda en blanco"). -->
    <VModal
      v-if="entidadActual"
      :open="modalAbierto"
      :title="(editandoId ? 'Editar ' : 'Nuevo ') + entidadActual.nombreSingular"
      @update:open="modalAbierto = $event"
    >
      <form class="space-y-3" @submit.prevent="guardar">
        <label v-for="campo in entidadActual.campos" :key="campo.key" class="block text-sm text-text-mid">
          <template v-if="campo.type === 'checkbox'">
            <span class="flex items-center gap-2">
              <input v-model="formData[campo.key]" type="checkbox" />
              {{ campo.label }}
            </span>
          </template>
          <template v-else-if="campo.type === 'number'">
            {{ campo.label }}
            <!-- step="any" (2026-09-09, bug real reportado por Federico: "solo me
                 deja poner números redondos" al editar Tara en Camiones) — sin
                 step, el navegador asume step="1" (enteros); en el teclado
                 numérico de mobile eso hace que ni aparezca la tecla del punto
                 decimal. Aplica a todos los campos numéricos genéricos de Maestros
                 (Tara, mínimo/máximo de Stock en Materiales) — ninguno es
                 conceptualmente entero-only. -->
            <input
              v-model.number="formData[campo.key]"
              type="number"
              step="any"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </template>
          <template v-else>
            {{ campo.label }}
            <input
              v-model="formData[campo.key]"
              type="text"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            />
          </template>
        </label>

        <label class="flex items-center gap-2 text-sm text-text-mid">
          <input v-model="formData.activo" type="checkbox" />
          Activo
        </label>

        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="guardando">{{ guardando ? 'Guardando…' : 'Guardar' }}</VButton>
        </div>
      </form>
    </VModal>
  </div>
</template>
