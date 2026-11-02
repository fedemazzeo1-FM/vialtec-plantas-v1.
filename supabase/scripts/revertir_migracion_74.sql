-- ============================================================================
-- Reversión de la migración 74: vuelve al nombre como texto (estado del
-- 02/11/2026). Restaura los textos de pedidos y los 2 nombres del maestro
-- desde plantas_respaldo_mig74, borra las 8 altas de clientes si no se usan
-- en otro lado, y deja plantas_trg_ingresos_normalizar como en la 63
-- (md5 9ec7ae00fea65e98e09beaa9da18c413).
-- OJO: un nombre editado en Maestros DESPUÉS de aplicar la 74 ya quedó
-- copiado en pedidos/ingresos; eso no se deshace (es lo que se pidió).
-- Revertir también el frontend de la 74 (agrupa por cliente_id/proveedor_id).
-- ============================================================================
begin;

drop trigger plantas_clientes_renombrar on plantas_clientes;
drop trigger plantas_proveedores_renombrar on plantas_proveedores;
drop trigger plantas_pedidos_cliente on plantas_pedidos;
drop function plantas_trg_clientes_renombrar();
drop function plantas_trg_proveedores_renombrar();
drop function plantas_trg_pedidos_cliente();

alter table plantas_pedidos drop constraint plantas_pedidos_venta_con_cliente;

-- Textos de pedidos como estaban
update plantas_pedidos p set cliente_externo = r.valor_anterior
  from plantas_respaldo_mig74 r
 where r.tabla = 'plantas_pedidos' and r.columna = 'cliente_externo' and r.id = p.id;

alter table plantas_pedidos drop column cliente_id;

drop trigger plantas_ingresos_normalizar on plantas_ingresos;
alter table plantas_ingresos drop column proveedor_id;

CREATE OR REPLACE FUNCTION public.plantas_trg_ingresos_normalizar()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  v_neto_tn numeric;
begin
  new.proveedor := coalesce(
    (select nombre from plantas_proveedores where lower(btrim(nombre)) = lower(btrim(new.proveedor)) limit 1),
    btrim(new.proveedor)
  );

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

create trigger plantas_ingresos_normalizar
  before insert or update of proveedor, cantidad on plantas_ingresos
  for each row execute function plantas_trg_ingresos_normalizar();

drop index plantas_clientes_nombre_normalizado;
drop index plantas_proveedores_nombre_normalizado;

-- Nombres del maestro como estaban (casos 4 y 5)
update plantas_clientes c set nombre = r.valor_anterior
  from plantas_respaldo_mig74 r
 where r.tabla = 'plantas_clientes' and r.columna = 'nombre' and r.id = c.id;

-- Altas de la 74 (borrado con motivo, queda en auditoría)
select set_config('plantas.motivo_eliminacion', 'Reversión de la migración 74', true);
delete from plantas_clientes where nombre in (
  'G Y C CONSTRUCCIONES S.A', 'HV-VIAL S.A', 'CORRALON FILIBERTI', 'Corralon ramiro antonazzi',
  'INMIX', 'Lucas Maldonado', 'Vialmani', 'COLEGIO MOORLANDS');

drop table plantas_respaldo_mig74;
drop function plantas_normalizar_nombre(text);

-- Debe dar 9ec7ae00fea65e98e09beaa9da18c413
select md5(pg_get_functiondef('public.plantas_trg_ingresos_normalizar()'::regprocedure));

commit;
