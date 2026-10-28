-- ============================================================================
-- Corrección de datos: cargas de asfalto tipeadas con el peso BRUTO del camión
-- en vez del neto (pedido de Federico, 28/10/2026).
--   P-0264, vale 10288: 48,88 → 32,42 (neto en balanza)
--   P-0273, vale 10312: 30,88 → 17,63 (neto en balanza)
-- Solo cambia plantas_cargas_asfalto.cantidad_tn (detalle por camión). NO toca
-- pedidos ni stock: cantidad_despachada de los dos pedidos ya es la de la
-- balanza (100,79 y 71,25, corregida por Felix) y el stock se descuenta desde
-- el pedido, no desde las cargas. plantas_cargas_asfalto no tiene triggers.
-- Una fila CORREGIR de auditoría por carga. Controla el estado de partida y
-- que el stock no se mueva; si algo no cierra, falla sin dejar nada a medias.
--
-- Dry-run: correr antes, en la misma ejecución,
--   select set_config('plantas.dry_run', 'on', false);
-- y el bloque termina con ERROR "DRYRUN CARGAS OK — …" (todo revertido).
-- ============================================================================
do $fix$
declare
  c_motivo constant text := 'Carga tipeada con el peso bruto';
  v_dry    boolean := coalesce(current_setting('plantas.dry_run', true), '') = 'on';
  v_stock0 numeric := (select sum(cantidad_kg) from plantas_stock);
  v_movs0  bigint  := (select count(*) from plantas_stock_movimientos);
  r        record;
  v_n      int := 0;
  v_txt    text := '';
begin
  for r in
    select c.id, c.numero_vale, c.cantidad_tn, v.peso_neto, v.peso_bruto, p.id as pedido_id, p.numero,
           p.cantidad_despachada, x.esperado_desp, x.carga_mal, x.neto_ok
      from (values (264, '10288', 100.79::numeric, 48.88::numeric, 32.42::numeric),
                   (273, '10312', 71.25::numeric, 30.88::numeric, 17.63::numeric)) x(numero, vale, esperado_desp, carga_mal, neto_ok)
      join plantas_pedidos p on p.numero = x.numero
      join plantas_cargas_asfalto c on c.pedido_id = p.id and c.numero_vale = x.vale
      join plantas_vales v on v.numero_vale::text = c.numero_vale and v.tipo_vale = 'asfalto' and not v.anulado and v.pedido_id = p.id
     for update of c
  loop
    if r.cantidad_tn <> r.carga_mal or r.peso_bruto <> r.carga_mal or r.peso_neto <> r.neto_ok
       or r.cantidad_despachada <> r.esperado_desp then
      raise exception 'P-% vale %: estado inesperado (carga %, bruto %, neto %, despachado %)',
        r.numero, r.numero_vale, r.cantidad_tn, r.peso_bruto, r.peso_neto, r.cantidad_despachada;
    end if;

    update plantas_cargas_asfalto set cantidad_tn = r.peso_neto where id = r.id;

    perform plantas_auditar('CORREGIR', 'despachos', 'carga_asfalto', r.numero_vale,
      'Carga vale ' || r.numero_vale || ' — ' || plantas_auditoria_label_pedido(r.pedido_id),
      c_motivo,
      jsonb_build_object('cantidad_tn', r.cantidad_tn),
      jsonb_build_object('cantidad_tn', r.peso_neto));

    v_n := v_n + 1;
    v_txt := v_txt || format('P-%s vale %s: %s → %s; ', lpad(r.numero::text, 4, '0'), r.numero_vale, r.cantidad_tn, r.peso_neto);
  end loop;

  if v_n <> 2 then
    raise exception 'Se esperaban 2 cargas y se encontraron %', v_n;
  end if;
  -- Cargas = balanza = despachado en los dos pedidos
  if exists (select 1 from plantas_pedidos p where p.numero in (264, 273)
              and (select sum(cantidad_tn) from plantas_cargas_asfalto c where c.pedido_id = p.id) <> p.cantidad_despachada) then
    raise exception 'Las cargas no suman el despachado';
  end if;
  if (select sum(cantidad_kg) from plantas_stock) is distinct from v_stock0
     or (select count(*) from plantas_stock_movimientos) <> v_movs0 then
    raise exception 'El stock cambió y no debía';
  end if;

  if v_dry then
    raise exception 'DRYRUN CARGAS OK — %stock sin cambio, % filas de auditoría', v_txt,
      (select count(*) from plantas_auditoria where motivo = c_motivo);
  end if;
  raise notice 'Cargas corregidas — %', v_txt;
end;
$fix$;
