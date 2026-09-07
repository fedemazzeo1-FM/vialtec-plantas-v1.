// Composable de Administración — tab "Roles" (2026-09-06, migración 26).
// La vista (AdministracionView.vue) queda como template puro (memory/
// conventions.md): toda la carga/guardado vive acá.

import { reactive, ref } from 'vue'
import {
  MODULOS_MATRIZ,
  ACCIONES_MATRIZ,
  fetchRoles,
  fetchPermisosRol,
  generarIdRolUnico,
  guardarRol,
  toggleActivoRol,
} from '@/modules/usuarios/services/roles.service'

function matrizVacia() {
  const m = {}
  for (const modulo of MODULOS_MATRIZ) {
    m[modulo.key] = {}
    for (const accion of ACCIONES_MATRIZ) m[modulo.key][accion.key] = false
  }
  return m
}

export function useAdministracionRoles() {
  const roles = ref([])
  const cargando = ref(false)
  const error = ref(null)

  const modalAbierto = ref(false)
  const guardando = ref(false)
  const cargandoPermisos = ref(false)
  // null = alta nueva; si no, es el rol que se está editando ({id, nombre, descripcion, es_sistema})
  const rolEditando = ref(null)
  const formRol = reactive({ nombre: '', descripcion: '' })
  const permisos = reactive(matrizVacia())

  async function cargar() {
    cargando.value = true
    error.value = null
    try {
      roles.value = await fetchRoles()
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
  }

  function abrirNuevo() {
    rolEditando.value = null
    formRol.nombre = ''
    formRol.descripcion = ''
    Object.assign(permisos, matrizVacia())
    error.value = null
    modalAbierto.value = true
  }

  async function abrirEditar(rol) {
    rolEditando.value = rol
    formRol.nombre = rol.nombre
    formRol.descripcion = rol.descripcion ?? ''
    error.value = null
    modalAbierto.value = true
    cargandoPermisos.value = true
    try {
      Object.assign(permisos, await fetchPermisosRol(rol.id))
    } catch (e) {
      error.value = e.message
    } finally {
      cargandoPermisos.value = false
    }
  }

  async function guardar() {
    if (!formRol.nombre.trim()) {
      error.value = 'El nombre es obligatorio.'
      return
    }
    guardando.value = true
    error.value = null
    try {
      const esNuevo = !rolEditando.value
      const id = esNuevo ? await generarIdRolUnico(formRol.nombre) : rolEditando.value.id
      await guardarRol({ id, nombre: formRol.nombre.trim(), descripcion: formRol.descripcion.trim() || null, esNuevo, permisos })
      modalAbierto.value = false
      await cargar()
    } catch (e) {
      error.value = e.message
    } finally {
      guardando.value = false
    }
  }

  async function toggleActivo(rol) {
    error.value = null
    try {
      await toggleActivoRol(rol)
      await cargar()
    } catch (e) {
      error.value = e.message
    }
  }

  return {
    roles,
    cargando,
    error,
    modalAbierto,
    guardando,
    cargandoPermisos,
    rolEditando,
    formRol,
    permisos,
    modulosMatriz: MODULOS_MATRIZ,
    accionesMatriz: ACCIONES_MATRIZ,
    cargar,
    abrirNuevo,
    abrirEditar,
    guardar,
    toggleActivo,
  }
}
