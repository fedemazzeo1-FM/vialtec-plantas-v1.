-- ============================================================================
-- Dry-run de la migración 66 contra producción. Termina SIEMPRE con raise
-- exception: no persiste nada. Las secuencias no vuelven atrás con el
-- rollback: se bloquean las tablas que las usan y se devuelven al final
-- (también si falla). Generado: cabecera + migración 66 + pruebas
-- (dry_run_migracion_66_pruebas.sql).
-- ============================================================================
do $dry$
declare
  v_plantista text; v_balancero text; v_fa uuid; v_obra bigint;
  v_n int; v_m int; v_txt text; v_txt2 text; v_ok text := ''; v_j jsonb; v_aud bigint; v_v plantas_vales;
  v_a uuid; v_b uuid; v_c uuid; v_d uuid; v_e uuid; v_f uuid; v_g uuid; v_h uuid; v_i uuid;
  v_p1 uuid; v_p2 uuid; v_p263 jsonb; v_filas_vista int; v_err text;
  s1 bigint; c1 boolean; s2 bigint; c2 boolean; s3 bigint; c3 boolean; s4 bigint; c4 boolean; s5 bigint; c5 boolean;
begin
  lock table plantas_pedidos, plantas_vales, plantas_remitos_manuales, plantas_auditoria in share row exclusive mode;
  select last_value, is_called into s1, c1 from plantas_vales_numero_vale_seq;
  select last_value, is_called into s2, c2 from plantas_vales_numero_arido_seq;
  select last_value, is_called into s3, c3 from plantas_remitos_numero_seq;
  select last_value, is_called into s4, c4 from plantas_pedidos_numero_seq;
  select last_value, is_called into s5, c5 from plantas_auditoria_id_seq;
  select count(*) into v_filas_vista from plantas_v_bascula_viva;
  select to_jsonb(p) into v_p263 from plantas_pedidos p where numero = 263;
  create temp table dry66_antes on commit drop as select id, acumulado_obra_tn as guardado from plantas_vales;

  begin
  execute $m66$
-- ============================================================================
-- Migración 66: el acumulado guardado se recalcula al corregir, anular o
-- reasignar un vale de asfalto
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido de Federico (2026-10-20). El vale 10276 (P-0263) se corrigió de
-- 37,63 a 35,4 tn (y después a 35,65) y su acumulado_obra_tn siguió en
-- 37,63: corregir_vale_bascula cambiaba el peso pero no el acumulado
-- guardado. Lo mismo pasa con los vales siguientes del mismo pedido, y con
-- anular o reasignar un vale.
--
--   1. plantas_recalcular_acumulados_asfalto(pedido, obra, desde): vuelve a
--      calcular el acumulado guardado de los vales de asfalto del grupo
--      (mismo pedido; sin pedido, misma obra y día de Argentina) desde esa
--      fecha en adelante, con el mismo helper que la pesada, la vista y la
--      impresión (plantas_acumulado_asfalto, migración 65). No toca vales
--      anulados (conservan su foto) ni vales migrados del legado (no tienen
--      acumulado guardado).
--   2. Lo llaman corregir_vale_bascula (el vale corregido y los siguientes),
--      anular_vale_bascula (los siguientes), reasignar_vale_bascula (el
--      pedido de origen y el de destino) y registrar_pesada_bascula (una
--      pesada con fecha anterior a otras del mismo pedido). En corregir y
--      reasignar el recálculo va antes de auditar: la auditoría del vale
--      muestra también el cambio de su acumulado.
--   3. Datos: se corrigen los 18 vales que ya quedaron mal y que están mal
--      con cualquier regla (sumaban un vale anulado o el peso previo a una
--      corrección). Cada uno se verifica contra su valor actual antes de
--      cambiarlo; si alguno cambió, la migración no se aplica.
--        - Corregidos: 10213 (P-0227) y 10276 (P-0263).
--        - Con un vale anulado antes: P-0213 (10138-10140, 10142, 10143) y
--          P-0216 (10151-10159, 10162, 10164).
--      No se tocan los 10 vales nocturnos/de otro día guardados con la regla
--      vieja de corte diario (P-0212: 10144-10145; P-0233: 10240-10247): son
--      la foto que salió impresa en su momento (migración 65: "los vales
--      viejos conservan su acumulado_obra_tn guardado").
--
-- No cambia pedidos (P-0263 sigue abierto), ni la vista, ni lo impreso (la
-- impresión ya recalcula), ni las firmas de las funciones.
--
-- Reversión: supabase/scripts/revertir_migracion_66.sql
-- ============================================================================

-- 1) Recálculo del acumulado guardado
create function public.plantas_recalcular_acumulados_asfalto(p_pedido_id uuid, p_obra_id bigint, p_desde timestamptz)
returns integer
language plpgsql
set search_path to 'public'
as $function$
declare
  v_n integer;
begin
  if p_desde is null then
    return 0;
  end if;

  with objetivo as (
    select v.id, (plantas_acumulado_asfalto(v.pedido_id, v.obra_id, v.fecha_pesada) ->> 'tn')::numeric as acumulado
    from plantas_vales v
    where v.tipo_vale = 'asfalto'
      and not v.anulado
      and v.acumulado_obra_tn is not null
      and v.fecha_pesada >= p_desde
      and case
        when p_pedido_id is not null then v.pedido_id = p_pedido_id
        else v.pedido_id is null
          and v.obra_id is not distinct from p_obra_id
          and (v.fecha_pesada at time zone 'America/Argentina/Buenos_Aires')::date
              = (p_desde at time zone 'America/Argentina/Buenos_Aires')::date
      end
  )
  update plantas_vales v
    set acumulado_obra_tn = o.acumulado
    from objetivo o
    where v.id = o.id
      and v.acumulado_obra_tn is distinct from o.acumulado;

  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

revoke all on function public.plantas_recalcular_acumulados_asfalto(uuid, bigint, timestamptz) from public, anon, authenticated;

-- 2) Llamadas desde las funciones de Báscula (parches sobre la versión de
--    producción, con control de que sea exactamente la esperada)
do $parches$
declare
  v_src text;
  v_ancla text;
  v_extra text;
begin
  -- corregir_vale_bascula
  v_src := pg_get_functiondef('public.corregir_vale_bascula(uuid,numeric,numeric,text,text,text,numeric,text,text,numeric,bigint,text,text)'::regprocedure);
  if md5(v_src) <> '797ed596c289029530cc3d74deb9f605' then
    raise exception 'M66: corregir_vale_bascula no es la versión esperada (md5 %)', md5(v_src);
  end if;
  v_ancla := $a$  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, antes, despues, usuario_email, motivo)$a$;
  v_extra := $b$  -- Migración 66: el acumulado guardado de este vale y de los siguientes
  -- del mismo pedido se recalcula con el peso corregido.
  if v_vale.tipo_vale = 'asfalto' then
    perform plantas_recalcular_acumulados_asfalto(v_vale.pedido_id, v_vale.obra_id, v_vale.fecha_pesada);
    select * into v_vale from plantas_vales where id = p_vale_id;
  end if;

$b$;
  if (length(v_src) - length(replace(v_src, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'M66: ancla de corregir_vale_bascula no encontrada una sola vez';
  end if;
  execute replace(v_src, v_ancla, v_extra || v_ancla);

  -- anular_vale_bascula
  v_src := pg_get_functiondef('public.anular_vale_bascula(uuid,text)'::regprocedure);
  if md5(v_src) <> '5d321660fcb55d6078fb9afda21e7c7c' then
    raise exception 'M66: anular_vale_bascula no es la versión esperada (md5 %)', md5(v_src);
  end if;
  v_ancla := $a$  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, motivo, usuario_email)$a$;
  v_extra := $b$  -- Migración 66: los vales siguientes del mismo pedido dejan de sumar el anulado.
  if v_vale.tipo_vale = 'asfalto' then
    perform plantas_recalcular_acumulados_asfalto(v_vale.pedido_id, v_vale.obra_id, v_vale.fecha_pesada);
  end if;

$b$;
  if (length(v_src) - length(replace(v_src, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'M66: ancla de anular_vale_bascula no encontrada una sola vez';
  end if;
  execute replace(v_src, v_ancla, v_extra || v_ancla);

  -- reasignar_vale_bascula
  v_src := pg_get_functiondef('public.reasignar_vale_bascula(uuid,uuid,text)'::regprocedure);
  if md5(v_src) <> 'cf27eb059bfa765bd729cf8352c93f34' then
    raise exception 'M66: reasignar_vale_bascula no es la versión esperada (md5 %)', md5(v_src);
  end if;
  v_ancla := $a$  update plantas_pedidos
    set nro_remito_global = coalesce(nro_remito_global, nextval('plantas_remitos_numero_seq')::text)
    where id = v_destino.id;$a$;
  v_extra := $b$  -- Migración 66: recalcula el pedido de origen (sin este vale) y el de
  -- destino (con este vale) desde la fecha de la pesada. La obra de origen
  -- sale de la foto previa (el update de arriba ya la reemplazó).
  perform plantas_recalcular_acumulados_asfalto(v_origen.id, (v_aud_antes ->> 'obra_id')::bigint, v_vale.fecha_pesada);
  perform plantas_recalcular_acumulados_asfalto(v_destino.id, v_destino.obra_id, v_vale.fecha_pesada);
  select * into v_vale from plantas_vales where id = p_vale_id;

$b$;
  if (length(v_src) - length(replace(v_src, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'M66: ancla de reasignar_vale_bascula no encontrada una sola vez';
  end if;
  execute replace(v_src, v_ancla, v_extra || v_ancla);

  -- registrar_pesada_bascula
  v_src := pg_get_functiondef('public.registrar_pesada_bascula(text,numeric,numeric,uuid,bigint,text,text,text,text,timestamptz,text,text,text,numeric,numeric)'::regprocedure);
  if md5(v_src) <> '6b69d3f3499968c8f0d680cd08697e38' then
    raise exception 'M66: registrar_pesada_bascula no es la versión esperada (md5 %)', md5(v_src);
  end if;
  v_ancla := $a$  perform plantas_auditar_vale('CREAR', v_vale.id);$a$;
  v_extra := $b$  -- Migración 66: una pesada con fecha anterior a otras del mismo pedido
  -- corrige el acumulado guardado de las siguientes (en el caso normal no
  -- hay siguientes y no cambia nada).
  if p_tipo_vale = 'asfalto' then
    perform plantas_recalcular_acumulados_asfalto(v_vale.pedido_id, v_vale.obra_id, v_vale.fecha_pesada);
  end if;

$b$;
  if (length(v_src) - length(replace(v_src, v_ancla, ''))) / length(v_ancla) <> 1 then
    raise exception 'M66: ancla de registrar_pesada_bascula no encontrada una sola vez';
  end if;
  execute replace(v_src, v_ancla, v_extra || v_ancla);
end;
$parches$;

-- 3) Datos: los 18 vales que ya quedaron mal
do $datos$
declare
  r record;
  v_actual numeric;
  v_nuevo numeric;
  v_n integer := 0;
begin
  for r in
    select * from (values
      (10213, 76.74), (10276, 37.63),
      (10138, 429.08), (10139, 456.42), (10140, 491.24), (10142, 543.20), (10143, 571.90),
      (10151, 183.31), (10152, 221.59), (10153, 252.95), (10154, 288.45), (10155, 325.05),
      (10156, 363.08), (10157, 397.72), (10158, 434.96), (10159, 470.98), (10162, 580.46),
      (10164, 648.46)
    ) as t(numero_vale, guardado)
  loop
    select v.acumulado_obra_tn, (plantas_acumulado_asfalto(v.pedido_id, v.obra_id, v.fecha_pesada) ->> 'tn')::numeric
      into v_actual, v_nuevo
      from plantas_vales v
      where v.numero_vale = r.numero_vale and v.tipo_vale = 'asfalto' and not v.anulado
      for update;
    if not found then
      raise exception 'M66: el vale % no existe o está anulado', r.numero_vale;
    end if;
    if v_actual is distinct from r.guardado then
      raise exception 'M66: el vale % tiene guardado % (se esperaba %) — revisar antes de aplicar', r.numero_vale, v_actual, r.guardado;
    end if;
    update plantas_vales set acumulado_obra_tn = v_nuevo where numero_vale = r.numero_vale and tipo_vale = 'asfalto';
    v_n := v_n + 1;
  end loop;
  if v_n <> 18 then
    raise exception 'M66: se corrigieron % vales (se esperaban 18)', v_n;
  end if;
end;
$datos$;
$m66$;

  -- ==========================================================================
  -- Pruebas (se arma en dry_run_migracion_66.sql junto con la migración)
  -- ==========================================================================
  execute $h$
create function dry66_como(p_email text) returns void language plpgsql as $f$
begin
  perform set_config('request.jwt.claims', json_build_object(
    'email', p_email, 'role', 'authenticated',
    'sub', (select id from auth.users where lower(email) = lower(p_email)))::text, true);
end;
$f$;
create function dry66_acum(p_numeros uuid[]) returns text language sql as $f$
  select string_agg(coalesce(trim_scale(v.acumulado_obra_tn)::text, 'null'), ' ' order by u.ord)
  from unnest(p_numeros) with ordinality u(id, ord) join plantas_vales v on v.id = u.id
$f$;
  $h$;

  select email into v_plantista from plantas_usuarios_roles where rol = 'plantista' and activo order by email limit 1;
  select email into v_balancero from plantas_usuarios_roles where rol = 'balancero' and activo order by email limit 1;
  select id into v_fa from plantas_formulas where activo and tipo = 'asfalto' order by nombre limit 1;
  select id into v_obra from flota_obras order by id limit 1;

  -- ===== GENERAL =====
  select count(*) into v_n from plantas_v_bascula_viva;
  if v_n <> v_filas_vista then raise exception 'DRY FALLA: la vista cambió de % a % filas', v_filas_vista, v_n; end if;
  if has_function_privilege('anon', 'plantas_recalcular_acumulados_asfalto(uuid,bigint,timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'plantas_recalcular_acumulados_asfalto(uuid,bigint,timestamptz)', 'execute')
     or not has_function_privilege('authenticated', 'corregir_vale_bascula(uuid,numeric,numeric,text,text,text,numeric,text,text,numeric,bigint,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'anular_vale_bascula(uuid,text)', 'execute')
     or not has_function_privilege('authenticated', 'reasignar_vale_bascula(uuid,uuid,text)', 'execute')
     or not has_function_privilege('authenticated', 'registrar_pesada_bascula(text,numeric,numeric,uuid,bigint,text,text,text,text,timestamptz,text,text,text,numeric,numeric)', 'execute')
     or has_function_privilege('anon', 'corregir_vale_bascula(uuid,numeric,numeric,text,text,text,numeric,text,text,numeric,bigint,text,text)', 'execute') then
    raise exception 'DRY FALLA: permisos de las funciones';
  end if;
  if to_jsonb((select p from plantas_pedidos p where numero = 263)) is distinct from v_p263 then
    raise exception 'DRY FALLA: P-0263 cambió';
  end if;
  v_ok := 'GENERAL: vista ' || v_n || ' filas (igual); permisos ok (el recálculo es interno, sin EXECUTE para anon/authenticated); P-0263 sin cambios (sigue confirmado y con el pesaje abierto)';

  -- ===== DATOS: los 18 vales corregidos =====
  select string_agg(v.numero_vale || ' ' || trim_scale(a.guardado) || '→' || trim_scale(v.acumulado_obra_tn), ', ' order by v.fecha_pesada)
    into v_txt
    from plantas_vales v join dry66_antes a on a.id = v.id
    where v.acumulado_obra_tn is distinct from a.guardado;
  select count(*) into v_n from plantas_vales v join dry66_antes a on a.id = v.id where v.acumulado_obra_tn is distinct from a.guardado;
  if v_n <> 18 then raise exception 'DRY FALLA: cambiaron % vales (se esperaban 18): %', v_n, v_txt; end if;
  v_ok := v_ok || ' || DATOS: 18 vales corregidos: ' || v_txt;

  -- Lo que queda distinto del helper: solo los 10 de la regla vieja (no se tocan) y los anulados
  select string_agg(numero_vale::text, ' ' order by numero_vale) into v_txt
    from plantas_vales v
    where v.tipo_vale = 'asfalto' and not v.anulado and v.acumulado_obra_tn is not null
      and v.acumulado_obra_tn is distinct from (plantas_acumulado_asfalto(v.pedido_id, v.obra_id, v.fecha_pesada) ->> 'tn')::numeric;
  if v_txt is distinct from '10144 10145 10240 10241 10242 10243 10244 10245 10246 10247' then
    raise exception 'DRY FALLA: quedan distintos: %', v_txt;
  end if;
  select count(*) into v_n from plantas_vales v join dry66_antes a on a.id = v.id
    where v.anulado and v.acumulado_obra_tn is distinct from a.guardado;
  select count(*) into v_m from plantas_vales v join dry66_antes a on a.id = v.id
    where v.datos_legados is not null and v.acumulado_obra_tn is not null;
  if v_n <> 0 or v_m <> 0 then raise exception 'DRY FALLA: se tocaron anulados (%) o legado (%)', v_n, v_m; end if;
  v_ok := v_ok || ' | quedan con la regla vieja, sin tocar: ' || v_txt || '; anulados y legado sin cambios';

  -- Pedidos de prueba (confirmados)
  insert into plantas_pedidos (formula_id, tipo, cantidad_solicitada, fecha_programada, estado, obra_id)
    values (v_fa, 'asfalto', 100, '2026-10-20', 'confirmado', v_obra) returning id into v_p1;
  insert into plantas_pedidos (formula_id, tipo, cantidad_solicitada, fecha_programada, estado, obra_id)
    values (v_fa, 'asfalto', 100, '2026-10-20', 'confirmado', v_obra) returning id into v_p2;

  -- ===== 1. Pesadas normales: 30 + 25 + 20 =====
  perform dry66_como(v_balancero);
  v_a := (registrar_pesada_bascula('asfalto', 40, 10, v_p1, null, 'DRY001', 'Chofer', 'tn', null, '2026-10-20 10:00-03')).id;
  v_b := (registrar_pesada_bascula('asfalto', 35, 10, v_p1, null, 'DRY002', 'Chofer', 'tn', null, '2026-10-20 11:00-03')).id;
  v_c := (registrar_pesada_bascula('asfalto', 30, 10, v_p1, null, 'DRY003', 'Chofer', 'tn', null, '2026-10-20 12:00-03')).id;
  v_txt := dry66_acum(array[v_a, v_b, v_c]);
  if v_txt <> '30 55 75' then raise exception 'DRY FALLA: 1. pesadas %', v_txt; end if;
  v_ok := v_ok || ' || 1. pesadas 30+25+20: guardado ' || v_txt;

  -- ===== 2. Corregir la primera (30 → 25): ella y las siguientes =====
  select max(id) into v_aud from plantas_auditoria;
  v_v := corregir_vale_bascula(v_a, 35, 10, null, null, null, null, null, null, null, null, 'Prueba dry-run: mal tipeo');
  v_txt := dry66_acum(array[v_a, v_b, v_c]);
  if v_txt <> '25 50 70' or v_v.acumulado_obra_tn <> 25 then raise exception 'DRY FALLA: 2. corregir %, devuelve %', v_txt, v_v.acumulado_obra_tn; end if;
  select valores_antes ->> 'acumulado_obra_tn' || '→' || (valores_despues ->> 'acumulado_obra_tn') || ' / neto ' || (valores_antes ->> 'peso_neto') || '→' || (valores_despues ->> 'peso_neto')
    into v_txt2 from plantas_auditoria where id > v_aud and tipo_accion = 'CORREGIR' and entidad_ref = v_v.numero_vale::text;
  if v_txt2 is distinct from '30→25 / neto 30→25' then raise exception 'DRY FALLA: 2. auditoría de la corrección: %', v_txt2; end if;
  select count(*) into v_n from plantas_auditoria where id > v_aud;
  if v_n <> 1 then raise exception 'DRY FALLA: 2. filas de auditoría = % (se esperaba 1, los siguientes no se auditan aparte)', v_n; end if;
  v_ok := v_ok || ' || 2. corregir el 1° (30→25 tn): guardado ' || v_txt || '; auditoría CORREGIR: acumulado ' || v_txt2 || ' (1 sola fila)';

  -- Corregir sin cambiar el peso (solo chofer): no cambia ningún acumulado
  perform corregir_vale_bascula(v_b, 35, 10, null, 'Otro chofer', null, null, null, null, null, null, 'Prueba dry-run: chofer');
  v_txt := dry66_acum(array[v_a, v_b, v_c]);
  if v_txt <> '25 50 70' then raise exception 'DRY FALLA: 2b. corregir chofer %', v_txt; end if;
  v_ok := v_ok || ' | corregir solo el chofer: sin cambios (' || v_txt || ')';

  -- ===== 3. Anular el segundo: el tercero deja de sumarlo, el anulado conserva su foto =====
  perform dry66_como(v_plantista);
  perform anular_vale_bascula(v_b, 'Prueba dry-run: pesada repetida');
  v_txt := dry66_acum(array[v_a, v_b, v_c]);
  if v_txt <> '25 50 45' then raise exception 'DRY FALLA: 3. anular %', v_txt; end if;
  v_ok := v_ok || ' || 3. anular el 2°: guardado ' || v_txt || ' (el anulado conserva 50)';

  -- ===== 4. Reasignar el tercero al pedido 2 (que ya tenía 10 tn antes) =====
  perform dry66_como(v_balancero);
  v_d := (registrar_pesada_bascula('asfalto', 20, 10, v_p2, null, 'DRY004', 'Chofer', 'tn', null, '2026-10-20 09:00-03')).id;
  v_e := (registrar_pesada_bascula('asfalto', 25, 10, v_p2, null, 'DRY005', 'Chofer', 'tn', null, '2026-10-20 13:00-03')).id;
  if dry66_acum(array[v_d, v_e]) <> '10 25' then raise exception 'DRY FALLA: 4. pedido 2 antes %', dry66_acum(array[v_d, v_e]); end if;
  v_v := reasignar_vale_bascula(v_c, v_p2, 'Prueba dry-run: pedido equivocado');
  v_txt := dry66_acum(array[v_a, v_c]);
  v_txt2 := dry66_acum(array[v_d, v_c, v_e]);
  if v_txt <> '25 30' or v_txt2 <> '10 30 45' or v_v.acumulado_obra_tn <> 30 then
    raise exception 'DRY FALLA: 4. reasignar: origen %, destino %', v_txt, v_txt2;
  end if;
  v_ok := v_ok || ' || 4. reasignar el 3° (20 tn) al pedido 2: origen queda 25; destino 10 → 30 (el reasignado) → 45 (el siguiente)';

  -- ===== 5. Pesada con fecha anterior a las otras del pedido 1 =====
  v_f := (registrar_pesada_bascula('asfalto', 18, 10, v_p1, null, 'DRY006', 'Chofer', 'tn', null, '2026-10-20 08:00-03')).id;
  v_txt := dry66_acum(array[v_f, v_a]);
  if v_txt <> '8 33' then raise exception 'DRY FALLA: 5. pesada anterior %', v_txt; end if;
  v_ok := v_ok || ' || 5. pesada de las 08:00 cargada después (8 tn): guardado ' || v_txt || ' (el de las 10:00 pasa de 25 a 33)';

  -- ===== 6. Sin pedido: por obra y día de Argentina =====
  v_g := (registrar_pesada_bascula('asfalto', 30, 10, null, v_obra, 'DRY007', 'Chofer', 'tn', null, '2026-10-24 22:00-03')).id;
  v_h := (registrar_pesada_bascula('asfalto', 25, 10, null, v_obra, 'DRY008', 'Chofer', 'tn', null, '2026-10-24 23:00-03')).id;
  v_i := (registrar_pesada_bascula('asfalto', 22, 10, null, v_obra, 'DRY009', 'Chofer', 'tn', null, '2026-10-25 00:30-03')).id;
  v_v := corregir_vale_bascula(v_g, 26, 10, null, null, null, null, null, null, null, null, 'Prueba dry-run: sin pedido');
  v_txt := dry66_acum(array[v_g, v_h, v_i]);
  if v_txt <> '16 31 12' then raise exception 'DRY FALLA: 6. sin pedido %', v_txt; end if;
  v_ok := v_ok || ' || 6. sin pedido, misma obra: corregir el de las 22:00 (20→16): ' || v_txt || ' (el de las 00:30 es otro día: no cambia)';

  -- ===== 7. La vista y la impresión coinciden con lo guardado =====
  select count(*) into v_n from plantas_v_bascula_viva b join plantas_vales v on v.id = b.id
    where b.pedido_id in (v_p1, v_p2) and not v.anulado and b.acumulado_dia_tn is distinct from v.acumulado_obra_tn;
  v_j := registrar_impresion(v_e, 'remito', 'bascula');
  if v_n <> 0 or (v_j ->> 'acumulado_tn')::numeric <> 45 then
    raise exception 'DRY FALLA: 7. vista distinta en % vales, impresión %', v_n, v_j ->> 'acumulado_tn';
  end if;
  v_ok := v_ok || ' || 7. vista = guardado en los pedidos de prueba; remito del pedido 2: 45 tn';

  exception when others then
    v_err := sqlerrm;
    perform setval('plantas_vales_numero_vale_seq', s1, c1);
    perform setval('plantas_vales_numero_arido_seq', s2, c2);
    perform setval('plantas_remitos_numero_seq', s3, c3);
    perform setval('plantas_pedidos_numero_seq', s4, c4);
    perform setval('plantas_auditoria_id_seq', s5, c5);
    raise exception 'DRYRUN 66 FALLÓ (secuencias restauradas): %', v_err;
  end;

  perform setval('plantas_vales_numero_vale_seq', s1, c1);
  perform setval('plantas_vales_numero_arido_seq', s2, c2);
  perform setval('plantas_remitos_numero_seq', s3, c3);
  perform setval('plantas_pedidos_numero_seq', s4, c4);
  perform setval('plantas_auditoria_id_seq', s5, c5);
  raise exception 'DRYRUN 66 OK — %', v_ok;
end;
$dry$;
