-- ============================================================================
-- Migración 63: ingreso de áridos — editar/anular mueven stock, cambio de
-- material, tope de Cant. s/Remito, proveedores unificados
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido de Federico (2026-10-08 / 2026-10-10). Causa raíz: en un vale
-- 'ingreso_arido' el material vive en plantas_ingresos.material
-- (plantas_vales.material queda null), pero corregir_vale_bascula y
-- anular_vale_bascula lo buscaban en plantas_vales → no encontraban material
-- y el recálculo de stock salía sin hacer nada. Editar o anular un ingreso
-- nunca corregía el stock (vales I-614, I-717, I-718).
--
--   1. corregir_vale_bascula: toma el material de plantas_ingresos; parámetro
--      nuevo p_material (al final) para cambiarlo: revierte el stock del
--      material anterior y lo suma al nuevo. Cambia la firma: drop + create y
--      permisos de nuevo (sin anon).
--   2. anular_vale_bascula: mismo arreglo; marca plantas_ingresos.anulado.
--   3. plantas_ingresos.anulado (nuevo): la Analítica de proveedores lee
--      plantas_ingresos y no tenía forma de excluir un ingreso anulado.
--   4. Tope: la cantidad según remito no puede diferir más de un 20 % del
--      peso neto pesado (alta por trigger, edición en la RPC). Medido sobre
--      744 ingresos: p1 = 0,970 y p99 = 1,021; solo 2 quedan fuera del 20 %.
--   5. Proveedores: el nombre se guarda siempre como figura en el catálogo
--      (trigger) y se unifican los históricos ("Cerro del Aguila" →
--      "CERRO DEL AGUILA", etc.) en plantas_ingresos y en el origen de los
--      movimientos de stock.
--   6. Datos: los vales I-614, I-717 e I-718 quedan con su recálculo en el
--      historial de stock SIN tocar el saldo: el relevamiento del 09/10/2026
--      (Felix) ya había absorbido el error.
--
-- Vales migrados del legado (sin movimiento de stock ligado al vale): editar
-- o anular sigue sin mover stock, porque no hay contra qué recalcular.
--
-- IMPORTANTE: aplicar JUNTO con el deploy del frontend (selector de material
-- y filtro `anulado` en la analítica). Fuera del horario de báscula.
-- ============================================================================

do $pre$
begin
  if (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'corregir_vale_bascula') <> 'f1c5e2d4f2e5d7137fd06a7aa6fe7657' then
    raise exception 'MIG63: corregir_vale_bascula en producción no es la versión esperada';
  end if;
  if (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'anular_vale_bascula') <> 'fd2e6a092faa58f1f460e83b4a330bae' then
    raise exception 'MIG63: anular_vale_bascula en producción no es la versión esperada';
  end if;
end;
$pre$;

-- ---------------------------------------------------------------------------
-- 3. plantas_ingresos.anulado
-- ---------------------------------------------------------------------------
alter table plantas_ingresos add column anulado boolean not null default false;

update plantas_ingresos i
   set anulado = true
  from plantas_vales v
 where v.id = i.vale_id and v.anulado;

-- ---------------------------------------------------------------------------
-- 4 y 5. Tope de cantidad + nombre de proveedor del catálogo
-- ---------------------------------------------------------------------------
create function plantas_validar_cantidad_remito(p_cantidad_tn numeric, p_neto_tn numeric)
returns void
language plpgsql
set search_path to 'public'
as $function$
begin
  if p_cantidad_tn is null or p_neto_tn is null or not (p_neto_tn > 0) then
    return;
  end if;
  if p_cantidad_tn > p_neto_tn * 1.2 or p_cantidad_tn < p_neto_tn * 0.8 then
    raise exception 'La cantidad según remito (% tn) difiere más de un 20 %% del peso neto pesado (% tn). Revisá que esté cargada en toneladas.',
      p_cantidad_tn, p_neto_tn;
  end if;
end;
$function$;

revoke execute on function plantas_validar_cantidad_remito(numeric, numeric) from public, anon, authenticated;

create function plantas_trg_ingresos_normalizar()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
declare
  v_neto_tn numeric;
begin
  new.proveedor := coalesce(
    (select nombre from plantas_proveedores where lower(btrim(nombre)) = lower(btrim(new.proveedor)) limit 1),
    btrim(new.proveedor)
  );

  if new.vale_id is not null and (tg_op = 'INSERT' or new.cantidad is distinct from old.cantidad) then
    select case when unidad = 'kg' then peso_neto / 1000 else peso_neto end into v_neto_tn
      from plantas_vales where id = new.vale_id;
    perform plantas_validar_cantidad_remito(
      case when new.unidad = 'kg' then new.cantidad / 1000 else new.cantidad end, v_neto_tn
    );
  end if;

  return new;
end;
$function$;

revoke execute on function plantas_trg_ingresos_normalizar() from public, anon, authenticated;

create trigger plantas_ingresos_normalizar
  before insert or update of proveedor, cantidad on plantas_ingresos
  for each row execute function plantas_trg_ingresos_normalizar();

-- ---------------------------------------------------------------------------
-- 1. corregir_vale_bascula (firma nueva: + p_material)
-- ---------------------------------------------------------------------------
drop function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint, text);

create function corregir_vale_bascula(
  p_vale_id uuid, p_peso_bruto numeric, p_tara numeric,
  p_patente text default null, p_chofer text default null, p_observaciones text default null,
  p_temperatura numeric default null, p_proveedor text default null, p_numero_remito text default null,
  p_cantidad_remito numeric default null, p_obra_id bigint default null, p_motivo text default null,
  p_material text default null
)
returns plantas_vales
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_aud_antes jsonb;
  v_vale        plantas_vales;
  v_antes       jsonb;
  v_peso_neto   numeric;
  v_neto_tn     numeric;
  v_material_id uuid;
  v_ingreso            plantas_ingresos;
  v_material_nuevo     text;
  v_material_viejo_id  uuid;
  v_mueve_stock        boolean;
begin
  if not plantas_tiene_permiso('bascula', 'editar') then
    raise exception 'Tu rol (%) no puede editar vales de báscula.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select * into v_vale from plantas_vales where id = p_vale_id;
  v_aud_antes := plantas_auditoria_snapshot_vale(p_vale_id);
  if not found then
    raise exception 'El vale % no existe.', p_vale_id;
  end if;
  if v_vale.anulado then
    raise exception 'Este vale está anulado — no se puede editar. Cargá un vale nuevo si corresponde.';
  end if;

  if nullif(btrim(p_motivo), '') is null then
    raise exception 'Indicá el motivo de la corrección del vale.';
  end if;

  if not (p_peso_bruto > 0) then
    raise exception 'peso_bruto debe ser mayor a 0';
  end if;
  if not (p_tara >= 0) then
    raise exception 'tara no puede ser negativa';
  end if;
  if not (p_peso_bruto > p_tara) then
    raise exception 'el peso bruto debe ser mayor que la tara';
  end if;

  v_peso_neto := p_peso_bruto - p_tara;
  v_neto_tn := case when v_vale.unidad = 'kg' then v_peso_neto / 1000 else v_peso_neto end;

  if v_vale.tipo_vale = 'ingreso_arido' and p_numero_remito is not null and btrim(p_numero_remito) <> '' then
    if exists (
      select 1 from plantas_ingresos
      where numero_remito = btrim(p_numero_remito) and vale_id <> p_vale_id
    ) then
      raise exception 'Ya existe otro ingreso registrado con el remito %.', p_numero_remito;
    end if;
  end if;

  if v_vale.tipo_vale = 'ingreso_arido' then
    select * into v_ingreso from plantas_ingresos where vale_id = p_vale_id limit 1;
    if not found then
      raise exception 'El vale % no tiene su ingreso de áridos asociado.', plantas_etiqueta_vale(v_vale);
    end if;

    v_material_viejo_id := plantas_buscar_material_id(v_ingreso.material);
    v_material_nuevo := coalesce(nullif(btrim(p_material), ''), v_ingreso.material);
    v_material_id := plantas_buscar_material_id(v_material_nuevo);
    if v_material_id is null then
      raise exception 'El material "%" no está en el catálogo de materiales.', v_material_nuevo;
    end if;

    perform plantas_validar_cantidad_remito(coalesce(p_cantidad_remito, v_ingreso.cantidad), v_neto_tn);

    -- Un vale migrado del legado no tiene movimiento de stock ligado: no hay
    -- contra qué recalcular, así que su edición no mueve stock.
    v_mueve_stock := exists (select 1 from plantas_stock_movimientos where vale_id = p_vale_id)
      or not exists (select 1 from plantas_materiales where id = v_material_viejo_id and controla_stock);
  end if;

  v_antes := jsonb_build_object(
    'peso_bruto', v_vale.peso_bruto, 'tara', v_vale.tara, 'peso_neto', v_vale.peso_neto,
    'patente', v_vale.patente, 'chofer', v_vale.chofer, 'temperatura', v_vale.temperatura,
    'obra_id', v_vale.obra_id, 'observaciones', v_vale.observaciones
  );
  if v_vale.tipo_vale = 'ingreso_arido' then
    v_antes := v_antes || jsonb_build_object(
      'material', v_ingreso.material, 'proveedor', v_ingreso.proveedor,
      'numero_remito', v_ingreso.numero_remito, 'cantidad_remito', v_ingreso.cantidad
    );
  end if;

  update plantas_vales set
    peso_bruto    = p_peso_bruto,
    tara          = p_tara,
    peso_neto     = v_peso_neto,
    patente       = coalesce(p_patente, patente),
    chofer        = case when tipo_vale = 'asfalto' then coalesce(p_chofer, chofer) else chofer end,
    temperatura   = case when tipo_vale = 'asfalto' then p_temperatura else temperatura end,
    obra_id       = case when tipo_vale = 'egreso_arido' then coalesce(p_obra_id, obra_id) else obra_id end,
    observaciones = coalesce(p_observaciones, observaciones)
  where id = p_vale_id
  returning * into v_vale;

  if v_vale.tipo_vale = 'ingreso_arido' then
    update plantas_ingresos set
      material      = v_material_nuevo,
      proveedor     = coalesce(p_proveedor, proveedor),
      numero_remito = coalesce(nullif(btrim(p_numero_remito), ''), numero_remito),
      cantidad      = coalesce(p_cantidad_remito, cantidad)
    where id = v_ingreso.id
    returning * into v_ingreso;

    if v_mueve_stock then
      if v_material_viejo_id is distinct from v_material_id then
        perform plantas_recalcular_stock_vale(
          p_vale_id, v_material_viejo_id, 0, v_ingreso.proveedor, v_ingreso.numero_remito,
          'Corrección de vale #' || plantas_etiqueta_vale(v_vale) || ': cambio de material a ' || v_ingreso.material
        );
      end if;
      perform plantas_recalcular_stock_vale(
        p_vale_id, v_material_id, v_ingreso.cantidad * 1000,
        v_ingreso.proveedor, v_ingreso.numero_remito, 'Corrección de vale #' || plantas_etiqueta_vale(v_vale)
      );
    end if;
  end if;

  if v_vale.tipo_vale = 'egreso_arido' then
    v_material_id := plantas_buscar_material_id(v_vale.material);
    perform plantas_recalcular_stock_vale(
      p_vale_id, v_material_id, -(v_neto_tn * 1000),
      null, null, 'Corrección de vale #' || plantas_etiqueta_vale(v_vale)
    );
  end if;

  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, antes, despues, usuario_email, motivo)
  values (
    p_vale_id, 'edicion', v_vale.pedido_id, v_vale.pedido_id, v_antes,
    jsonb_build_object(
      'peso_bruto', v_vale.peso_bruto, 'tara', v_vale.tara, 'peso_neto', v_vale.peso_neto,
      'patente', v_vale.patente, 'chofer', v_vale.chofer, 'temperatura', v_vale.temperatura,
      'obra_id', v_vale.obra_id, 'observaciones', v_vale.observaciones
    ) || case when v_vale.tipo_vale = 'ingreso_arido' then jsonb_build_object(
      'material', v_ingreso.material, 'proveedor', v_ingreso.proveedor,
      'numero_remito', v_ingreso.numero_remito, 'cantidad_remito', v_ingreso.cantidad
    ) else '{}'::jsonb end,
    auth.email(), btrim(p_motivo)
  );

  if v_aud_antes is distinct from plantas_auditoria_snapshot_vale(p_vale_id) then
    perform plantas_auditar_vale('CORREGIR', p_vale_id, btrim(p_motivo), v_aud_antes);
  end if;

  return v_vale;
end;
$function$;

revoke execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint, text, text) from public, anon;
grant execute on function corregir_vale_bascula(uuid, numeric, numeric, text, text, text, numeric, text, text, numeric, bigint, text, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. anular_vale_bascula (misma firma)
-- ---------------------------------------------------------------------------
create or replace function anular_vale_bascula(p_vale_id uuid, p_motivo text)
returns plantas_vales
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_aud_antes jsonb;
  v_vale        plantas_vales;
  v_material_id uuid;
begin
  if not plantas_tiene_permiso('bascula', 'eliminar') then
    raise exception 'Tu rol (%) no puede anular vales de báscula.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  if p_motivo is null or btrim(p_motivo) = '' then
    raise exception 'El motivo de anulación es obligatorio.';
  end if;

  select * into v_vale from plantas_vales where id = p_vale_id;
  v_aud_antes := plantas_auditoria_snapshot_vale(p_vale_id);
  if not found then
    raise exception 'El vale % no existe.', p_vale_id;
  end if;
  if v_vale.anulado then
    raise exception 'Este vale ya está anulado.';
  end if;

  update plantas_vales set
    anulado          = true,
    anulado_en       = now(),
    anulado_por      = auth.email(),
    motivo_anulacion = btrim(p_motivo)
  where id = p_vale_id
  returning * into v_vale;

  if v_vale.tipo_vale in ('ingreso_arido', 'egreso_arido') then
    -- El material de un ingreso vive en plantas_ingresos (plantas_vales.material
    -- solo se completa en los egresos).
    v_material_id := plantas_buscar_material_id(coalesce(
      (select material from plantas_ingresos where vale_id = p_vale_id limit 1), v_vale.material
    ));
    perform plantas_recalcular_stock_vale(
      p_vale_id, v_material_id, 0, null, null, 'Anulación de vale #' || plantas_etiqueta_vale(v_vale) || ': ' || btrim(p_motivo)
    );
    update plantas_ingresos set anulado = true where vale_id = p_vale_id;
  end if;

  insert into plantas_vales_historial (vale_id, accion, pedido_anterior_id, pedido_nuevo_id, motivo, usuario_email)
  values (p_vale_id, 'anulacion', v_vale.pedido_id, v_vale.pedido_id, btrim(p_motivo), auth.email());

  perform plantas_auditar_vale('ANULAR', p_vale_id, btrim(p_motivo), v_aud_antes);

  return v_vale;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 5. Proveedores: unificar los nombres históricos con el catálogo
-- ---------------------------------------------------------------------------
do $prov$
declare
  v_ingresos int; v_movs int;
begin
  update plantas_ingresos i
     set proveedor = p.nombre
    from plantas_proveedores p
   where lower(btrim(i.proveedor)) = lower(btrim(p.nombre)) and i.proveedor <> p.nombre;
  get diagnostics v_ingresos = row_count;

  update plantas_stock_movimientos m
     set origen = p.nombre
    from plantas_proveedores p
   where m.tipo in ('ingreso_proveedor', 'recalculo_bascula')
     and lower(btrim(m.origen)) = lower(btrim(p.nombre)) and m.origen <> p.nombre;
  get diagnostics v_movs = row_count;

  perform plantas_auditar(
    'CORREGIR', 'maestros', 'proveedor', 'migracion-63',
    'Unificación de nombres de proveedores',
    'Migración 63: el nombre del proveedor queda como figura en el catálogo',
    null,
    jsonb_build_object('ingresos_renombrados', v_ingresos, 'movimientos_de_stock_renombrados', v_movs)
  );
end;
$prov$;

-- ---------------------------------------------------------------------------
-- 6. Vales I-614, I-717, I-718: el historial de stock refleja la corrección,
--    el saldo NO cambia (el relevamiento del 09/10/2026 ya lo había absorbido)
-- ---------------------------------------------------------------------------
do $datos$
declare
  r record;
  v_objetivo numeric; v_aplicado numeric; v_delta numeric; v_total_antes numeric;
begin
  select sum(cantidad_kg) into v_total_antes from plantas_stock;

  for r in
    select v.id as vale_id, v.anulado, v.numero_vale_arido, i.id as ingreso_id, i.cantidad, i.proveedor,
           i.numero_remito, plantas_buscar_material_id(i.material) as material_id
      from plantas_vales v join plantas_ingresos i on i.vale_id = v.id
     where v.tipo_vale = 'ingreso_arido' and v.numero_vale_arido in (614, 717, 718)
  loop
    v_objetivo := case when r.anulado then 0 else r.cantidad * 1000 end;
    select coalesce(sum(cantidad_kg), 0) into v_aplicado
      from plantas_stock_movimientos
     where vale_id = r.vale_id and material_id = r.material_id
       and tipo in ('ingreso_proveedor', 'egreso_arido', 'recalculo_bascula');
    v_delta := v_objetivo - v_aplicado;
    if v_delta = 0 then
      continue;
    end if;

    insert into plantas_stock_movimientos (material_id, tipo, cantidad_kg, origen, numero_remito, vale_id, ingreso_id, observaciones, responsable_email)
    values (r.material_id, 'recalculo_bascula', v_delta, r.proveedor, r.numero_remito, r.vale_id, r.ingreso_id,
            'Migración 63: corrección del vale #I-' || lpad(r.numero_vale_arido::text, 5, '0')
            || ' que no había movido stock al editarlo/anularlo', 'sistema (SQL)');

    insert into plantas_stock_movimientos (material_id, tipo, cantidad_kg, origen, observaciones, responsable_email)
    values (r.material_id, 'ajuste', -v_delta, 'Compensación migración 63',
            'El relevamiento del 09/10/2026 ya había absorbido el error del vale #I-' || lpad(r.numero_vale_arido::text, 5, '0')
            || ': el saldo no cambia', 'sistema (SQL)');

    perform plantas_auditar(
      'CORREGIR', 'bascula', 'vale', r.vale_id::text,
      'Vale I-' || lpad(r.numero_vale_arido::text, 5, '0') || ' — historial de stock',
      'Migración 63: la edición/anulación no había movido stock; se registra el recálculo sin cambiar el saldo (ya corregido por el relevamiento del 09/10/2026)',
      jsonb_build_object('aplicado_al_vale_kg', v_aplicado),
      jsonb_build_object('aplicado_al_vale_kg', v_objetivo)
    );
  end loop;

  if (select sum(cantidad_kg) from plantas_stock) is distinct from v_total_antes then
    raise exception 'MIG63: el saldo de stock cambió y no debía';
  end if;
end;
$datos$;

-- ---------------------------------------------------------------------------
-- Chequeos finales
-- ---------------------------------------------------------------------------
do $chk$
declare
  v_mal text;
begin
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'corregir_vale_bascula') <> 1 then
    raise exception 'MIG63: corregir_vale_bascula quedó duplicada';
  end if;
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('corregir_vale_bascula', 'anular_vale_bascula')
     and (has_function_privilege('anon', p.oid, 'execute')
          or not has_function_privilege('authenticated', p.oid, 'execute')
          or not p.prosecdef);
  if v_mal is not null then
    raise exception 'MIG63: permisos alterados en: %', v_mal;
  end if;
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('plantas_validar_cantidad_remito', 'plantas_trg_ingresos_normalizar')
     and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'));
  if v_mal is not null then
    raise exception 'MIG63: helper expuesto: %', v_mal;
  end if;
  if exists (
    select 1 from plantas_ingresos i join plantas_proveedores p on lower(btrim(i.proveedor)) = lower(btrim(p.nombre))
     where i.proveedor <> p.nombre
  ) then
    raise exception 'MIG63: quedaron ingresos con el nombre de proveedor sin unificar';
  end if;
  if exists (
    select 1 from plantas_vales v join plantas_ingresos i on i.vale_id = v.id
     where v.numero_vale_arido in (614, 717, 718)
       and (select coalesce(sum(cantidad_kg), 0) from plantas_stock_movimientos m
             where m.vale_id = v.id and m.tipo in ('ingreso_proveedor', 'recalculo_bascula'))
           <> case when v.anulado then 0 else i.cantidad * 1000 end
  ) then
    raise exception 'MIG63: los vales 614/717/718 no quedaron reconciliados';
  end if;
end;
$chk$;
