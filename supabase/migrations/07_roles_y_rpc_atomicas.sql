-- ============================================================================
-- Migración 07: Roles propios de VialTec Plantas + RPC atómicas de báscula/hormigón
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- IMPORTANTE (memory/procedimientos.md): este archivo queda guardado para
-- revisión previa de Federico. NO se ejecutó contra Supabase todavía.
--
-- Decisión de diseño CONFIRMADA por Federico: NO se reusa
-- flota_roles/flota_rol_permisos. flota_usuarios_email.rol es texto libre
-- sin FK, con nombres que no coinciden 1:1 contra flota_roles (verificado
-- contra el schema real: "Admin" vs "admin", "Encargado de Obra" vs
-- "encargado_obra", roles como "Encargado del Sistema"/"Gerente de Equipos"
-- que no existen en flota_roles), y ninguno de los 7 roles de
-- memory/business-rules.md (plantista, supervisor, balancero,
-- plantista_hormigon) existe en flota_roles hoy. Autenticación sí usa
-- Supabase Auth (compartido, ya usado por flota) — solo el mapeo de rol es
-- propio de este proyecto.
--
-- Depende de: 02_pedidos.sql (plantas_pedidos), 04_bascula_y_vales.sql
-- (plantas_vales), 05_analitica_y_vistas.sql (plantas_ingresos), todas sin
-- aplicar todavía.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) plantas_usuarios_roles
-- ----------------------------------------------------------------------------
create table if not exists plantas_usuarios_roles (
  id                uuid primary key default gen_random_uuid(),
  email             text not null unique,
  rol               text not null
                    check (rol in ('admin', 'plantista', 'encargado', 'supervisor', 'balancero', 'gerencia', 'plantista_hormigon')),
  ver_todas_obras   boolean not null default false,
  ver_ventas        boolean not null default false,
  obra_ids          bigint[] not null default '{}',  -- flota_obras.id, solo relevante si ver_todas_obras = false
  activo            boolean not null default true,
  created_at        timestamptz not null default now()
);

comment on table plantas_usuarios_roles is
  'Mapeo email -> rol de VialTec Plantas (los 7 roles de memory/business-rules.md). Independiente de flota_roles a propósito, ver nota de la migración.';

alter table plantas_usuarios_roles enable row level security;

-- Fase 1 (RLS avanzada queda para la tarea dedicada, confirmado por
-- Federico): cada usuario autenticado puede leer SU PROPIA fila (necesario
-- para que el login resuelva su rol). Gestión (insert/update/delete) queda
-- sin policy todavía -> solo con la service role, hasta que exista la
-- pantalla ABM de Roles (PENDIENTE, memory/modules-status.md #10).
create policy "usuario lee su propio rol"
  on plantas_usuarios_roles for select
  to authenticated
  using (email = auth.email());

-- ----------------------------------------------------------------------------
-- 2) Helper: rol del usuario autenticado actual
-- ----------------------------------------------------------------------------
create or replace function plantas_rol_actual()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select rol
  from plantas_usuarios_roles
  where email = auth.email()
    and activo = true
  limit 1;
$$;

comment on function plantas_rol_actual() is
  'Rol de VialTec Plantas del usuario autenticado actual, o null si no tiene uno asignado/activo. Reutilizable en RLS futuras y en las RPC atómicas de abajo.';

-- ----------------------------------------------------------------------------
-- 3) registrar_pesada_bascula — atómica (reemplaza el flujo multi-paso de
--    bascula.service.js#registrarPesada). El `for update` sobre el pedido es
--    lo que soluciona la race condition de slots paralelos pesando el mismo
--    pedido a la vez.
-- ----------------------------------------------------------------------------
create or replace function registrar_pesada_bascula(
  p_tipo_vale        text,
  p_peso_bruto       numeric,
  p_tara             numeric,
  p_pedido_id        uuid default null,
  p_obra_id          bigint default null,
  p_patente          text default null,
  p_chofer           text default null,
  p_unidad           text default 'tn',
  p_observaciones    text default null,
  p_fecha_pesada     timestamptz default now(),
  p_material         text default null,
  p_proveedor        text default null,
  p_numero_remito    text default null,
  p_cantidad_remito  numeric default null
)
returns plantas_vales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol           text;
  v_pedido        plantas_pedidos;
  v_peso_neto     numeric;
  v_obra_id       bigint;
  v_neto_tn       numeric;
  v_acumulado_tn  numeric;
  v_vale          plantas_vales;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'balancero') then
    raise exception 'Tu rol (%) no puede registrar pesadas de báscula.', coalesce(v_rol, 'sin rol asignado');
  end if;

  if not (p_peso_bruto > 0) then
    raise exception 'peso_bruto debe ser mayor a 0';
  end if;
  if not (p_tara >= 0) then
    raise exception 'tara no puede ser negativa';
  end if;
  if not (p_peso_bruto > p_tara) then
    raise exception 'el peso bruto debe ser mayor que la tara';
  end if;

  v_peso_neto := p_peso_bruto - p_tara;

  -- Lock del pedido (si hay) ANTES de leer cantidad_despachada: esto es lo
  -- que hace atómico el incremento entre slots paralelos.
  if p_pedido_id is not null then
    select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
    if not found then
      raise exception 'El pedido % no existe.', p_pedido_id;
    end if;
  end if;

  v_obra_id := coalesce(p_obra_id, v_pedido.obra_id);
  v_neto_tn := case when p_unidad = 'kg' then v_peso_neto / 1000 else v_peso_neto end;

  -- Acumulado dinámico (foto informativa, mismo criterio que
  -- obtenerAcumuladoObraHastaFecha en bascula.service.js — el remito
  -- impreso lo sigue recalculando en el momento, no lee esta columna).
  if v_obra_id is not null and p_tipo_vale = 'asfalto' then
    select coalesce(sum(case when unidad = 'kg' then peso_neto / 1000 else peso_neto end), 0)
      into v_acumulado_tn
      from plantas_vales
      where obra_id = v_obra_id
        and tipo_vale = 'asfalto'
        and fecha_pesada >= date_trunc('day', p_fecha_pesada)
        and fecha_pesada <= p_fecha_pesada;
    v_acumulado_tn := v_acumulado_tn + v_neto_tn;
  end if;

  insert into plantas_vales (
    tipo_vale, pedido_id, obra_id, patente, chofer,
    peso_bruto, tara, peso_neto, unidad, acumulado_obra_tn, fecha_pesada, observaciones
  ) values (
    p_tipo_vale, p_pedido_id, v_obra_id, p_patente, p_chofer,
    p_peso_bruto, p_tara, v_peso_neto, p_unidad, v_acumulado_tn, p_fecha_pesada, p_observaciones
  )
  returning * into v_vale;

  if p_pedido_id is not null and p_tipo_vale = 'asfalto' then
    update plantas_pedidos
      set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + v_neto_tn,
          estado = case
            when coalesce(v_pedido.cantidad_despachada, 0) + v_neto_tn >= v_pedido.cantidad_solicitada
            then 'despachado' else estado end
      where id = p_pedido_id;
  end if;

  if p_tipo_vale = 'ingreso_arido' then
    if p_material is null or p_proveedor is null then
      raise exception 'Un ingreso de áridos necesita material y proveedor.';
    end if;
    insert into plantas_ingresos (
      material, proveedor, numero_remito, cantidad, unidad, origen, vale_id, fecha_ingreso, observaciones
    ) values (
      p_material, p_proveedor, p_numero_remito, coalesce(p_cantidad_remito, v_neto_tn), 'tn',
      'bascula', v_vale.id, p_fecha_pesada, p_observaciones
    );
  end if;

  -- TODO(stock): acá va el descuento de insumos cuando exista plantas_stock
  -- (mismo TODO que ya estaba en bascula.service.js, ahora movido acá).

  return v_vale;
end;
$$;

comment on function registrar_pesada_bascula is
  'Registra un vale de báscula (asfalto/hormigón/ingreso de árido) y actualiza el pedido asociado de forma atómica. Reemplaza el flujo multi-paso de bascula.service.js#registrarPesada — ver memory/pending.md.';

-- ----------------------------------------------------------------------------
-- 4) registrar_carga_hormigon — atómica (reemplaza
--    pedidos.service.js#registrarCargaHormigon).
-- ----------------------------------------------------------------------------
create or replace function registrar_carga_hormigon(
  p_pedido_id       uuid,
  p_numero_remito   text,
  p_volumen_m3      numeric,
  p_patente_mixer   text default null,
  p_chofer          text default null,
  p_fecha_carga     timestamptz default now(),
  p_observaciones   text default null
)
returns plantas_cargas_hormigon
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rol    text;
  v_pedido plantas_pedidos;
  v_carga  plantas_cargas_hormigon;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista', 'plantista_hormigon') then
    raise exception 'Tu rol (%) no puede registrar cargas de hormigón.', coalesce(v_rol, 'sin rol asignado');
  end if;

  if not (p_volumen_m3 > 0) then
    raise exception 'volumen_m3 debe ser mayor a 0';
  end if;
  if p_numero_remito is null or btrim(p_numero_remito) = '' then
    raise exception 'numero_remito es obligatorio';
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.tipo <> 'hormigon' then
    raise exception 'El pedido no es de hormigón.';
  end if;
  if v_pedido.estado <> 'confirmado' then
    raise exception 'El pedido tiene que estar confirmado.';
  end if;

  insert into plantas_cargas_hormigon (
    pedido_id, obra_id, numero_remito, volumen_m3, patente_mixer, chofer, fecha_carga, observaciones
  ) values (
    v_pedido.id, v_pedido.obra_id, btrim(p_numero_remito), p_volumen_m3, p_patente_mixer, p_chofer, p_fecha_carga, p_observaciones
  )
  returning * into v_carga;

  update plantas_pedidos
    set cantidad_despachada = coalesce(v_pedido.cantidad_despachada, 0) + p_volumen_m3,
        estado = case
          when coalesce(v_pedido.cantidad_despachada, 0) + p_volumen_m3 >= v_pedido.cantidad_solicitada
          then 'despachado' else estado end
    where id = p_pedido_id;

  return v_carga;
end;
$$;

comment on function registrar_carga_hormigon is
  'Registra una carga de hormigón (remito por mixer) y actualiza el pedido asociado de forma atómica. Reemplaza pedidos.service.js#registrarCargaHormigon — ver memory/pending.md.';

-- ----------------------------------------------------------------------------
-- 5) Grants explícitos (no depender del default de Postgres de EXECUTE a
--    PUBLIC): solo `authenticated` puede ejecutar estas funciones.
-- ----------------------------------------------------------------------------
revoke execute on function plantas_rol_actual() from public;
grant execute on function plantas_rol_actual() to authenticated;

revoke execute on function registrar_pesada_bascula(text, numeric, numeric, uuid, bigint, text, text, text, text, timestamptz, text, text, text, numeric) from public;
grant execute on function registrar_pesada_bascula(text, numeric, numeric, uuid, bigint, text, text, text, text, timestamptz, text, text, text, numeric) to authenticated;

revoke execute on function registrar_carga_hormigon(uuid, text, numeric, text, text, timestamptz, text) from public;
grant execute on function registrar_carga_hormigon(uuid, text, numeric, text, text, timestamptz, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 6) Usuario admin inicial (confirmado por Federico)
-- ----------------------------------------------------------------------------
insert into plantas_usuarios_roles (email, rol, ver_todas_obras, ver_ventas)
values ('federico.mazzeo@vialtec.com.ar', 'admin', true, true)
on conflict (email) do update
  set rol = excluded.rol,
      ver_todas_obras = excluded.ver_todas_obras,
      ver_ventas = excluded.ver_ventas,
      activo = true;

-- ----------------------------------------------------------------------------
-- Nota importante para revisión — esto NO cierra el problema del todo:
-- Ambas funciones son security definer y atómicas, pero mientras
-- plantas_vales/plantas_pedidos/plantas_cargas_hormigon sigan sin RLS
-- (pendiente, confirmado por Federico que queda para la tarea dedicada de
-- RLS, prioridad P0.2), cualquiera con la anon key puede seguir
-- insertando/actualizando esas tablas DIRECTO por PostgREST, salteando
-- estas funciones y reintroduciendo la race condition. Cerrar esto del todo
-- requiere revocar insert/update directo sobre esas 3 tablas para el rol
-- `authenticated` y dejar solo `execute` sobre las funciones — parte de esa
-- tarea de RLS, no de esta migración.
-- ----------------------------------------------------------------------------
