-- ============================================================================
-- Dry-run de la migración 73. Pegar DESPUÉS del contenido completo de
-- supabase/migrations/73_cargas_asfalto_desde_balanza.sql, en la misma
-- ejecución. Termina SIEMPRE con ERROR "DRYRUN 73 OK — …" (todo revertido).
--
-- Escenario: dentro de la transacción (se revierte) P-0264 vuelve a
-- 'confirmado' con 0 tn y sin cargas, para probar el despacho desde sus 3
-- vales de balanza (10286, 10287, 10288). No consume numeración.
-- ============================================================================
do $dry$
declare
  v_felix   uuid := (select id from auth.users where email = 'felix.pereyra@vialtec.com.ar');
  v_p264    uuid := (select id from plantas_pedidos where numero = 264);
  v_anulado text := (select numero_vale::text from plantas_vales where tipo_vale = 'asfalto' and anulado order by numero_vale desc limit 1);
  v_carga   plantas_cargas_asfalto;
  v_ok      text[] := '{}';
  v_err     text;
  v_total   numeric;
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_felix, 'email', 'felix.pereyra@vialtec.com.ar', 'role', 'authenticated')::text, true);

  -- Escenario (como postgres, se revierte al final)
  delete from plantas_cargas_asfalto where pedido_id = v_p264;
  update plantas_pedidos set estado = 'confirmado', cantidad_despachada = 0 where id = v_p264;

  -- A. Vale de balanza con cantidad tipeada mal (el bruto) → guarda el neto
  set local role authenticated;
  v_carga := registrar_carga_asfalto(v_p264, '10288', 48.88, null, now(), null);
  reset role;
  if v_carga.cantidad_tn <> 32.42 or v_carga.patente is distinct from 'AD-519-YI' then
    raise exception 'A: guardó % tn / patente % (se esperaba 32,42 / AD-519-YI)', v_carga.cantidad_tn, v_carga.patente;
  end if;
  v_ok := v_ok || 'A 10288: tipeado 48,88 → guarda el neto 32,42 y la patente del vale'::text;

  -- B. Mismo vale dos veces → rechazo
  v_err := null;
  set local role authenticated;
  begin
    perform registrar_carga_asfalto(v_p264, '10288', 32.42, null, now(), null);
  exception when others then v_err := sqlerrm;
  end;
  reset role;
  if v_err is null or v_err not like '%ya está cargado%' then raise exception 'B: aceptó el vale repetido (%)', v_err; end if;
  v_ok := v_ok || 'B vale repetido rechazado'::text;

  -- C. Vale de otro pedido (10312 es de P-0273) → rechazo
  v_err := null;
  set local role authenticated;
  begin
    perform registrar_carga_asfalto(v_p264, '10312', 17.63, null, now(), null);
  exception when others then v_err := sqlerrm;
  end;
  reset role;
  if v_err is null or v_err not like '%es de otro pedido (P-0273)%' then raise exception 'C: %', coalesce(v_err, 'aceptó un vale de otro pedido'); end if;
  v_ok := v_ok || 'C vale de otro pedido rechazado'::text;

  -- D. Vale anulado → rechazo
  if v_anulado is not null then
    v_err := null;
    set local role authenticated;
    begin
      perform registrar_carga_asfalto(v_p264, v_anulado, 10, null, now(), null);
    exception when others then v_err := sqlerrm;
    end;
    reset role;
    if v_err is null or v_err not like '%anulado%' then raise exception 'D: %', coalesce(v_err, 'aceptó un vale anulado'); end if;
    v_ok := v_ok || ('D vale anulado ' || v_anulado || ' rechazado')::text;
  end if;

  -- E. Vale que no está en balanza, sin motivo → rechazo; con motivo → entra y se audita
  v_err := null;
  set local role authenticated;
  begin
    perform registrar_carga_asfalto(v_p264, 'DRYRUN-73', 5, null, now(), null);
  exception when others then v_err := sqlerrm;
  end;
  reset role;
  if v_err is null or v_err not like '%no está en balanza%' then raise exception 'E1: %', coalesce(v_err, 'aceptó sin motivo'); end if;
  set local role authenticated;
  v_carga := registrar_carga_asfalto(v_p264, 'DRYRUN-73', 5, 'AAA-000', now(), 'Balanza fuera de servicio');
  reset role;
  if v_carga.cantidad_tn <> 5 or not exists (select 1 from plantas_auditoria where entidad = 'carga_asfalto'
        and entidad_ref = 'DRYRUN-73' and motivo = 'Carga sin vale de balanza: Balanza fuera de servicio') then
    raise exception 'E2: la carga sin balanza no quedó con su cantidad o su motivo en auditoría';
  end if;
  v_ok := v_ok || 'E sin balanza: sin motivo rechazado, con motivo entra y queda auditado'::text;

  -- F. Las otras dos cargas desde balanza; el despachado suma los netos
  set local role authenticated;
  perform registrar_carga_asfalto(v_p264, '10286', 0, null, now(), null);
  perform registrar_carga_asfalto(v_p264, '10287', 999, null, now(), null);
  reset role;
  select cantidad_despachada into v_total from plantas_pedidos where id = v_p264;
  if v_total <> 100.79 + 5 then raise exception 'F: despachado % (se esperaba 105,79)', v_total; end if;
  v_ok := v_ok || 'F 3 vales + 1 manual: despachado 105,79 (balanza 100,79 + 5)'::text;

  -- G. Permisos
  if has_function_privilege('anon', 'registrar_carga_asfalto(uuid,text,numeric,text,timestamptz,text)', 'execute')
     or not has_function_privilege('authenticated', 'registrar_carga_asfalto(uuid,text,numeric,text,timestamptz,text)', 'execute') then
    raise exception 'G: permisos mal';
  end if;
  v_ok := v_ok || 'G authenticated sí, anon no'::text;

  raise exception 'DRYRUN 73 OK — %', array_to_string(v_ok, ' || ');
end;
$dry$;
