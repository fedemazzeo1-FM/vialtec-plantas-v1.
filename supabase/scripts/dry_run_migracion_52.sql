-- ============================================================================
-- Dry-run de la migración 52 (número correlativo de pedido) contra producción.
-- Termina SIEMPRE con raise exception: no persiste nada (la secuencia se crea
-- dentro de la misma transacción, así que tampoco queda consumida).
-- No llama a finalizar_despacho (consumiría un N° de remito real): el residual
-- se prueba con un insert sin `numero`, que es el mismo mecanismo (DEFAULT).
-- ============================================================================
do $dry$
declare
  v_admin text; v_uid uuid; v_formula uuid; v_obra bigint;
  v_total int; v_n int; v_a int; v_b int; v_txt text; v_estado text; v_ok text := '';
begin
  select count(*) into v_total from plantas_pedidos;
  select r.email, u.id into v_admin, v_uid
    from plantas_usuarios_roles r join auth.users u on lower(u.email) = lower(r.email)
   where r.rol = 'admin' and r.activo limit 1;
  select id into v_formula from plantas_formulas where activo and tipo = 'asfalto' order by nombre limit 1;
  select id into v_obra from flota_obras order by id limit 1;

  execute $mig52$
-- ============================================================================
-- Migración 52: número correlativo de pedido (P-0001)
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Propuesta aprobada por Federico (2026-10-05), previa a la etapa 5 del
-- módulo de Auditoría (memory/pending.md, decisión 3): hoy un pedido solo se
-- identifica por su UUID; hace falta un número legible para buscarlo en
-- pantallas, WhatsApp, remitos y auditoría.
--
-- Decisiones:
--   1) Una sola numeración para todos los tipos (asfalto, hormigón, mezcla
--      cemento).
--   2) El pedido residual (finalizar_despacho con "dividir") toma un número
--      nuevo propio; la referencia al original sigue en observaciones.
--   3) Huecos aceptados: un número asignado no se reutiliza (cancelados lo
--      conservan; si una creación falla, ese número se pierde).
--
-- Qué hace:
--   - plantas_pedidos.numero (integer, NOT NULL, UNIQUE), alimentado por la
--     secuencia plantas_pedidos_numero_seq (segura ante altas simultáneas).
--   - Los pedidos existentes se numeran por orden de creación
--     (created_at, id): el más viejo es el 1.
--   - No se recrea ninguna función: crear_pedido y el residual de
--     finalizar_despacho insertan sin nombrar la columna y toman el número
--     por el DEFAULT.
--   - plantas_etiqueta_pedido(numero) -> 'P-0001' (4 dígitos; más si hace
--     falta). Gemela JS: formatearNumeroPedido() (frontend, commit aparte).
--
-- No toca tablas flota_*. La vista plantas_v_bascula_viva no se modifica.
--
-- Reversión:
--   drop function plantas_etiqueta_pedido(integer);
--   alter table plantas_pedidos drop column numero;  -- arrastra la secuencia
-- ============================================================================

create sequence plantas_pedidos_numero_seq as integer;

-- El primer ALTER toma el lock exclusivo de la tabla hasta el final de la
-- transacción: no puede entrar un pedido nuevo entre la numeración y el DEFAULT.
alter table plantas_pedidos add column numero integer;

with orden as (
  select id, row_number() over (order by created_at, id) as n
    from plantas_pedidos
)
update plantas_pedidos p
   set numero = orden.n
  from orden
 where orden.id = p.id;

-- Deja la secuencia en el último número usado (si la tabla estuviera vacía,
-- el próximo sería el 1).
select setval(
  'plantas_pedidos_numero_seq',
  coalesce((select max(numero) from plantas_pedidos), 1),
  (select count(*) > 0 from plantas_pedidos)
);

alter table plantas_pedidos
  alter column numero set default nextval('plantas_pedidos_numero_seq'),
  alter column numero set not null,
  add constraint plantas_pedidos_numero_key unique (numero);

alter sequence plantas_pedidos_numero_seq owned by plantas_pedidos.numero;

comment on column plantas_pedidos.numero is
  'Número correlativo del pedido (se muestra como P-0001). Único, no se reutiliza.';

-- Nadie pide números desde afuera: solo el DEFAULT, dentro de las funciones
-- SECURITY DEFINER que insertan pedidos (plantas_pedidos no tiene policy de
-- INSERT para los usuarios).
revoke all on sequence plantas_pedidos_numero_seq from public, anon, authenticated;

create function plantas_etiqueta_pedido(p_numero integer)
returns text
language sql
immutable
set search_path to 'public'
as $fn$
  select 'P-' || lpad(p_numero::text, greatest(4, length(p_numero::text)), '0')
$fn$;

revoke execute on function plantas_etiqueta_pedido(integer) from public, anon;
grant execute on function plantas_etiqueta_pedido(integer) to authenticated;

-- Control final.
do $chk$
declare
  v_total int; v_max int; v_dist int; v_seq bigint;
begin
  select count(*), max(numero), count(distinct numero) into v_total, v_max, v_dist from plantas_pedidos;
  select last_value into v_seq from plantas_pedidos_numero_seq;
  if v_total > 0 and (v_max <> v_total or v_dist <> v_total or v_seq <> v_total) then
    raise exception 'MIG52: numeración inconsistente (total %, max %, distintos %, secuencia %)',
      v_total, v_max, v_dist, v_seq;
  end if;
  if exists (
    select 1 from plantas_pedidos a join plantas_pedidos b
      on a.numero < b.numero and a.created_at > b.created_at
  ) then
    raise exception 'MIG52: la numeración no respeta el orden de creación';
  end if;
end;
$chk$;

$mig52$;

  -- 1) numeración densa 1..N, sin nulos ni repetidos
  select count(*), count(distinct numero), min(numero), max(numero) into v_n, v_a, v_b, v_estado from plantas_pedidos;
  if v_n <> v_total or v_a <> v_total or v_b <> 1 or v_estado::int <> v_total then
    raise exception 'FALLA 1: total % distintos % min % max % (esperado %)', v_n, v_a, v_b, v_estado, v_total;
  end if;
  v_ok := v_ok || '1 ' || v_total || ' pedidos numerados 1..' || v_total || ' sin huecos ni repetidos; ';

  -- 2) el más viejo es el 1 y el más nuevo el N
  select numero, to_char(created_at at time zone 'America/Argentina/Buenos_Aires', 'DD/MM/YYYY') into v_a, v_txt
    from plantas_pedidos order by created_at, id limit 1;
  select numero into v_b from plantas_pedidos order by created_at desc, id desc limit 1;
  if v_a <> 1 or v_b <> v_total then raise exception 'FALLA 2: primero % ultimo %', v_a, v_b; end if;
  v_ok := v_ok || '2 ' || plantas_etiqueta_pedido(1) || ' = pedido creado el ' || v_txt || ', el mas nuevo = ' || plantas_etiqueta_pedido(v_total) || '; ';

  -- 3) crear_pedido como admin logueado: toma N+1 y N+2
  perform set_config('request.jwt.claims', json_build_object('email', v_admin, 'sub', v_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select numero into v_a from crear_pedido(v_formula, 1, current_date, v_obra);
  select numero into v_b from crear_pedido(v_formula, 1, current_date, v_obra);
  execute 'reset role';
  if v_a <> v_total + 1 or v_b <> v_total + 2 then raise exception 'FALLA 3: crear_pedido dio % y %', v_a, v_b; end if;
  v_ok := v_ok || '3 crear_pedido (admin logueado) asigna ' || plantas_etiqueta_pedido(v_a) || ' y ' || plantas_etiqueta_pedido(v_b) || '; ';

  -- 4) insert sin numero (mecanismo del residual de finalizar_despacho)
  insert into plantas_pedidos (obra_id, formula_id, tipo, cantidad_solicitada, fecha_programada, estado)
  values (v_obra, v_formula, 'asfalto', 1, current_date, 'confirmado')
  returning numero into v_a;
  if v_a <> v_total + 3 then raise exception 'FALLA 4: insert sin numero dio %', v_a; end if;
  v_ok := v_ok || '4 insert sin numero (residual) toma ' || plantas_etiqueta_pedido(v_a) || '; ';

  -- 5) número repetido rechazado
  v_estado := 'sin error';
  begin
    insert into plantas_pedidos (numero, obra_id, formula_id, tipo, cantidad_solicitada, fecha_programada)
    values (1, v_obra, v_formula, 'asfalto', 1, current_date);
  exception when others then v_estado := sqlstate;
  end;
  if v_estado <> '23505' then raise exception 'FALLA 5: numero repetido dio %', v_estado; end if;
  v_ok := v_ok || '5 numero repetido rechazado (23505); ';

  -- 6) formato
  if plantas_etiqueta_pedido(1) <> 'P-0001' or plantas_etiqueta_pedido(230) <> 'P-0230'
     or plantas_etiqueta_pedido(12345) <> 'P-12345' then
    raise exception 'FALLA 6: formato';
  end if;
  v_ok := v_ok || '6 formato P-0001 / P-0230 / P-12345; ';

  -- 7) lectura: admin logueado ve el numero; anon 0 filas sin error
  execute 'set local role authenticated';
  select count(*) into v_a from plantas_pedidos where numero = 1;
  v_estado := 'sin error';
  begin
    perform nextval('plantas_pedidos_numero_seq');
  exception when others then v_estado := sqlstate;
  end;
  execute 'reset role';
  if v_a <> 1 then raise exception 'FALLA 7: admin no lee el pedido 1 (%)', v_a; end if;
  if v_estado <> '42501' then raise exception 'FALLA 7: authenticated pudo pedir un numero (%)', v_estado; end if;
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role anon';
  select count(*) into v_b from plantas_pedidos;
  execute 'reset role';
  v_ok := v_ok || '7 admin lee por numero; un usuario no puede pedir numeros a mano (42501); anon lee ' || v_b || ' filas sin error';

  raise exception 'DRYRUN 52 OK — %', v_ok;
end;
$dry$;
