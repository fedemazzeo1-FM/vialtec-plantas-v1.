// Constantes de estado de pedido — extraídas de PedidosView.vue (2026-09-04,
// rediseño en cards) para que PedidoCard.vue las comparta sin duplicar
// (memory/conventions.md: lógica compartida en un solo lugar).

export const ESTADOS = ['solicitado', 'confirmado', 'despachado', 'postergado', 'cancelado']

export const VARIANTE_ESTADO = {
  solicitado: 'default',
  confirmado: 'info',
  despachado: 'success',
  postergado: 'postergado',
  cancelado: 'danger',
}

// Colores de los 5 KPI de estado — confirmados contra el legado en vivo
// (memory/relevamiento-sistema-viejo.md Etapa 3: getComputedStyle real, no
// a ojo). postergado es violeta (mismo tono que la marca), no ámbar.
export const COLOR_KPI_ESTADO = {
  solicitado: 'bg-warning',
  confirmado: 'bg-info',
  despachado: 'bg-success',
  postergado: 'bg-vialtec',
  cancelado: 'bg-danger',
}

// Franja superior de color de cada card (2026-09-04, rediseño — replica al
// legado, mismo criterio de color que COLOR_KPI_ESTADO/VARIANTE_ESTADO).
export const COLOR_BORDE_ESTADO = {
  solicitado: 'border-t-warning',
  confirmado: 'border-t-info',
  despachado: 'border-t-success',
  postergado: 'border-t-vialtec',
  cancelado: 'border-t-danger',
}

export const ESTADOS_ARCHIVABLES = ['despachado', 'cancelado']
export const ESTADOS_EDITABLES = ['solicitado', 'confirmado']
// postergado -> confirmado es una transición válida del ciclo de vida
// (memory/business-rules.md: "POSTERGADO → CONFIRMADO → DESPACHADO") — un
// pedido postergado tiene que poder volver a confirmarse, postergarse de
// nuevo, o cancelarse, igual que uno solicitado.
export const ESTADOS_CONFIRMABLES = ['solicitado', 'postergado']
export const ESTADOS_POSTERGABLES = ['solicitado', 'confirmado', 'postergado']
export const ESTADOS_CANCELABLES = ['solicitado', 'confirmado', 'postergado']
