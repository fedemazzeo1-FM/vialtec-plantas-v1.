-- ============================================================================
-- Migración 35: Catálogo de Clientes (Maestros → tab "Clientes")
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido explícito de Federico (2026-09-09): un tab de Maestros para
-- gestionar los clientes que compran asfalto/hormigón por "Venta externa"
-- (plantas_pedidos.tipo_pedido = 'venta'), y que el campo "Cliente externo"
-- del alta/edición de Pedidos pase de texto libre a un <select> sobre este
-- catálogo.
--
-- No existía ninguna tabla equivalente: modules-status.md ya documentaba
-- "clientes (7) sin migrar (falta tabla, requiere autorización)" desde la
-- auditoría de Maestros del 2026-09-01 — los 7 clientes del legado viven en
-- `kv_store` (clave vt_maestros9.clientes) y NO se migran acá (fuera de
-- alcance de este pedido puntual; si Federico quiere backfillearlos, es una
-- tarea aparte con el mismo protocolo de aviso de datos).
--
-- Diseño: mismo patrón que plantas_proveedores/plantas_materiales (catálogo
-- liviano, memory/conventions.md — "Services obligatorios por módulo" +
-- "Componentes compartidos"). plantas_pedidos.cliente_externo SIGUE siendo
-- texto libre (sin FK nueva): el <select> de Pedidos consume este catálogo
-- para completar ese mismo campo por nombre, no se reemplaza el schema de
-- plantas_pedidos — cero riesgo sobre los pedidos de venta externa ya
-- migrados/cargados con un nombre de cliente que no esté (todavía) en este
-- catálogo (el front deja ver ese valor igual, ver PedidosView.vue).
-- ============================================================================

create table if not exists plantas_clientes (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null unique,
  cuit       text,
  contacto   text,
  telefono   text,
  activo     boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table plantas_clientes is
  'Catálogo de clientes de venta externa (asfalto/hormigón) — nombre alimenta el <select> de "Cliente externo" en Pedidos (plantas_pedidos.cliente_externo sigue siendo texto libre, sin FK).';

create index if not exists idx_plantas_clientes_activo on plantas_clientes (activo);

alter table plantas_clientes enable row level security;

-- Mismo patrón de RLS fina que la migración 23 ya dejó para el resto de los
-- catálogos de Maestros (plantas_materiales/proveedores/patentes/choferes/
-- encargados/formulas): lectura abierta a cualquier autenticado (lo
-- necesitan varios roles para el <select> de Pedidos), escritura restringida
-- a admin/plantista.
create policy "plantas_clientes: leer" on plantas_clientes
  for select to authenticated using (true);

create policy "plantas_clientes: crear admin/plantista" on plantas_clientes
  for insert to authenticated with check (plantas_rol_actual() in ('admin', 'plantista'));

create policy "plantas_clientes: editar admin/plantista" on plantas_clientes
  for update to authenticated
  using (plantas_rol_actual() in ('admin', 'plantista'))
  with check (plantas_rol_actual() in ('admin', 'plantista'));

create policy "plantas_clientes: borrar admin/plantista" on plantas_clientes
  for delete to authenticated using (plantas_rol_actual() in ('admin', 'plantista'));
