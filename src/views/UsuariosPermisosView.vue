<script setup>
// Módulo "Usuarios y Permisos por rol" (pedido de Federico, 2026-09-03):
// unifica en un solo lugar la administración de cuentas (tab "Usuarios") y
// la consulta de qué puede hacer cada rol (tab "Permisos por rol"). Acceso
// restringido a rol admin — doble guarda: el link de nav no aparece para
// otros roles (nav.js filtra por auth.puedeVerTab, y admin es el único rol
// con `tabs: 'todas'` en PERMISOS_POR_ROL) y el router bloquea el acceso
// directo por URL (router/index.js, mismo guard genérico que usa toda la
// app) — no hace falta un guard especial acá.
//
// La tab "Usuarios" depende de la migración 21 (policy "admin lee todos los
// usuarios" + RPC admin_upsert_usuario_rol) — APLICADA 2026-09-03 noche con
// confirmación explícita de Federico, ver supabase/migrations/21_admin_gestion_usuarios_roles.sql
// y memory/pending.md.

import { computed, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import VSection from '@/components/shared/VSection.vue'
import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VButton from '@/components/shared/VButton.vue'
import { useUsuariosRoles } from '@/modules/usuarios/composables/useUsuariosRoles'
import { PERMISOS_POR_ROL } from '@/stores/auth.store'

const TABS = ['usuarios', 'permisos']
const route = useRoute()
const router = useRouter()
const tabActiva = ref(TABS.includes(route.query.tab) ? route.query.tab : TABS[0])
function irATab(tab) {
  tabActiva.value = tab
  router.replace({ query: { ...route.query, tab } })
}

const {
  usuarios,
  obras,
  cargando,
  error,
  modalAbierto,
  guardando,
  editandoId,
  formData,
  rolesDisponibles,
  cargar,
  abrirNuevo,
  abrirEdicion,
  guardar,
  toggleActivo,
} = useUsuariosRoles()
cargar()

const columnas = [
  { key: 'email', label: 'Email' },
  { key: 'rol', label: 'Rol' },
  { key: 'obras', label: 'Obras visibles' },
  { key: 'ver_ventas', label: 'Ve ventas' },
  { key: 'activo', label: 'Estado' },
  { key: 'acciones', label: '' },
]

function nombreObra(id) {
  return obras.value.find((o) => o.id === id)?.nombre ?? `Obra #${id}`
}

const obrasSeleccionadasTexto = computed(() =>
  formData.obraIds.length ? formData.obraIds.map(nombreObra).join(', ') : 'Ninguna'
)
function toggleObra(id) {
  const i = formData.obraIds.indexOf(id)
  if (i === -1) formData.obraIds.push(id)
  else formData.obraIds.splice(i, 1)
}

// Etiquetas legibles de los campos de PERMISOS_POR_ROL, para el bloque
// "Pantallas visibles" de la tab "Permisos por rol" — mismo orden en el
// que se definen en auth.store.js.
const CAMPOS_PERMISO = [
  { key: 'tabs', label: 'Pantallas visibles' },
  { key: 'crearPedido', label: 'Crear pedido' },
  { key: 'confirmar', label: 'Confirmar pedido' },
  { key: 'despachar', label: 'Despachar' },
  { key: 'stock', label: 'Stock' },
  { key: 'verVentas', label: 'Ver ventas' },
]
function formatearPermiso(valor) {
  if (valor === 'todas') return 'Todas'
  if (Array.isArray(valor)) return valor.join(', ')
  if (valor === true) return 'Sí'
  if (valor === false) return 'No'
  if (valor === 'editar') return 'Editar'
  if (valor === 'ver') return 'Solo ver'
  return String(valor)
}

// -----------------------------------------------------------------------
// Matriz REAL de permisos (2026-09-06, migración 23 — tarea P0.2).
//
// A diferencia de PERMISOS_POR_ROL de arriba (que solo controla qué
// pestañas/botones muestra la UI — un usuario con la pestaña oculta igual
// podría llamar la API directo si el server no lo bloqueara), esto
// documenta el chequeo real server-side: cada fila cita la RPC
// `SECURITY DEFINER` o la policy de RLS que lo hace cumplir, no salteable
// desde el cliente. Auditado en vivo contra pg_proc/pg_policies de
// producción al escribir la migración 23 — si se cambia el rol permitido
// de una RPC o una policy, hay que actualizar esto a mano (no se puede
// introspectar en runtime desde el frontend).
const ROLES_MATRIZ = ['admin', 'plantista', 'encargado', 'supervisor', 'balancero', 'gerencia', 'plantista_hormigon']

const MATRIZ_REAL_PERMISOS = [
  {
    seccion: 'Pedidos',
    filas: [
      { accion: 'Crear pedido', fuente: 'RPC crear_pedido', roles: ['admin', 'plantista', 'encargado', 'supervisor'] },
      { accion: 'Confirmar pedido', fuente: 'RPC confirmar_pedido', roles: ['admin', 'plantista'] },
      {
        accion: 'Postergar pedido',
        fuente: 'RPC postergar_pedido',
        roles: ROLES_MATRIZ,
        nota: 'Único caso sin chequeo de rol en el servidor — cualquier autenticado puede postergar si tiene la pantalla visible. Hallazgo de esta auditoría, no corregido todavía (no fue pedido).',
      },
      { accion: 'Cancelar pedido', fuente: 'RPC cancelar_pedido', roles: ['admin', 'plantista', 'encargado', 'supervisor'] },
      { accion: 'Archivar pedido', fuente: 'RPC archivar_pedido', roles: ['admin', 'plantista'] },
      { accion: 'Finalizar despacho (cerrar)', fuente: 'RPC finalizar_despacho', roles: ['admin', 'plantista', 'plantista_hormigon'] },
      { accion: 'Corregir despacho', fuente: 'RPC corregir_despacho', roles: ['admin', 'plantista', 'plantista_hormigon'] },
    ],
  },
  {
    seccion: 'Báscula',
    filas: [
      { accion: 'Ver historial de Báscula (vales/ingresos)', fuente: 'RLS plantas_vales / plantas_ingresos', roles: ['admin', 'plantista', 'balancero'] },
      { accion: 'Registrar pesada (vale asfalto / ingreso / egreso árido)', fuente: 'RPC registrar_pesada_bascula', roles: ['admin', 'plantista', 'balancero'] },
      { accion: 'Registrar carga de asfalto (desde Pedidos)', fuente: 'RPC registrar_carga_asfalto', roles: ['admin', 'plantista'] },
      { accion: 'Registrar carga de hormigón', fuente: 'RPC registrar_carga_hormigon', roles: ['admin', 'plantista', 'plantista_hormigon'] },
    ],
  },
  {
    seccion: 'Stock',
    filas: [
      { accion: 'Ver Stock e historial de movimientos', fuente: 'RLS plantas_stock / plantas_stock_movimientos', roles: ['admin', 'plantista', 'balancero', 'gerencia'] },
      { accion: 'Movimiento manual (ingreso/egreso)', fuente: 'RPC registrar_movimiento_manual', roles: ['admin', 'plantista'] },
      { accion: 'Relevamiento mensual', fuente: 'RPC registrar_relevamiento_stock', roles: ['admin', 'plantista'] },
    ],
  },
  {
    seccion: 'Maestros',
    filas: [
      {
        accion: 'Ver catálogos (fórmulas, materiales, patentes, proveedores, choferes, encargados)',
        fuente: 'RLS — SELECT abierto',
        roles: ROLES_MATRIZ,
      },
      { accion: 'Crear / editar / borrar catálogos', fuente: 'RLS — INSERT/UPDATE/DELETE', roles: ['admin', 'plantista'] },
    ],
  },
  {
    seccion: 'Usuarios y Permisos',
    filas: [{ accion: 'Administrar usuarios y roles', fuente: 'RPC admin_upsert_usuario_rol + RLS plantas_usuarios_roles', roles: ['admin'] }],
  },
]

// Columnas de VTable para la matriz de arriba: Acción + una por rol (con
// slot #cell-<rol> para el ✓/—) + Fuente.
const columnasMatriz = [
  { key: 'accion', label: 'Acción' },
  ...ROLES_MATRIZ.map((rol) => ({ key: rol, label: rol })),
  { key: 'fuente', label: 'Dónde se aplica' },
]
</script>

<template>
  <div>
    <VSection title="Usuarios y Permisos por rol">
      <div class="mb-4 flex gap-1 overflow-x-auto border-b border-border">
        <button
          v-for="tab in TABS"
          :key="tab"
          type="button"
          class="shrink-0 whitespace-nowrap border-b-2 px-3 py-2 text-sm font-semibold transition-colors duration-150"
          :class="tab === tabActiva ? 'border-vialtec text-vialtec' : 'border-transparent text-text-soft hover:text-text-mid'"
          @click="irATab(tab)"
        >
          {{ tab === 'usuarios' ? 'Usuarios' : 'Permisos por rol' }}
        </button>
      </div>

      <!-- Tab Usuarios -->
      <template v-if="tabActiva === 'usuarios'">
        <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
          {{ error }}
        </div>

        <div class="mb-3 flex justify-end">
          <VButton size="sm" @click="abrirNuevo"> + Nuevo usuario </VButton>
        </div>

        <VCard>
          <p v-if="cargando" class="text-sm text-text-soft">Cargando…</p>
          <VTable v-else :columns="columnas" :rows="usuarios">
            <template #cell-rol="{ row }">
              <VBadge>{{ row.rol }}</VBadge>
            </template>
            <template #cell-obras="{ row }">
              <span class="text-xs text-text-soft">
                {{ row.ver_todas_obras ? 'Todas' : (row.obra_ids?.length ? row.obra_ids.map(nombreObra).join(', ') : '—') }}
              </span>
            </template>
            <template #cell-ver_ventas="{ row }">
              <VBadge :variant="row.ver_ventas ? 'success' : 'default'">{{ row.ver_ventas ? 'Sí' : 'No' }}</VBadge>
            </template>
            <template #cell-activo="{ row }">
              <VBadge :variant="row.activo ? 'success' : 'default'">{{ row.activo ? 'Activo' : 'Inactivo' }}</VBadge>
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
          <p v-if="!cargando && !usuarios.length" class="py-4 text-center text-sm text-text-soft">
            No hay usuarios cargados todavía.
          </p>
        </VCard>
      </template>

      <!-- Tab Permisos por rol -->
      <template v-else>
        <h3 class="mb-1 text-sm font-semibold text-text-strong">Matriz real — qué bloquea de verdad el servidor</h3>
        <p class="mb-3 text-xs text-text-soft">
          Cada fila cita la RPC <code>SECURITY DEFINER</code> o la policy de RLS que hace
          cumplir esa acción — no salteable desde el cliente aunque alguien llame la API
          directo. Auditado en vivo contra <code>pg_proc</code>/<code>pg_policies</code> de
          producción al escribir la migración 23 (2026-09-06, tarea P0.2). Distinto de
          "Pantallas visibles" más abajo, que solo controla qué muestra la UI.
        </p>
        <div class="space-y-5">
          <div v-for="grupo in MATRIZ_REAL_PERMISOS" :key="grupo.seccion">
            <h4 class="mb-1.5 text-xs font-bold uppercase tracking-wide text-text-soft">{{ grupo.seccion }}</h4>
            <VCard>
              <VTable :columns="columnasMatriz" :rows="grupo.filas">
                <template #cell-accion="{ row }">
                  {{ row.accion }}
                  <p v-if="row.nota" class="mt-1 text-xs text-danger">⚠ {{ row.nota }}</p>
                </template>
                <template v-for="rol in ROLES_MATRIZ" :key="rol" #[`cell-${rol}`]="{ row }">
                  <span v-if="row.roles.includes(rol)" class="text-success">✓</span>
                  <span v-else class="text-text-soft/40">—</span>
                </template>
                <template #cell-fuente="{ row }">
                  <code class="text-xs text-text-soft">{{ row.fuente }}</code>
                </template>
              </VTable>
            </VCard>
          </div>

          <div>
            <h4 class="mb-1.5 text-xs font-bold uppercase tracking-wide text-text-soft">Visibilidad de Pedidos por obra (no es por rol)</h4>
            <p class="text-xs text-text-soft">
              Qué obras ve cada usuario en Pedidos/Despachos/Cargas/Historial no depende del
              rol sino de su fila individual en <code>plantas_usuarios_roles</code>
              (<code>ver_todas_obras</code>, <code>obra_ids</code>, <code>ver_ventas</code> —
              RLS de <code>plantas_pedidos</code>/<code>plantas_cargas_asfalto</code>/
              <code>plantas_cargas_hormigon</code>/<code>plantas_pedidos_historial</code>,
              migraciones 17 y 23). Se administra desde la tab "Usuarios" de acá arriba, no
              hay nada que configurar por rol. Hoy los 22 usuarios reales tienen
              <code>ver_todas_obras = true</code> — el filtro no restringe a nadie todavía.
            </p>
          </div>
        </div>

        <h3 class="mb-1 mt-6 text-sm font-semibold text-text-strong">Pantallas visibles (solo UI)</h3>
        <p class="mb-3 text-xs text-text-soft">
          Controla qué pestañas/botones muestra la interfaz — se define en
          <code>src/stores/auth.store.js#PERMISOS_POR_ROL</code>. No es un control de
          seguridad por sí solo, es la matriz de arriba la que no se puede saltear.
        </p>
        <div class="space-y-4">
          <VCard v-for="(permisos, rol) in PERMISOS_POR_ROL" :key="rol">
            <h3 class="mb-2 text-sm font-semibold text-text-strong">{{ rol }}</h3>
            <dl class="grid grid-cols-1 gap-x-6 gap-y-1.5 sm:grid-cols-2">
              <div v-for="campo in CAMPOS_PERMISO" :key="campo.key" class="flex justify-between gap-3 text-sm">
                <dt class="text-text-soft">{{ campo.label }}</dt>
                <dd class="text-right font-medium text-text-mid">{{ formatearPermiso(permisos[campo.key]) }}</dd>
              </div>
            </dl>
          </VCard>
        </div>
      </template>
    </VSection>

    <VModal :open="modalAbierto" :title="(editandoId ? 'Editar' : 'Nuevo') + ' usuario'" @update:open="modalAbierto = $event">
      <form class="space-y-3" @submit.prevent="guardar">
        <label class="block text-sm text-text-mid">
          Email
          <input
            v-model="formData.email"
            type="email"
            :disabled="!!editandoId"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none disabled:bg-gray-50 disabled:text-text-soft"
          />
        </label>

        <label class="block text-sm text-text-mid">
          Rol
          <select
            v-model="formData.rol"
            class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
          >
            <option v-for="rol in rolesDisponibles" :key="rol" :value="rol">{{ rol }}</option>
          </select>
        </label>

        <label class="flex items-center gap-2 text-sm text-text-mid">
          <input v-model="formData.verVentas" type="checkbox" />
          Ve ventas externas
        </label>

        <label class="flex items-center gap-2 text-sm text-text-mid">
          <input v-model="formData.verTodasObras" type="checkbox" />
          Ve todas las obras
        </label>

        <div v-if="!formData.verTodasObras" class="rounded-lg border border-border p-2">
          <p class="mb-1.5 text-xs text-text-soft">Obras visibles: {{ obrasSeleccionadasTexto }}</p>
          <div class="max-h-32 space-y-1 overflow-y-auto">
            <label v-for="obra in obras" :key="obra.id" class="flex items-center gap-2 text-sm text-text-mid">
              <input
                type="checkbox"
                :checked="formData.obraIds.includes(obra.id)"
                @change="toggleObra(obra.id)"
              />
              {{ obra.nombre }}
            </label>
          </div>
        </div>

        <label class="flex items-center gap-2 text-sm text-text-mid">
          <input v-model="formData.activo" type="checkbox" />
          Activo
        </label>

        <div v-if="error" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
          {{ error }}
        </div>

        <div class="flex justify-end gap-2 pt-2">
          <VButton type="button" variant="secondary" @click="modalAbierto = false">Cancelar</VButton>
          <VButton type="submit" :disabled="guardando">{{ guardando ? 'Guardando…' : 'Guardar' }}</VButton>
        </div>
      </form>
    </VModal>
  </div>
</template>
