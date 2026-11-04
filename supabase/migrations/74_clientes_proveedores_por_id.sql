-- ============================================================================
-- Migración 74 — clientes y proveedores por identificador
-- ESTADO: BORRADOR, sin correr (Federico, 02/11/2026: ensayo y aplicación
-- juntos). Ensayo: supabase/scripts/dry_run_migracion_74.sql.
-- Reversión: supabase/scripts/revertir_migracion_74.sql.
-- ============================================================================
--
-- Problema (Federico, 02/11): editar el nombre de un cliente o proveedor en
-- Maestros dividía pedidos, despachos, ingresos e informes en dos, porque
-- plantas_pedidos.cliente_externo y plantas_ingresos.proveedor guardan el
-- nombre como texto, sin vínculo con el maestro.
--
-- Qué hace:
--   1. plantas_normalizar_nombre(): minúsculas, sin espacios de más. Índice
--      único sobre esa forma en plantas_clientes y plantas_proveedores: no
--      se pueden crear dos con el mismo nombre escrito distinto.
--   2. Unifica los clientes divididos (casos 1-5 aprobados por Federico el
--      02/11) y da de alta los que tienen pedidos y no estaban en el maestro.
--      VIAL 8 S.A y VIAL 8 S.A (EDMANCAR) quedan separados (Federico, 04/11:
--      mismo cliente, dos órdenes distintas). COLEGIO MOORLANDS no es un
--      cliente: es la obra propia Moorlands-Tortuguitas (Federico, 04/11) —
--      P-0015 y P-0112 pasan a pedidos de esa obra (id 28).
--      P-0123 (venta a AUTOVIA MERCOSUR, 28/07) tenía cargada por error la
--      obra Moorlands-Tortuguitas (Federico, 04/11): se le saca, al pedido y
--      a su carga de mixer (remito 12519), que es lo que lee Obras.
--   3. plantas_pedidos.cliente_id → plantas_clientes y
--      plantas_ingresos.proveedor_id → plantas_proveedores (FK, ON DELETE
--      RESTRICT), completados para todo el historial. Venta sin cliente_id:
--      no se puede (CHECK).
--   4. Triggers: al guardar un pedido o ingreso, el identificador sale del
--      nombre elegido (o el nombre del identificador) y el texto queda
--      SIEMPRE igual al nombre actual del maestro. Al editar el nombre en
--      Maestros, se reescribe en todos sus pedidos / ingresos / movimientos
--      de stock (para atrás); lo nuevo ya entra con el nombre nuevo (para
--      adelante). Un nombre que no está en el maestro se rechaza.
--   Las RPC (crear_pedido, actualizar_pedido, finalizar_despacho,
--   registrar_pesada_bascula, corregir_vale_bascula) no cambian: siguen
--   mandando el nombre y el trigger resuelve el identificador.
--   Respaldo de los textos que cambian en plantas_respaldo_mig74 (para la
--   reversión).
--
-- Maestro de proveedores compartido (Flota, en preparación): no se toca
-- nada de flota_* ni obras_*. Cuando exista, alcanza con vincular cada
-- plantas_proveedores.id con el compartido; los ingresos ya apuntan por id.
-- ============================================================================

-- 0. Control: el trigger de ingresos es el de producción (migración 63).
do $mig$
begin
  if md5(pg_get_functiondef('public.plantas_trg_ingresos_normalizar()'::regprocedure))
     <> '9ec7ae00fea65e98e09beaa9da18c413' then
    raise exception 'plantas_trg_ingresos_normalizar cambió en producción: revisar antes de aplicar la 74';
  end if;
  if exists (select 1 from information_schema.columns where table_name = 'plantas_pedidos' and column_name = 'cliente_id') then
    raise exception 'La 74 ya está aplicada (plantas_pedidos.cliente_id existe).';
  end if;
end;
$mig$;

-- 1. Nombre normalizado + únicos ---------------------------------------------
create function plantas_normalizar_nombre(p text)
returns text
language sql
immutable
set search_path to 'public'
as $$ select nullif(lower(regexp_replace(btrim(p), '\s+', ' ', 'g')), '') $$;

revoke execute on function plantas_normalizar_nombre(text) from public, anon;
grant execute on function plantas_normalizar_nombre(text) to authenticated;

-- Respaldo de lo que se cambia (pedidos y nombres del maestro).
create table plantas_respaldo_mig74 (
  tabla text not null,
  id uuid not null,
  columna text not null,
  valor_anterior text,
  primary key (tabla, id, columna)
);
alter table plantas_respaldo_mig74 enable row level security;
revoke all on plantas_respaldo_mig74 from public, anon, authenticated;

-- 2. Unificación de clientes -------------------------------------------------
-- COLEGIO MOORLANDS = obra propia Moorlands-Tortuguitas (id 28). P-0112 ya
-- tenía la obra cargada (y su carga de mixer también); P-0015 no tiene cargas.
insert into plantas_respaldo_mig74
select 'plantas_pedidos', p.id, c.columna, c.valor
  from plantas_pedidos p
  cross join lateral (values ('tipo_pedido', p.tipo_pedido), ('obra_id', p.obra_id::text), ('cliente_externo', p.cliente_externo)) c(columna, valor)
 where p.id in ('7dde927e-189a-43e3-975d-009c2f9b82d1', 'd43fe4d0-1147-4bb9-9972-9fba5ce38aab')
   and p.cliente_externo = 'COLEGIO MOORLANDS';
do $mig$
begin
  if (select count(*) from plantas_respaldo_mig74 where columna = 'tipo_pedido') <> 2
     or not exists (select 1 from flota_obras where id = 28 and nombre = 'Moorlands-Tortuguitas') then
    raise exception 'COLEGIO MOORLANDS: P-0015/P-0112 u obra 28 no son los esperados';
  end if;
end;
$mig$;
update plantas_pedidos set tipo_pedido = 'obra', obra_id = 28, cliente_externo = null
 where id in ('7dde927e-189a-43e3-975d-009c2f9b82d1', 'd43fe4d0-1147-4bb9-9972-9fba5ce38aab');

-- P-0123: venta a AUTOVIA MERCOSUR con la obra 28 cargada por error.
insert into plantas_respaldo_mig74
select 'plantas_pedidos', id, 'obra_id_p0123', obra_id::text from plantas_pedidos
 where id = '9ca7b987-2d41-42ce-adc2-bd371d1b63e5' and tipo_pedido = 'venta' and obra_id = 28;
insert into plantas_respaldo_mig74
select 'plantas_cargas_hormigon', id, 'obra_id', obra_id::text from plantas_cargas_hormigon
 where pedido_id = '9ca7b987-2d41-42ce-adc2-bd371d1b63e5' and obra_id = 28;
do $mig$
begin
  if (select count(*) from plantas_respaldo_mig74 where columna = 'obra_id_p0123') <> 1
     or (select count(*) from plantas_respaldo_mig74 where tabla = 'plantas_cargas_hormigon') <> 1 then
    raise exception 'P-0123: el pedido o su carga no son los esperados';
  end if;
end;
$mig$;
update plantas_pedidos set obra_id = null where id = '9ca7b987-2d41-42ce-adc2-bd371d1b63e5';
update plantas_cargas_hormigon set obra_id = null where pedido_id = '9ca7b987-2d41-42ce-adc2-bd371d1b63e5';

-- Nombres del maestro con espacios de más (casos 4 y 5).
insert into plantas_respaldo_mig74
select 'plantas_clientes', id, 'nombre', nombre from plantas_clientes
 where nombre <> regexp_replace(btrim(nombre), '\s+', ' ', 'g');
update plantas_clientes set nombre = regexp_replace(btrim(nombre), '\s+', ' ', 'g')
 where nombre <> regexp_replace(btrim(nombre), '\s+', ' ', 'g');

-- Altas: clientes con pedidos que no estaban en el maestro (nombre del más usado).
insert into plantas_clientes (nombre, activo) values
  ('G Y C CONSTRUCCIONES S.A', true),
  ('HV-VIAL S.A', true),
  ('CORRALON FILIBERTI', true),
  ('Corralon ramiro antonazzi', true),
  ('INMIX', true),
  ('Lucas Maldonado', true),
  ('Vialmani', true);

create unique index plantas_clientes_nombre_normalizado
  on plantas_clientes (plantas_normalizar_nombre(nombre));
create unique index plantas_proveedores_nombre_normalizado
  on plantas_proveedores (plantas_normalizar_nombre(nombre));

-- 3. Columnas con FK ---------------------------------------------------------
alter table plantas_pedidos
  add column cliente_id uuid references plantas_clientes(id) on update cascade on delete restrict;
alter table plantas_ingresos
  add column proveedor_id uuid references plantas_proveedores(id) on update cascade on delete restrict;
create index plantas_pedidos_cliente_id on plantas_pedidos (cliente_id);
create index plantas_ingresos_proveedor_id on plantas_ingresos (proveedor_id);

-- Variantes escritas distinto (casos 1 y 3: no coinciden ni normalizadas).
create temp table mig74_alias (alias text primary key, nombre text not null) on commit drop;
insert into mig74_alias values
  ('aggm-sa', 'AGGM CONTRUCCIONES'),
  ('hvvial s.a', 'HV-VIAL S.A'),
  ('municipalidad exaltacion de la cruz', 'Municipalidad de Exaltación de la Cruz');

insert into plantas_respaldo_mig74
select 'plantas_pedidos', p.id, 'cliente_externo', p.cliente_externo
  from plantas_pedidos p
  left join mig74_alias a on a.alias = plantas_normalizar_nombre(p.cliente_externo)
  join plantas_clientes c
    on plantas_normalizar_nombre(c.nombre) = plantas_normalizar_nombre(coalesce(a.nombre, p.cliente_externo))
 where p.cliente_externo is not null and p.cliente_externo <> c.nombre;

update plantas_pedidos p
   set cliente_id = c.id, cliente_externo = c.nombre
  from plantas_clientes c
 where p.cliente_externo is not null
   and plantas_normalizar_nombre(c.nombre) = plantas_normalizar_nombre(coalesce(
         (select a.nombre from mig74_alias a where a.alias = plantas_normalizar_nombre(p.cliente_externo)),
         p.cliente_externo));

update plantas_ingresos i
   set proveedor_id = pr.id
  from plantas_proveedores pr
 where plantas_normalizar_nombre(pr.nombre) = plantas_normalizar_nombre(i.proveedor);

do $mig$
declare v_sin_cliente int; v_sin_proveedor int;
begin
  select count(*) into v_sin_cliente from plantas_pedidos where cliente_externo is not null and cliente_id is null;
  select count(*) into v_sin_proveedor from plantas_ingresos where proveedor is not null and proveedor_id is null;
  if v_sin_cliente > 0 or v_sin_proveedor > 0 then
    raise exception 'Quedaron % pedidos sin cliente_id y % ingresos sin proveedor_id: revisar nombres.', v_sin_cliente, v_sin_proveedor;
  end if;
end;
$mig$;

alter table plantas_pedidos
  add constraint plantas_pedidos_venta_con_cliente check (tipo_pedido <> 'venta' or cliente_id is not null);

-- 4. Triggers ----------------------------------------------------------------
-- Pedidos: identificador y nombre siempre del maestro.
create function plantas_trg_pedidos_cliente()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_id     uuid;
  v_nombre text;
begin
  if new.cliente_id is not null
     and (tg_op = 'INSERT' or new.cliente_id is distinct from old.cliente_id
          or new.cliente_externo is not distinct from old.cliente_externo) then
    select nombre into v_nombre from plantas_clientes where id = new.cliente_id;
  elsif plantas_normalizar_nombre(new.cliente_externo) is not null then
    select id, nombre into v_id, v_nombre from plantas_clientes
     where plantas_normalizar_nombre(nombre) = plantas_normalizar_nombre(new.cliente_externo);
    if v_id is null then
      raise exception 'El cliente "%" no está en Maestros → Clientes.', btrim(new.cliente_externo);
    end if;
    new.cliente_id := v_id;
  else
    new.cliente_id := null;
  end if;
  new.cliente_externo := v_nombre;
  return new;
end;
$function$;
revoke execute on function plantas_trg_pedidos_cliente() from public, anon, authenticated;

create trigger plantas_pedidos_cliente
  before insert or update of cliente_externo, cliente_id on plantas_pedidos
  for each row execute function plantas_trg_pedidos_cliente();

-- Ingresos: mismo criterio (reemplaza la normalización por texto de la 63).
create or replace function public.plantas_trg_ingresos_normalizar()
 returns trigger
 language plpgsql
 set search_path to 'public'
as $function$
declare
  v_neto_tn numeric;
  v_id      uuid;
  v_nombre  text;
begin
  if tg_op = 'INSERT' or new.proveedor is distinct from old.proveedor or new.proveedor_id is distinct from old.proveedor_id then
    if new.proveedor_id is not null
       and (tg_op = 'INSERT' or new.proveedor_id is distinct from old.proveedor_id
            or new.proveedor is not distinct from old.proveedor) then
      select nombre into v_nombre from plantas_proveedores where id = new.proveedor_id;
    elsif plantas_normalizar_nombre(new.proveedor) is not null then
      select id, nombre into v_id, v_nombre from plantas_proveedores
       where plantas_normalizar_nombre(nombre) = plantas_normalizar_nombre(new.proveedor);
      if v_id is null then
        raise exception 'El proveedor "%" no está en Maestros → Proveedores.', btrim(new.proveedor);
      end if;
      new.proveedor_id := v_id;
    else
      new.proveedor_id := null;
    end if;
    new.proveedor := v_nombre;
  end if;

  if new.vale_id is not null and (tg_op = 'INSERT' or new.cantidad is distinct from old.cantidad) then
    select case when unidad = 'kg' then peso_neto / 1000 else peso_neto end into v_neto_tn
      from plantas_vales where id = new.vale_id;
    perform plantas_validar_cantidad_remito(
      case when new.unidad = 'kg' then new.cantidad / 1000 else new.cantidad end, v_neto_tn
    );
  end if;

  return new;
end;
$function$;

drop trigger plantas_ingresos_normalizar on plantas_ingresos;
create trigger plantas_ingresos_normalizar
  before insert or update of proveedor, proveedor_id, cantidad on plantas_ingresos
  for each row execute function plantas_trg_ingresos_normalizar();

-- Renombrar en Maestros: corrige todo lo cargado (security definer: pedidos e
-- ingresos no se editan directo desde la app, solo por RPC).
create function plantas_trg_clientes_renombrar()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  update plantas_pedidos set cliente_externo = new.nombre
   where cliente_id = new.id and cliente_externo is distinct from new.nombre;
  return null;
end;
$function$;
revoke execute on function plantas_trg_clientes_renombrar() from public, anon, authenticated;

create trigger plantas_clientes_renombrar
  after update of nombre on plantas_clientes
  for each row when (old.nombre is distinct from new.nombre)
  execute function plantas_trg_clientes_renombrar();

create function plantas_trg_proveedores_renombrar()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  update plantas_ingresos set proveedor = new.nombre
   where proveedor_id = new.id and proveedor is distinct from new.nombre;
  -- Los movimientos de stock guardan el proveedor en `origen` (texto, igual
  -- que la migración 63); el nombre es único, así que se corrigen por nombre.
  update plantas_stock_movimientos set origen = new.nombre
   where tipo in ('ingreso_proveedor', 'recalculo_bascula') and origen = old.nombre;
  return null;
end;
$function$;
revoke execute on function plantas_trg_proveedores_renombrar() from public, anon, authenticated;

create trigger plantas_proveedores_renombrar
  after update of nombre on plantas_proveedores
  for each row when (old.nombre is distinct from new.nombre)
  execute function plantas_trg_proveedores_renombrar();

-- 5. Auditoría del cambio ----------------------------------------------------
select plantas_auditar('CORREGIR', 'maestros', 'cliente', 'migracion-74',
  'Clientes y proveedores por identificador',
  'Migración 74: editar el nombre en Maestros ya no divide pedidos, ingresos ni informes',
  null,
  jsonb_build_object(
    'pedidos_renombrados', (select count(*) from plantas_respaldo_mig74 where tabla = 'plantas_pedidos' and columna = 'cliente_externo') - 2,
    'clientes_corregidos', (select count(*) from plantas_respaldo_mig74 where tabla = 'plantas_clientes'),
    'clientes_alta', 7,
    'pedidos_a_obra_moorlands_tortuguitas', jsonb_build_array('P-0015', 'P-0112'),
    'obra_quitada_por_error', jsonb_build_array('P-0123 (y su carga, remito 12519)'),
    'pedidos_con_cliente_id', (select count(*) from plantas_pedidos where cliente_id is not null),
    'ingresos_con_proveedor_id', (select count(*) from plantas_ingresos where proveedor_id is not null)));
