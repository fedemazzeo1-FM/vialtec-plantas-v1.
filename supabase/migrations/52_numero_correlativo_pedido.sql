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
