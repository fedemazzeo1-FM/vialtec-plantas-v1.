-- ============================================================================
-- Corrección de datos: vales I-613 (01/10/2026) e I-729 (08/10/2026)
-- Cargados como 0/3, eran ARENA (confirmado por Federico, 2026-10-10).
--
-- Correr DESPUÉS de la migración 63. Cambia el material del ingreso y pasa el
-- movimiento del vale de 0/3 a ARENA en el historial de stock, con su ajuste
-- de compensación: los SALDOS de 0/3 y ARENA NO cambian (las cuentas parten
-- del relevamiento de Felix del 09/10/2026). Deja fila de auditoría por vale.
-- Si algo no cierra, falla sin dejar nada a medias.
-- ============================================================================
do $fix$
declare
  r record;
  v_viejo uuid := plantas_buscar_material_id('0/3');
  v_nuevo uuid := plantas_buscar_material_id('ARENA');
  v_kg numeric; v_antes numeric; v_n int := 0;
begin
  if v_viejo is null or v_nuevo is null then
    raise exception 'No se encontró 0/3 o ARENA en el catálogo';
  end if;
  select sum(cantidad_kg) into v_antes from plantas_stock where material_id in (v_viejo, v_nuevo);

  for r in
    select v.id as vale_id, v.numero_vale_arido, i.id as ingreso_id, i.cantidad, i.proveedor, i.numero_remito
      from plantas_vales v join plantas_ingresos i on i.vale_id = v.id
     where v.tipo_vale = 'ingreso_arido' and v.numero_vale_arido in (613, 729)
       and not v.anulado and i.material = '0/3'
  loop
    select coalesce(sum(cantidad_kg), 0) into v_kg
      from plantas_stock_movimientos
     where vale_id = r.vale_id and material_id = v_viejo
       and tipo in ('ingreso_proveedor', 'recalculo_bascula');
    if v_kg <> r.cantidad * 1000 then
      raise exception 'Vale I-%: el stock ligado (% kg) no coincide con el remito (% kg)', r.numero_vale_arido, v_kg, r.cantidad * 1000;
    end if;

    update plantas_ingresos set material = 'ARENA' where id = r.ingreso_id;

    insert into plantas_stock_movimientos (material_id, tipo, cantidad_kg, origen, numero_remito, vale_id, ingreso_id, observaciones, responsable_email)
    values
      (v_viejo, 'recalculo_bascula', -v_kg, r.proveedor, r.numero_remito, r.vale_id, r.ingreso_id,
       'Corrección de vale #I-' || lpad(r.numero_vale_arido::text, 5, '0') || ': cambio de material a ARENA', 'sistema (SQL)'),
      (v_nuevo, 'recalculo_bascula', v_kg, r.proveedor, r.numero_remito, r.vale_id, r.ingreso_id,
       'Corrección de vale #I-' || lpad(r.numero_vale_arido::text, 5, '0') || ': estaba cargado como 0/3', 'sistema (SQL)');

    insert into plantas_stock_movimientos (material_id, tipo, cantidad_kg, origen, observaciones, responsable_email)
    values
      (v_viejo, 'ajuste', v_kg, 'Compensación corrección de material',
       'Vale #I-' || lpad(r.numero_vale_arido::text, 5, '0') || ' pasó a ARENA: el saldo parte del relevamiento del 09/10/2026 y no cambia', 'sistema (SQL)'),
      (v_nuevo, 'ajuste', -v_kg, 'Compensación corrección de material',
       'Vale #I-' || lpad(r.numero_vale_arido::text, 5, '0') || ' pasó a ARENA: el saldo parte del relevamiento del 09/10/2026 y no cambia', 'sistema (SQL)');

    insert into plantas_vales_historial (vale_id, accion, antes, despues, usuario_email, motivo)
    values (r.vale_id, 'edicion', jsonb_build_object('material', '0/3'), jsonb_build_object('material', 'ARENA'),
            'sistema (SQL)', 'Material mal cargado: era ARENA (confirmado por Federico, 10/10/2026)');

    perform plantas_auditar(
      'CORREGIR', 'bascula', 'vale', r.vale_id::text,
      'Vale I-' || lpad(r.numero_vale_arido::text, 5, '0') || ' — material',
      'Material mal cargado: era ARENA (confirmado por Federico, 10/10/2026). Saldos de 0/3 y ARENA sin cambio.',
      jsonb_build_object('material', '0/3'), jsonb_build_object('material', 'ARENA')
    );
    v_n := v_n + 1;
  end loop;

  if v_n <> 2 then
    raise exception 'Se esperaban 2 vales para corregir y se encontraron %', v_n;
  end if;
  if (select sum(cantidad_kg) from plantas_stock where material_id in (v_viejo, v_nuevo)) is distinct from v_antes then
    raise exception 'El saldo cambió y no debía';
  end if;
end;
$fix$;
