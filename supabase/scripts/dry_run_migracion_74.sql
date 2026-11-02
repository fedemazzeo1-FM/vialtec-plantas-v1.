-- ============================================================================
-- Ensayo de la migración 74. Correr DESPUÉS del contenido completo de
-- supabase/migrations/74_clientes_proveedores_por_id.sql, en la misma
-- transacción (o los dos dentro de un solo DO con EXECUTE). Termina SIEMPRE
-- con ERROR "DRYRUN 74 OK — …" (todo revertido). No consume numeración de
-- pedidos (no crea pedidos).
-- ============================================================================
do $dry$
declare
  v_felix     uuid := (select id from auth.users where email = 'felix.pereyra@vialtec.com.ar');
  v_ok        text[] := '{}';
  v_err       text;
  v_n         int;
  v_id        uuid;
  v_pedido    uuid;
  v_ingreso   uuid;
  v_mov_viejo int;
  r           record;
begin
  -- A. Unificación y totales intactos
  if (select count(*) from plantas_pedidos) <> 318
     or (select sum(cantidad_despachada) from plantas_pedidos) <> 27358.294 then
    raise exception 'A: cambió la cantidad de pedidos o el total despachado';
  end if;
  if exists (select 1 from plantas_pedidos where tipo_pedido = 'venta' and cliente_id is null)
     or exists (select 1 from plantas_ingresos where proveedor_id is null) then
    raise exception 'A: quedaron ventas sin cliente_id o ingresos sin proveedor_id';
  end if;
  if exists (select 1 from plantas_pedidos p join plantas_clientes c on c.id = p.cliente_id where p.cliente_externo <> c.nombre)
     or exists (select 1 from plantas_ingresos i join plantas_proveedores p on p.id = i.proveedor_id where i.proveedor <> p.nombre) then
    raise exception 'A: hay textos distintos al nombre del maestro';
  end if;
  for r in
    select * from (values
      ('AGGM CONTRUCCIONES', 4), ('G Y C CONSTRUCCIONES S.A', 5), ('HV-VIAL S.A', 6),
      ('Municipalidad de Exaltación de la Cruz', 4), ('EMISER S.A', 1),
      ('VIAL 8 S.A', 21), ('VIAL 8 S.A (EDMANCAR)', 10), ('COLEGIO MOORLANDS', 2),
      ('CORRALON FILIBERTI', 1), ('Corralon ramiro antonazzi', 1), ('INMIX', 2),
      ('Lucas Maldonado', 2), ('Vialmani', 2)
    ) t(nombre, esperado)
  loop
    select count(*) into v_n from plantas_pedidos p join plantas_clientes c on c.id = p.cliente_id where c.nombre = r.nombre;
    if v_n <> r.esperado then raise exception 'A: % tiene % pedidos (se esperaban %)', r.nombre, v_n, r.esperado; end if;
  end loop;
  v_ok := v_ok || 'A 318 pedidos y 27.358,294 despachado sin cambio; casos 1-5 unidos, VIAL 8/EDMANCAR y MOORLANDS separados, 865 ingresos con proveedor_id'::text;

  perform set_config('request.jwt.claims',
    json_build_object('sub', v_felix, 'email', 'felix.pereyra@vialtec.com.ar', 'role', 'authenticated')::text, true);

  -- B. Felix renombra un cliente en Maestros → todos sus pedidos cambian
  set local role authenticated;
  update plantas_clientes set nombre = 'VIALMANI PRUEBA' where nombre = 'Vialmani';
  reset role;
  select count(*) into v_n from plantas_pedidos where cliente_externo = 'VIALMANI PRUEBA';
  if v_n <> 2 or exists (select 1 from plantas_pedidos where cliente_externo = 'Vialmani') then
    raise exception 'B: renombrar el cliente dejó % pedidos con el nombre nuevo', v_n;
  end if;
  v_ok := v_ok || 'B renombrar cliente (Felix): sus 2 pedidos pasan al nombre nuevo, ninguno con el viejo'::text;

  -- C. Felix renombra un proveedor → ingresos y movimientos de stock cambian
  select count(*) into v_mov_viejo from plantas_stock_movimientos
   where tipo in ('ingreso_proveedor', 'recalculo_bascula') and origen = 'TRANSARIDOS S.A';
  set local role authenticated;
  update plantas_proveedores set nombre = 'TRANSARIDOS PRUEBA' where nombre = 'TRANSARIDOS S.A';
  reset role;
  if (select count(*) from plantas_ingresos where proveedor = 'TRANSARIDOS PRUEBA') <> 33
     or exists (select 1 from plantas_ingresos where proveedor = 'TRANSARIDOS S.A')
     or (select count(*) from plantas_stock_movimientos where origen = 'TRANSARIDOS PRUEBA') <> v_mov_viejo
     or exists (select 1 from plantas_stock_movimientos where origen = 'TRANSARIDOS S.A') then
    raise exception 'C: renombrar el proveedor no corrigió ingresos/movimientos';
  end if;
  v_ok := v_ok || ('C renombrar proveedor (Felix): 33 ingresos y ' || v_mov_viejo || ' movimientos con el nombre nuevo')::text;

  -- D. Pedido guardado con el nombre escrito distinto → queda vinculado y con el nombre del maestro
  select id into v_pedido from plantas_pedidos where cliente_externo = 'AUTOVIA MERCOSUR' limit 1;
  update plantas_pedidos set cliente_externo = '  vialmani   prueba ' where id = v_pedido;
  select c.id into v_id from plantas_clientes c where c.nombre = 'VIALMANI PRUEBA';
  if (select cliente_id from plantas_pedidos where id = v_pedido) <> v_id
     or (select cliente_externo from plantas_pedidos where id = v_pedido) <> 'VIALMANI PRUEBA' then
    raise exception 'D: el pedido no quedó vinculado al cliente';
  end if;
  v_ok := v_ok || 'D pedido con "  vialmani   prueba " → cliente_id y nombre del maestro'::text;

  -- E. Cliente que no está en el maestro → rechazo
  v_err := null;
  begin
    update plantas_pedidos set cliente_externo = 'CLIENTE INEXISTENTE 74' where id = v_pedido;
  exception when others then v_err := sqlerrm;
  end;
  if v_err is null or v_err not like '%no está en Maestros%' then raise exception 'E: %', coalesce(v_err, 'aceptó un cliente inexistente'); end if;
  v_ok := v_ok || 'E cliente fuera del maestro rechazado'::text;

  -- F. Ingreso: proveedor escrito distinto → vinculado; inexistente → rechazo
  select id into v_ingreso from plantas_ingresos where proveedor = 'TRANSARIDOS PRUEBA' limit 1;
  update plantas_ingresos set proveedor = ' cerro del  aguila ' where id = v_ingreso;
  if (select proveedor from plantas_ingresos where id = v_ingreso) <> 'CERRO DEL AGUILA'
     or (select proveedor_id from plantas_ingresos where id = v_ingreso) <> (select id from plantas_proveedores where nombre = 'CERRO DEL AGUILA') then
    raise exception 'F: el ingreso no quedó vinculado al proveedor';
  end if;
  v_err := null;
  begin
    update plantas_ingresos set proveedor = 'PROVEEDOR INEXISTENTE 74' where id = v_ingreso;
  exception when others then v_err := sqlerrm;
  end;
  if v_err is null or v_err not like '%no está en Maestros%' then raise exception 'F2: %', coalesce(v_err, 'aceptó un proveedor inexistente'); end if;
  v_ok := v_ok || 'F ingreso con " cerro del  aguila " → vinculado; proveedor inexistente rechazado'::text;

  -- G. Mismo nombre escrito distinto en el maestro → rechazo
  v_err := null;
  begin
    insert into plantas_clientes (nombre, activo) values ('vialmani prueba', true);
  exception when unique_violation then v_err := 'unico';
  end;
  if v_err is null then raise exception 'G: aceptó un cliente duplicado'; end if;
  v_err := null;
  begin
    insert into plantas_proveedores (nombre, activo) values ('Cerro  del Aguila', true);
  exception when unique_violation then v_err := 'unico';
  end;
  if v_err is null then raise exception 'G2: aceptó un proveedor duplicado'; end if;
  v_ok := v_ok || 'G cliente y proveedor duplicados (mayúsculas/espacios) rechazados'::text;

  -- H. Borrar un cliente o proveedor con movimientos → rechazo
  perform set_config('plantas.motivo_eliminacion', 'ensayo 74', true);
  v_err := null;
  begin
    delete from plantas_clientes where nombre = 'INMIX';
  exception when foreign_key_violation then v_err := 'fk';
  end;
  if v_err is null then raise exception 'H: borró un cliente con pedidos'; end if;
  v_err := null;
  begin
    delete from plantas_proveedores where nombre = 'MAPEI';
  exception when foreign_key_violation then v_err := 'fk';
  end;
  if v_err is null then raise exception 'H2: borró un proveedor con ingresos'; end if;
  v_ok := v_ok || 'H borrar cliente/proveedor con historial rechazado'::text;

  -- I. Venta sin cliente → rechazo
  v_err := null;
  begin
    update plantas_pedidos set cliente_externo = null where id = v_pedido;
  exception when check_violation then v_err := 'check';
  end;
  if v_err is null then raise exception 'I: aceptó una venta sin cliente'; end if;
  v_ok := v_ok || 'I venta sin cliente rechazada'::text;

  -- J. Permisos
  if has_table_privilege('anon', 'plantas_respaldo_mig74', 'select')
     or has_table_privilege('authenticated', 'plantas_respaldo_mig74', 'select')
     or has_function_privilege('anon', 'plantas_normalizar_nombre(text)', 'execute') then
    raise exception 'J: permisos mal';
  end if;
  v_ok := v_ok || 'J respaldo sin acceso desde la app; anon sin permisos'::text;

  raise exception 'DRYRUN 74 OK — %', array_to_string(v_ok, ' || ');
end;
$dry$;
