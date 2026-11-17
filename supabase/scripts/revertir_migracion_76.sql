-- ============================================================================
-- Vuelta atrás de la migración 76: cron al día 1, aviso de stock como en la 75
-- (sin sistema) y mínimos de CEMENTO, ASFALTO CA30 y ADITIVO vacíos.
-- ============================================================================
begin;
set local lock_timeout = '5s';
select cron.alter_job((select jobid from cron.job where jobname = 'informe-produccion-vialtec'), schedule := '0 11 1 * *');
update public.plantas_materiales set stock_minimo_kg = null
 where nombre in ('CEMENTO', 'ASFALTO CA30', 'ADITIVO')
   and stock_minimo_kg in (50000, 25000, 1000);
create or replace function public.plantas_avisos_stock_revisar()
 returns int language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_filas jsonb := '[]'::jsonb;
  v_nombres text[] := '{}';
  v_actual int := 0;
  r record;
begin
  perform pg_advisory_xact_lock(hashtext('plantas_avisos_stock'));
  for r in
    select e.*, a.critico as antes,
           case when e.estado_actual = 'rojo' then 'actual' when e.estado_proyectado = 'rojo' then 'proyectado' end as ahora
      from plantas_stock_estados() e
      left join plantas_avisos_stock_estado a on a.material_id = e.material_id
     order by e.material
  loop
    if r.ahora is distinct from r.antes then
      insert into plantas_avisos_stock_estado (material_id, critico, cambiado_at) values (r.material_id, r.ahora, now())
      on conflict (material_id) do update set critico = excluded.critico, cambiado_at = excluded.cambiado_at;
      -- Avisa al entrar en crítico o cuando pasa de proyectado a actual; salir (o bajar de actual a proyectado) no.
      if r.ahora is not null and (r.antes is null or (r.antes = 'proyectado' and r.ahora = 'actual')) then
        v_nombres := v_nombres || r.material;
        if r.ahora = 'actual' then v_actual := v_actual + 1; end if;
        v_filas := v_filas || jsonb_build_array(jsonb_build_array(
          r.material,
          plantas_numero_ar(r.stock_kg / 1000) || ' tn',
          case when r.consumo_semana_kg > 0 then plantas_numero_ar(r.consumo_semana_kg / 1000) || ' tn' else '—' end,
          plantas_numero_ar((r.stock_kg - r.consumo_semana_kg) / 1000) || ' tn',
          plantas_numero_ar(r.minimo_kg / 1000) || ' tn',
          case r.ahora when 'actual' then 'Stock actual' else 'Pedidos de la semana' end));
      end if;
    end if;
  end loop;

  if cardinality(v_nombres) = 0 then return 0; end if;

  return core_notificar(
    'plantas_stock_critico',
    case when cardinality(v_nombres) = 1 then 'Stock crítico en Plantas: ' || v_nombres[1]
         else 'Stock crítico en Plantas: ' || cardinality(v_nombres) || ' materiales' end,
    null,
    jsonb_build_object(
      'tono', 'critico',
      'etiqueta', 'Plantas · Stock crítico',
      'titulo', case when cardinality(v_nombres) = 1 then v_nombres[1] || ' en stock crítico'
                     else cardinality(v_nombres) || ' materiales en stock crítico' end,
      'mensaje', case when v_actual > 0
                      then 'El stock quedó en cero o debajo del mínimo. Revisá los ingresos previstos antes de despachar.'
                      else 'Con los pedidos confirmados de esta semana, el stock quedaría debajo del mínimo. Revisá los ingresos previstos.' end,
      'preencabezado', array_to_string(v_nombres, ', ') || ' en crítico',
      'secciones', jsonb_build_array(jsonb_build_object(
        'titulo', 'Materiales en crítico',
        'columnas', jsonb_build_array(
          jsonb_build_object('texto', 'Material'),
          jsonb_build_object('texto', 'Stock', 'derecha', true),
          jsonb_build_object('texto', 'Pedidos semana', 'derecha', true),
          jsonb_build_object('texto', 'Queda', 'derecha', true),
          jsonb_build_object('texto', 'Mínimo', 'derecha', true),
          jsonb_build_object('texto', 'Por')),
        'filas', v_filas)),
      'accion', jsonb_build_object('texto', 'Ver stock', 'url', 'https://produccion.vialtec.app/stock'),
      'nota', 'Sale una vez cuando un material entra en crítico (en cero o debajo del mínimo, ahora o con los pedidos confirmados de la semana). Vuelve a avisar solo si sale de crítico y vuelve a entrar. No bloquea pedidos.'),
    'plantas_stock', null, '{}'::jsonb, null,
    'plantas_stock_critico:' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'));
end $f$;
commit;
