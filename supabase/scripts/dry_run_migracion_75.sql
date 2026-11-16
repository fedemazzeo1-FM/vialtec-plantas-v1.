-- ============================================================================
-- Ensayo de la migración 75. Correr DESPUÉS del contenido de
-- supabase/migrations/75_avisos_por_mail_plantas.sql, en la misma transacción.
-- Termina SIEMPRE con ERROR "DRYRUN 75 OK — …" (todo revertido: los mails
-- que se anotan en la bandeja durante el ensayo nunca se ven ni se mandan).
-- Antes de la migración, en la misma transacción, guardar la foto:
--   select set_config('ensayo75.cron', (select command from cron.job where jobname = 'informe-produccion-vialtec'), true);
-- ============================================================================
do $dry$
declare
  v_ok    text[] := '{}';
  v_n     int;
  v_base  bigint := coalesce((select max(id) from core_notificaciones), 0);
  v_mat   record;
  v_mat2  record;
  v_proy  record;
  v_datos jsonb;
  mails   int;
begin
  -- A. Eventos, reglas, cron y respaldo
  if (select count(*) from core_notificacion_eventos where clave in ('informe_plantas_mensual', 'plantas_stock_critico') and app = 'plantas' and activo) <> 2 then
    raise exception 'A: faltan los eventos';
  end if;
  if (select count(*) from core_notificacion_reglas where evento = 'informe_plantas_mensual' and activo) <> 7
     or (select count(*) from core_notificacion_reglas where evento = 'plantas_stock_critico' and activo) <> 4 then
    raise exception 'A: reglas distintas de 7 + 4';
  end if;
  if (select command from cron.job where jobname = 'informe-produccion-vialtec') not like '%core_secreto_llamada()%'
     or (select schedule from cron.job where jobname = 'informe-produccion-vialtec') <> '0 11 1 * *' then
    raise exception 'A: el cron no quedó con el secreto de Vault / día 1 11:00 UTC';
  end if;
  if (select substr(definicion, strpos(definicion, E'\n') + 1) from plantas_avisos_respaldo where objeto = 'cron:informe-produccion-vialtec')
     is distinct from current_setting('ensayo75.cron') then
    raise exception 'A: el respaldo del cron no es el comando anterior';
  end if;
  v_ok := v_ok || 'A eventos 2, reglas 7+4, cron con Vault, respaldo = comando anterior'::text;

  -- B. Punto de partida sin mails
  select count(*) into v_n from plantas_materiales where activo and controla_stock;
  if (select count(*) from plantas_avisos_stock_estado) <> v_n then raise exception 'B: estado inicial incompleto'; end if;
  if exists (select 1 from core_notificaciones where id > v_base) then raise exception 'B: aplicar anotó mails'; end if;
  v_ok := v_ok || format('B %s materiales con estado inicial, 0 mails', v_n);

  -- C. Stock actual a rojo: 4 mails, un solo aviso
  select * into v_mat from plantas_stock_estados() where stock_kg > 0 and consumo_semana_kg = 0 order by stock_kg desc limit 1;
  update plantas_materiales set stock_minimo_kg = v_mat.stock_kg * 2, stock_maximo_kg = null where id = v_mat.material_id;
  select count(*), min(datos::text)::jsonb into mails, v_datos from core_notificaciones where id > v_base and evento = 'plantas_stock_critico';
  if mails <> 4 then raise exception 'C: % mails (esperaba 4)', mails; end if;
  if (select array_agg(destinatario order by destinatario) from core_notificaciones where id > v_base)
     <> array['alejandro.fernandez@vialtec.com.ar', 'daniel.natel@vialtec.com.ar', 'federico.mazzeo@vialtec.com.ar', 'felix.pereyra@vialtec.com.ar'] then
    raise exception 'C: destinatarios distintos';
  end if;
  if v_datos ->> 'titulo' <> v_mat.material || ' en stock crítico' or jsonb_array_length(v_datos -> 'secciones' -> 0 -> 'filas') <> 1
     or v_datos -> 'secciones' -> 0 -> 'filas' -> 0 ->> 5 <> 'Stock actual' then
    raise exception 'C: contenido inesperado %', v_datos;
  end if;
  v_ok := v_ok || format('C %s mínimo %s tn → 4 mails "%s" (%s)', v_mat.material, plantas_numero_ar(v_mat.stock_kg * 2 / 1000),
                         v_datos ->> 'titulo', v_datos -> 'secciones' -> 0 -> 'filas' -> 0 ->> 1);

  -- D. Sigue en rojo: no repite (otro cambio del material y un movimiento de stock)
  update plantas_materiales set stock_minimo_kg = v_mat.stock_kg * 3 where id = v_mat.material_id;
  update plantas_stock set cantidad_kg = cantidad_kg where material_id = v_mat.material_id;
  if (select count(*) from core_notificaciones where id > v_base) <> 4 then raise exception 'D: repitió el aviso'; end if;
  v_ok := v_ok || 'D sigue en rojo → sin mail nuevo'::text;

  -- E. Sale de crítico (sin mail) y vuelve a entrar (mail)
  update plantas_materiales set stock_minimo_kg = null where id = v_mat.material_id;
  if (select count(*) from core_notificaciones where id > v_base) <> 4 then raise exception 'E: avisó al salir'; end if;
  if (select critico from plantas_avisos_stock_estado where material_id = v_mat.material_id) is not null then raise exception 'E: no registró la salida'; end if;
  update plantas_materiales set stock_minimo_kg = v_mat.stock_kg * 2 where id = v_mat.material_id;
  if (select count(*) from core_notificaciones where id > v_base) <> 8 then raise exception 'E: no avisó al volver a entrar'; end if;
  update plantas_materiales set stock_minimo_kg = null where id = v_mat.material_id;
  v_ok := v_ok || 'E sale sin mail, vuelve a entrar → 4 mails'::text;

  -- F. Amarillo no manda mail
  select * into v_mat2 from plantas_stock_estados() where stock_kg > 0 and consumo_semana_kg = 0 and material_id <> v_mat.material_id order by stock_kg desc limit 1;
  update plantas_materiales set stock_minimo_kg = v_mat2.stock_kg / 1.1, stock_maximo_kg = null where id = v_mat2.material_id;
  if (select estado_actual from plantas_stock_estados() where material_id = v_mat2.material_id) <> 'amarillo' then raise exception 'F: no quedó amarillo'; end if;
  if (select count(*) from core_notificaciones where id > v_base) <> 8 then raise exception 'F: el amarillo avisó'; end if;
  update plantas_materiales set stock_minimo_kg = null where id = v_mat2.material_id;
  v_ok := v_ok || format('F %s en amarillo → sin mail', v_mat2.material);

  -- G. Proyectado: los pedidos confirmados de la semana lo dejarían en rojo
  select * into v_proy from plantas_stock_estados() where consumo_semana_kg > 0 and stock_kg > consumo_semana_kg order by consumo_semana_kg desc limit 1;
  if found then
    update plantas_materiales set stock_minimo_kg = v_proy.stock_kg - v_proy.consumo_semana_kg / 2, stock_maximo_kg = null where id = v_proy.material_id;
    select datos into v_datos from core_notificaciones where id > v_base order by id desc limit 1;
    if (select count(*) from core_notificaciones where id > v_base) <> 12
       or v_datos -> 'secciones' -> 0 -> 'filas' -> 0 ->> 5 <> 'Pedidos de la semana' then
      raise exception 'G: proyectado no avisó bien %', v_datos;
    end if;
    -- y si después se termina de verdad, avisa otra vez (proyectado → actual)
    update plantas_materiales set stock_minimo_kg = v_proy.stock_kg * 2 where id = v_proy.material_id;
    if (select count(*) from core_notificaciones where id > v_base) <> 16 then raise exception 'G: proyectado → actual no avisó'; end if;
    update plantas_materiales set stock_minimo_kg = null where id = v_proy.material_id;
    v_ok := v_ok || format('G %s: semana %s tn sobre %s tn → 4 mails "Pedidos de la semana"; pasa a actual → 4 más',
                           v_proy.material, plantas_numero_ar(v_proy.consumo_semana_kg / 1000), plantas_numero_ar(v_proy.stock_kg / 1000));
  else
    v_ok := v_ok || 'G SIN PROBAR: no hay pedidos confirmados esta semana con consumo'::text;
  end if;

  -- H. Permisos
  if has_function_privilege('anon', 'plantas_stock_estados(date)', 'execute')
     or has_function_privilege('authenticated', 'plantas_avisos_stock_revisar()', 'execute')
     or has_table_privilege('authenticated', 'plantas_avisos_stock_estado', 'select')
     or has_table_privilege('authenticated', 'plantas_avisos_respaldo', 'select') then
    raise exception 'H: permisos de más';
  end if;
  v_ok := v_ok || 'H anon/authenticated sin acceso a revisar, estado y respaldo'::text;

  -- I. Si la evaluación falla, la operación sigue (último: rompe la función a propósito)
  execute $x$create or replace function public.plantas_avisos_stock_revisar() returns int language plpgsql as $b$ begin raise exception 'falla de prueba'; end $b$$x$;
  update plantas_stock set cantidad_kg = cantidad_kg where material_id = v_mat.material_id;
  v_ok := v_ok || 'I con la evaluación rota, el movimiento de stock pasa (warning)'::text;

  raise exception 'DRYRUN 75 OK — %', array_to_string(v_ok, ' || ');
end;
$dry$;
