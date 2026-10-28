-- ============================================================================
-- Dry-run de la migración 71. Pegar DESPUÉS del contenido completo de
-- supabase/migrations/71_fecha_despacho_mixer_y_vista_despachos.sql, en la
-- misma ejecución. Termina SIEMPRE con ERROR "DRYRUN 71 OK — …" (todo
-- revertido). Las cargas de prueba no consumen numeración (el N° de remito de
-- mixer lo tipea el plantista).
-- ============================================================================
do $dry$
declare
  v_felix   uuid := (select id from auth.users where email = 'felix.pereyra@vialtec.com.ar');
  v_p271    uuid := (select id from plantas_pedidos where numero = 271);
  v_conf    plantas_pedidos;
  v_carga   plantas_cargas_hormigon;
  v_err     boolean;
  v_ok      text[] := '{}';
  v_n       int;
  v_txt     text;
  v_fecha   date;
begin
  -- A. Vista: tipos y unidades de la rama mixer
  select string_agg(material || '/' || unidad_volumen || ' ' || n, ', ' order by material) into v_txt
    from (select material, unidad_volumen, count(*) n from plantas_v_despachos_camion group by 1, 2) x;
  if exists (select 1 from plantas_v_despachos_camion where material = 'mezcla_cemento' and unidad_volumen <> 'tn')
     or exists (select 1 from plantas_v_despachos_camion where material = 'hormigon' and unidad_volumen <> 'm3') then
    raise exception 'A: unidades mal asignadas (%)', v_txt;
  end if;
  v_ok := v_ok || ('A ' || v_txt)::text;

  -- B. Moorlands Pilar: la fecha (día AR) de cada carga vieja es la del pedido
  select count(*) into v_n
    from plantas_v_despachos_camion d
    join plantas_pedidos p on p.id = d.pedido_id
    join flota_obras o on o.id = d.obra_id
   where o.nombre = 'Moorlands Pilar' and d.material <> 'asfalto'
     and (d.fecha at time zone 'America/Argentina/Buenos_Aires')::date <> p.fecha_programada;
  if v_n <> 0 then raise exception 'B: % cargas de Moorlands Pilar con fecha distinta a la del pedido', v_n; end if;
  select count(*) into v_n from plantas_v_despachos_camion d join flota_obras o on o.id = d.obra_id
   where o.nombre = 'Moorlands Pilar' and d.material = 'mezcla_cemento';
  v_ok := v_ok || ('B Moorlands Pilar: fechas = pedido, ' || v_n || ' cargas de mezcla cemento en tn')::text;

  -- C. Permisos y firma
  if exists (select 1 from pg_proc where proname = 'registrar_carga_hormigon' and pronargs <> 8) then
    raise exception 'C: quedó la firma vieja';
  end if;
  if has_function_privilege('anon', 'registrar_carga_hormigon(uuid,text,numeric,text,text,timestamptz,text,date)', 'execute')
     or not has_function_privilege('authenticated', 'registrar_carga_hormigon(uuid,text,numeric,text,text,timestamptz,text,date)', 'execute') then
    raise exception 'C: permisos mal (anon debe no, authenticated debe sí)';
  end if;
  if not exists (select 1 from pg_class where relname = 'plantas_v_despachos_camion' and 'security_invoker=true' = any(reloptions)) then
    raise exception 'C: la vista perdió security_invoker';
  end if;
  v_ok := v_ok || 'C firma de 8 parámetros, sin anon, vista con security_invoker'::text;

  -- D. Fecha futura → rechazo (como Felix, plantista)
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_felix, 'email', 'felix.pereyra@vialtec.com.ar', 'role', 'authenticated')::text, true);
  set local role authenticated;
  v_err := false;
  begin
    perform registrar_carga_hormigon(v_p271, 'DRYRUN', 1, null, null, now(), null, current_date + 3);
  exception when others then v_err := sqlerrm like 'La fecha de despacho no puede ser futura%';
  end;
  reset role;
  if not v_err then raise exception 'D: aceptó una fecha futura'; end if;
  v_ok := v_ok || 'D fecha futura rechazada'::text;

  -- E. Carga con fecha de despacho en un pedido de mixer confirmado (si hay)
  select * into v_conf from plantas_pedidos
   where tipo in ('hormigon', 'mezcla_cemento') and estado = 'confirmado' order by fecha_programada desc limit 1;
  if v_conf.id is null then
    v_ok := v_ok || 'E sin pedido de mixer confirmado para probar (salteado)'::text;
  else
    -- Igual que el modal: la fecha del pedido, o hoy si el pedido está programado para más adelante.
    v_fecha := least(v_conf.fecha_programada, (now() at time zone 'America/Argentina/Buenos_Aires')::date);
    set local role authenticated;
    v_carga := registrar_carga_hormigon(v_conf.id, 'DRYRUN-71', 1, null, null, now(), null, v_fecha);
    reset role;
    if v_carga.fecha_despacho is distinct from v_fecha then
      raise exception 'E: fecha_despacho % (se esperaba %)', v_carga.fecha_despacho, v_fecha;
    end if;
    if not exists (select 1 from plantas_v_despachos_camion
                    where numero_remito = 'DRYRUN-71'
                      and (fecha at time zone 'America/Argentina/Buenos_Aires')::date = v_fecha
                      and material = v_conf.tipo) then
      raise exception 'E: la vista no muestra la carga con su fecha de despacho';
    end if;
    if not exists (select 1 from plantas_auditoria where entidad = 'carga_hormigon' and entidad_ref = 'DRYRUN-71'
                    and valores_despues ->> 'fecha_despacho' = v_fecha::text) then
      raise exception 'E: la auditoría no guarda fecha_despacho';
    end if;
    v_ok := v_ok || ('E carga en ' || plantas_etiqueta_pedido(v_conf.numero) || ' con fecha ' || v_fecha || ' → vista y auditoría OK')::text;
  end if;

  raise exception 'DRYRUN 71 OK — %', array_to_string(v_ok, ' || ');
end;
$dry$;
