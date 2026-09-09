// Composable del módulo Usuarios y Permisos por rol — orquesta estado/carga,
// la vista es solo template (memory/conventions.md).

import { reactive, ref } from 'vue'
import { fetchUsuarios, guardarUsuario, fetchRolesAsignables } from '@/modules/usuarios/services/usuarios.service'
import { fetchObras } from '@/services/flota.service'

function usuarioVacio() {
  return { email: '', rol: 'plantista', verTodasObras: false, verVentas: false, obraIds: [], activo: true }
}

export function useUsuariosRoles() {
  const usuarios = ref([])
  // `obras` (solo activas/no archivadas): para el selector de "qué obras
  // puede ver" al asignar — no tiene sentido ofrecer una obra archivada.
  const obras = ref([])
  // `obrasTodas`: para RESOLVER el nombre de obras YA asignadas a un
  // usuario (fix 2026-09-09, bug real reportado por Federico: "Obra #17",
  // "Obra #19" en la columna "Obras visibles" — un usuario asignado a una
  // obra que después se desactivó en Flota o se archivó acá, mismo patrón
  // ya resuelto para el Informe Mensual en informe-mensual.service.js). Una
  // asignación histórica no tiene que "desaparecer" solo porque la obra ya
  // no está activa hoy.
  const obrasTodas = ref([])
  const rolesDisponibles = ref([]) // [{id, nombre}] — dinámico desde plantas_roles (migración 26)
  const cargando = ref(false)
  const error = ref(null)

  const modalAbierto = ref(false)
  const guardando = ref(false)
  const editandoId = ref(null)
  const formData = reactive(usuarioVacio())

  async function cargar() {
    cargando.value = true
    error.value = null
    try {
      const [listaUsuarios, listaObras, listaObrasTodas, listaRoles] = await Promise.all([
        fetchUsuarios(),
        fetchObras(),
        fetchObras({ soloActivas: false }),
        fetchRolesAsignables(),
      ])
      usuarios.value = listaUsuarios
      obras.value = listaObras
      obrasTodas.value = listaObrasTodas
      rolesDisponibles.value = listaRoles
    } catch (e) {
      error.value = e.message
    } finally {
      cargando.value = false
    }
  }

  function abrirNuevo() {
    editandoId.value = null
    Object.assign(formData, usuarioVacio())
    modalAbierto.value = true
  }

  function abrirEdicion(usuario) {
    editandoId.value = usuario.id
    Object.assign(formData, {
      email: usuario.email,
      rol: usuario.rol,
      verTodasObras: usuario.ver_todas_obras,
      verVentas: usuario.ver_ventas,
      obraIds: usuario.obra_ids ?? [],
      activo: usuario.activo,
    })
    modalAbierto.value = true
  }

  async function guardar() {
    if (!formData.email.trim()) {
      error.value = 'El email es obligatorio.'
      return
    }
    guardando.value = true
    error.value = null
    try {
      await guardarUsuario(formData)
      modalAbierto.value = false
      await cargar()
    } catch (e) {
      error.value = e.message
    } finally {
      guardando.value = false
    }
  }

  async function toggleActivo(usuario) {
    error.value = null
    try {
      await guardarUsuario({
        email: usuario.email,
        rol: usuario.rol,
        verTodasObras: usuario.ver_todas_obras,
        verVentas: usuario.ver_ventas,
        obraIds: usuario.obra_ids ?? [],
        activo: !usuario.activo,
      })
      await cargar()
    } catch (e) {
      error.value = e.message
    }
  }

  return {
    usuarios,
    obras,
    obrasTodas,
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
  }
}
