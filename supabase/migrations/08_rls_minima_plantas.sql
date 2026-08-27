-- ============================================================================
-- Migración 08: RLS mínima sobre las tablas plantas_*
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Contexto (no estaba en el plan original de Fase 1, se descubrió al aplicar
-- la migración 07): las 9 tablas plantas_* ya tenían RLS HABILITADO en la
-- base real (hay una función `rls_auto_enable()` en el proyecto — parece un
-- mecanismo a nivel de proyecto que auto-habilita RLS en tablas nuevas de
-- `public`), pero CERO políticas — confirmado con el security advisor de
-- Supabase (rls_enabled_no_policy en las 9 tablas). Sin este archivo, ningún
-- `select`/`insert`/`update` de la app funciona salvo a través de las RPC
-- security definer (migración 07).
--
-- Política CONFIRMADA por Federico: `for all to authenticated using (true)`
-- — cualquier usuario autenticado (de todo el proyecto Supabase compartido,
-- no solo los que tienen fila en plantas_usuarios_roles) puede
-- leer/crear/actualizar/borrar en estas 9 tablas. Esto es deliberadamente
-- MÁS abierto que mi borrador original (que exigía plantas_rol_actual() is
-- not null) — la restricción por rol/obra queda 100% para la tarea
-- dedicada P0.2, no acá.
--
-- Excepción: plantas_pedidos_historial (creada en la migración 06, no
-- estaba en el conteo de "9 tablas" original) NO se abre a UPDATE/DELETE acá
-- — es append-only por regla de negocio explícita (memory/business-rules.md:
-- "el historial de estados de un pedido es append-only"), así que solo lleva
-- SELECT + INSERT con using(true)/with check(true), no `for all`. Si se
-- prefiere unificar esto con el resto, avisar y se agrega.
--
-- Depende de: 06_ajustes_pedidos_vales_historial.sql (plantas_pedidos_historial).
-- ============================================================================

alter table plantas_pedidos enable row level security;
create policy "plantas_pedidos: acceso autenticado" on plantas_pedidos
  for all to authenticated using (true) with check (true);

alter table plantas_vales enable row level security;
create policy "plantas_vales: acceso autenticado" on plantas_vales
  for all to authenticated using (true) with check (true);

alter table plantas_ingresos enable row level security;
create policy "plantas_ingresos: acceso autenticado" on plantas_ingresos
  for all to authenticated using (true) with check (true);

alter table plantas_cargas_hormigon enable row level security;
create policy "plantas_cargas_hormigon: acceso autenticado" on plantas_cargas_hormigon
  for all to authenticated using (true) with check (true);

alter table plantas_formulas enable row level security;
create policy "plantas_formulas: acceso autenticado" on plantas_formulas
  for all to authenticated using (true) with check (true);

alter table plantas_encargados enable row level security;
create policy "plantas_encargados: acceso autenticado" on plantas_encargados
  for all to authenticated using (true) with check (true);

alter table plantas_proveedores enable row level security;
create policy "plantas_proveedores: acceso autenticado" on plantas_proveedores
  for all to authenticated using (true) with check (true);

alter table plantas_patentes enable row level security;
create policy "plantas_patentes: acceso autenticado" on plantas_patentes
  for all to authenticated using (true) with check (true);

alter table plantas_choferes enable row level security;
create policy "plantas_choferes: acceso autenticado" on plantas_choferes
  for all to authenticated using (true) with check (true);

-- plantas_pedidos_historial: append-only por regla de negocio (ver nota arriba).
alter table plantas_pedidos_historial enable row level security;
create policy "plantas_pedidos_historial: leer" on plantas_pedidos_historial
  for select to authenticated using (true);
create policy "plantas_pedidos_historial: crear" on plantas_pedidos_historial
  for insert to authenticated with check (true);

-- ----------------------------------------------------------------------------
-- Nota para P0.2 (tarea dedicada de RLS fina, todavía pendiente): reemplazar
-- estas policies `using (true)` por policies que lean plantas_rol_actual() y
-- plantas_usuarios_roles.obra_ids/ver_todas_obras para acotar por rol (ej.
-- solo plantista/admin puede actualizar plantas_pedidos.estado a
-- 'confirmado'/'despachado') y por obra (encargado/supervisor solo ven/tocan
-- sus obras asignadas). Hoy CUALQUIER usuario autenticado del proyecto
-- Supabase compartido (incluye usuarios de flota que no tienen ningún rol en
-- plantas_usuarios_roles) puede leer y escribir estas 9 tablas.
-- ----------------------------------------------------------------------------
