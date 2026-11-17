-- ============================================================================
-- Ensayo de la migración 76. Correr DESPUÉS de 76_informe_dia3_marca_plantas_minimos.sql,
-- en la misma transacción. Antes de la migración, en la misma transacción:
--   select set_config('ensayo76.base', coalesce((select max(id) from core_notificaciones), 0)::text, true);
-- Termina SIEMPRE con ERROR "DRYRUN 76 OK — …" (todo revertido).
-- ============================================================================
do $dry$
declare
  v_ok    text[] := '{}';
  v_base  bigint := current_setting('ensayo76.base')::bigint;
  v_datos jsonb;
  v_n     int;
  r       record;
begin
  -- A. Cron
  if (select schedule from cron.job where jobname = 'informe-produccion-vialtec') <> '0 11 3 * *'
     or (select command from cron.job where jobname = 'informe-produccion-vialtec') not like '%core_secreto_llamada()%' then
    raise exception 'A: cron';
  end if;
  v_ok := v_ok || 'A cron 0 11 3 * * (08:00 AR) con Vault'::text;

  -- B. Mínimos cargados y nada más
  if (select count(*) from plantas_materiales where stock_minimo_kg is not null) <> 3
     or (select stock_minimo_kg from plantas_materiales where nombre = 'CEMENTO') <> 50000
     or (select stock_minimo_kg from plantas_materiales where nombre = 'ASFALTO CA30') <> 25000
     or (select stock_minimo_kg from plantas_materiales where nombre = 'ADITIVO') <> 1000 then
    raise exception 'B: mínimos';
  end if;
  for r in select material, plantas_numero_ar(stock_kg / 1000) s, plantas_numero_ar(consumo_semana_kg / 1000) c, estado_actual, coalesce(estado_proyectado, '-') p
             from plantas_stock_estados() where minimo_kg is not null order by 1 loop
    v_ok := v_ok || format('B %s: stock %s tn, semana %s tn → actual %s, proyectado %s', r.material, r.s, r.c, r.estado_actual, r.p);
  end loop;

  -- C. Mails al cargar los mínimos (los reales que saldrían al aplicar)
  select count(*) into v_n from core_notificaciones where id > v_base and evento = 'plantas_stock_critico';
  v_ok := v_ok || format('C al aplicar: %s mails de stock crítico%s', v_n,
    coalesce(' (' || (select string_agg(distinct asunto, '; ') from core_notificaciones where id > v_base and evento = 'plantas_stock_critico') || ')', ''));

  -- D. Marca de Plantas: forzar un crítico de prueba en ADITIVO
  update plantas_materiales set stock_minimo_kg = 1000000 where nombre = 'ADITIVO';
  select datos into v_datos from core_notificaciones where id > v_base and evento = 'plantas_stock_critico' order by id desc limit 1;
  if v_datos ->> 'sistema' <> 'plantas' or v_datos ->> 'tono' <> 'critico' or v_datos ->> 'etiqueta' <> 'Stock crítico'
     or v_datos ->> 'titulo' <> 'ADITIVO en stock crítico' then
    raise exception 'D: contenido %', v_datos;
  end if;
  v_ok := v_ok || 'D aviso con sistema plantas, tono crítico, etiqueta "Stock crítico"'::text;

  -- E. Permisos de la función recreada
  if has_function_privilege('authenticated', 'plantas_avisos_stock_revisar()', 'execute')
     or has_function_privilege('anon', 'plantas_avisos_stock_revisar()', 'execute') then
    raise exception 'E: permisos';
  end if;
  v_ok := v_ok || 'E revisar sin acceso desde la app'::text;

  raise exception 'DRYRUN 76 OK — %', array_to_string(v_ok, ' || ');
end;
$dry$;
