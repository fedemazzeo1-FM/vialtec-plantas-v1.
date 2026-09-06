-- Migración 24: postergar_pedido() era la única RPC de transición de
-- estado de Pedidos sin ningún chequeo de rol (hallazgo de la auditoría de
-- RLS fina, migración 23, memory/pending.md 2026-09-06). Decisión de
-- Federico: restringir a admin/plantista, mismo criterio que
-- confirmar_pedido()/archivar_pedido().

create or replace function public.postergar_pedido(p_pedido_id uuid, p_fecha_nueva date default null::date, p_motivo text default null::text)
returns plantas_pedidos
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_rol            text;
  v_pedido         plantas_pedidos;
  v_fecha_anterior date;
begin
  v_rol := plantas_rol_actual();
  if v_rol is null or v_rol not in ('admin', 'plantista') then
    raise exception 'Tu rol (%) no puede postergar pedidos.', coalesce(v_rol, 'sin rol asignado');
  end if;

  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'El pedido % no existe.', p_pedido_id;
  end if;
  if v_pedido.estado not in ('solicitado', 'confirmado', 'postergado') then
    raise exception 'Solo se puede postergar un pedido solicitado, confirmado o ya postergado (estado actual: %).', v_pedido.estado;
  end if;

  v_fecha_anterior := v_pedido.fecha_programada;

  update plantas_pedidos
    set estado = 'postergado',
        fecha_programada = coalesce(p_fecha_nueva, fecha_programada),
        motivo = p_motivo,
        motivo_en = case when p_motivo is not null then now() else motivo_en end
    where id = p_pedido_id
    returning * into v_pedido;

  insert into plantas_pedidos_historial (
    pedido_id, estado, fecha_evento, fecha_programada_anterior, fecha_programada_nueva, usuario_id, motivo
  ) values (
    p_pedido_id, 'postergado', now(), v_fecha_anterior, p_fecha_nueva, auth.uid(), p_motivo
  );

  return v_pedido;
end;
$function$;
