-- ============================================================================
-- Ensayo de la migración 78. Correr DESPUÉS de 78_vales_manuales_remito_por_grupo.sql, en la misma transacción.
-- Termina SIEMPRE con ERROR "DRYRUN 78 OK — …" (todo revertido). Devuelve la numeración de remitos a su valor.
-- ============================================================================
do $dry$
declare
  v_ok        text[] := '{}';
  v_seq_antes bigint;
  v_seq_llamada boolean;
  v_obra      bigint := (select id from flota_obras where nombre ilike 'PRUEBA OBRAS%' limit 1);
  v_formula   uuid := (select id from plantas_formulas where tipo = 'asfalto' and activo order by nombre limit 1);
  v_a plantas_vales_manuales; v_b plantas_vales_manuales; v_c plantas_vales_manuales;
  v_d plantas_vales_manuales; v_e plantas_vales_manuales;
  v_prev_m2   bigint := (select numero_remito from plantas_vales_manuales where numero = 2);
begin
  select last_value, is_called into v_seq_antes, v_seq_llamada from plantas_remitos_numero_seq;
  perform set_config('request.jwt.claims', '{"email":"federico.mazzeo@vialtec.com.ar","role":"authenticated"}', true);

  -- Tres vales a la misma obra el mismo día (uno a la noche: 23:30 AR sigue siendo ese día), uno al día
  -- siguiente y uno a un cliente el mismo día.
  v_a := generar_vale_manual('2026-11-20 08:00-03', v_formula, 38, 14, v_obra);
  v_b := generar_vale_manual('2026-11-20 10:00-03', v_formula, 40, 14, v_obra);
  v_c := generar_vale_manual('2026-11-20 23:30-03', v_formula, 39, 14, v_obra);
  v_d := generar_vale_manual('2026-11-21 08:00-03', v_formula, 39, 14, v_obra);
  v_e := generar_vale_manual('2026-11-20 09:00-03', v_formula, 39, 14, null, 'Cliente Ensayo');

  v_b := generar_remito_vale_manual(v_b.id);
  v_a := generar_remito_vale_manual(v_a.id);
  v_c := generar_remito_vale_manual(v_c.id);
  v_d := generar_remito_vale_manual(v_d.id);
  v_e := generar_remito_vale_manual(v_e.id);

  if v_b.numero_remito <> v_seq_antes + (case when v_seq_llamada then 1 else 0 end) then raise exception 'A: primero %', v_b.numero_remito; end if;
  if v_a.numero_remito <> v_b.numero_remito or v_c.numero_remito <> v_b.numero_remito then
    raise exception 'A: mismo grupo distinto remito % % %', v_a.numero_remito, v_b.numero_remito, v_c.numero_remito;
  end if;
  v_ok := v_ok || ('A misma obra y día (08:00, 10:00, 23:30): un remito ' || v_b.numero_remito)::text;

  if v_d.numero_remito = v_b.numero_remito or v_e.numero_remito = v_b.numero_remito or v_d.numero_remito = v_e.numero_remito then
    raise exception 'B: grupos mezclados % % %', v_b.numero_remito, v_d.numero_remito, v_e.numero_remito;
  end if;
  v_ok := v_ok || ('B otro día → ' || v_d.numero_remito || '; cliente el mismo día → ' || v_e.numero_remito)::text;

  -- Anular el que tiene el número no libera el número: un vale nuevo del grupo lo reusa.
  perform anular_vale_manual(v_b.id, 'ensayo');
  v_a := generar_vale_manual('2026-11-20 12:00-03', v_formula, 41, 14, v_obra);
  v_a := generar_remito_vale_manual(v_a.id);
  if v_a.numero_remito <> v_b.numero_remito then raise exception 'C: %', v_a.numero_remito; end if;
  v_ok := v_ok || 'C vale nuevo del grupo después de una anulación: mismo remito'::text;

  -- Los vales existentes no cambian.
  if (select numero_remito from plantas_vales_manuales where numero = 2) is distinct from v_prev_m2
     or (select numero_remito from plantas_vales_manuales where numero = 1) <> 169 then
    raise exception 'D: tocó vales existentes';
  end if;
  v_ok := v_ok || 'D M-00001 (remito 169) y M-00002 sin cambios'::text;

  perform setval('plantas_remitos_numero_seq', v_seq_antes, v_seq_llamada);
  raise exception 'DRYRUN 78 OK — %', array_to_string(v_ok, ' || ');
exception when others then
  if v_seq_antes is not null then perform setval('plantas_remitos_numero_seq', v_seq_antes, v_seq_llamada); end if;
  raise;
end;
$dry$;
