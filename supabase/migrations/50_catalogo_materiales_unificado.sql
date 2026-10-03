-- ============================================================================
-- Migración 50: catálogo de materiales unificado — un solo nombre por material
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido de Federico (2026-10-02): lista oficial de nombres. Cada material
-- tiene UN nombre y todo el sistema lo usa igual (fórmulas, ingresos de
-- proveedores, vales de báscula). Decisiones:
--   - 13 materiales oficiales: 0/6, 6/20, 6/12, 0/3, FILLER, ARENA, CEMENTO,
--     ADITIVO, 10/30, ASFALTO CA30, FUEL OIL, 12/20, AM3 AUTOVIA.
--   - ASFALTO AM3 sigue como material propio (no se fusiona con AM3 AUTOVIA).
--   - AGUA y PURGUE quedan en el catálogo, sin control de stock (como hoy).
--   - GAS-OIL, FRESADO y CAL quedan en el catálogo, sin control de stock: no
--     suman ni descuentan.
--   - Fórmula "HORMIGON  H-13": sus 6 insumos pasan a los nombres oficiales.
--   - Se unifica el texto de material del historial de ingresos y vales.
--
-- Qué cambia:
--   1) Respaldo del estado anterior en plantas_respaldo_mig50 (para revertir).
--   2) Renombra 12 materiales del catálogo. Los IDs no cambian: plantas_stock
--      y plantas_stock_movimientos apuntan por material_id, no se tocan.
--   3) controla_stock = false en GAS-OIL, FRESADO y CAL.
--   4) Insumos de todas las fórmulas, plantas_ingresos.material y
--      plantas_vales.material reescritos al nombre oficial exacto.
--   5) "No se toca más":
--      - plantas_ingresos.material y plantas_vales.material: FK a
--        plantas_materiales(nombre) ON UPDATE CASCADE + trigger que lleva el
--        texto al nombre exacto del catálogo (sin importar mayúsculas) o
--        rechaza si el material no existe.
--      - plantas_formulas.insumos: mismo trigger de normalización/rechazo, y
--        renombrar un material del catálogo reescribe sus fórmulas.
--   6) plantas_aplicar_movimiento_stock() no mueve stock de un material con
--      controla_stock = false (hasta hoy solo el movimiento manual lo
--      respetaba; báscula y despachos lo ignoraban).
--
-- Reversible: el respaldo guarda nombre/controla_stock de los 19 materiales,
-- los insumos de las 21 fórmulas y el material de ingresos/vales tal como
-- estaban. No toca cantidades, stock ni movimientos.
-- ============================================================================

-- 1) Respaldo --------------------------------------------------------------
create table plantas_respaldo_mig50 (
  tabla   text  not null,
  fila_id text  not null,
  datos   jsonb not null,
  creado  timestamptz not null default now(),
  primary key (tabla, fila_id)
);
alter table plantas_respaldo_mig50 enable row level security;
revoke all on plantas_respaldo_mig50 from public, anon, authenticated;

insert into plantas_respaldo_mig50 (tabla, fila_id, datos)
select 'plantas_materiales', id::text, jsonb_build_object('nombre', nombre, 'controla_stock', controla_stock)
from plantas_materiales;
insert into plantas_respaldo_mig50 (tabla, fila_id, datos)
select 'plantas_formulas', id::text, jsonb_build_object('insumos', insumos)
from plantas_formulas;
insert into plantas_respaldo_mig50 (tabla, fila_id, datos)
select 'plantas_ingresos', id::text, jsonb_build_object('material', material)
from plantas_ingresos;
insert into plantas_respaldo_mig50 (tabla, fila_id, datos)
select 'plantas_vales', id::text, jsonb_build_object('material', material)
from plantas_vales where material is not null;

-- 2) Equivalencias: variante (minúsculas, sin espacios en los bordes) -> oficial
create temp table mig50_alias (variante text primary key, oficial text not null);
insert into mig50_alias (variante, oficial) values
  ('arena 0/6', '0/6'),            ('arena 0-6', '0/6'),
  ('piedra 6/20', '6/20'),         ('piedra 6-20', '6/20'),
  ('piedra 6/12', '6/12'),
  ('arena 0/3', '0/3'),
  ('arena silicia', 'ARENA'),      ('arena silicea', 'ARENA'),
  ('cemento cpc 40', 'CEMENTO'),   ('cemento cp 40', 'CEMENTO'),
  ('add plas', 'ADITIVO'),         ('ad plas', 'ADITIVO'),
  ('piedra 10/30', '10/30'),       ('piedra 10-30', '10/30'),
  ('fuel-oil', 'FUEL OIL'),
  ('piedra 12/20', '12/20'),
  ('asfalto am3 (autovia)', 'AM3 AUTOVIA');

-- Renombra el catálogo (los que no figuran en el alias conservan su nombre).
update plantas_materiales m
   set nombre = a.oficial
  from mig50_alias a
 where a.variante = lower(btrim(m.nombre));

-- 3) Sin control de stock
update plantas_materiales set controla_stock = false
 where nombre in ('GAS-OIL', 'FRESADO', 'CAL');

-- 4) Nombre oficial exacto del catálogo para un texto cualquiera
--    (alias conocido o coincidencia sin importar mayúsculas/espacios).
create or replace function plantas_nombre_material_oficial(p_nombre text)
returns text
language sql
stable
set search_path = public
as $$
  select nombre from plantas_materiales
   where lower(btrim(nombre)) = lower(btrim(coalesce(p_nombre, '')))
   limit 1;
$$;
revoke execute on function plantas_nombre_material_oficial(text) from public, anon, authenticated;

-- Fórmulas: cada insumo al nombre oficial (alias de la migración o catálogo).
update plantas_formulas f
   set insumos = (
     select jsonb_agg(
              jsonb_set(e.i, '{material}', to_jsonb(coalesce(
                a.oficial, plantas_nombre_material_oficial(e.i->>'material'), e.i->>'material')))
              order by e.ord)
       from jsonb_array_elements(f.insumos) with ordinality as e(i, ord)
       left join mig50_alias a on a.variante = lower(btrim(e.i->>'material'))
   )
 where jsonb_array_length(coalesce(f.insumos, '[]'::jsonb)) > 0;

update plantas_ingresos i
   set material = coalesce(a.oficial, plantas_nombre_material_oficial(i.material), i.material)
  from (select id, material from plantas_ingresos) x
  left join mig50_alias a on a.variante = lower(btrim(x.material))
 where x.id = i.id;

update plantas_vales v
   set material = coalesce(a.oficial, plantas_nombre_material_oficial(v.material), v.material)
  from (select id, material from plantas_vales where material is not null) x
  left join mig50_alias a on a.variante = lower(btrim(x.material))
 where x.id = v.id;

drop table mig50_alias;

-- 5) No se toca más ---------------------------------------------------------

-- Ingresos y vales: el texto se lleva al nombre exacto del catálogo, o se
-- rechaza con un mensaje claro (la FK de abajo sola daría un error críptico).
create or replace function plantas_trg_material_oficial()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_oficial text;
begin
  if new.material is null then
    return new;
  end if;
  v_oficial := plantas_nombre_material_oficial(new.material);
  if v_oficial is null then
    raise exception 'El material "%" no está en el catálogo de materiales (Maestros → Materiales).', new.material;
  end if;
  new.material := v_oficial;
  return new;
end;
$$;
revoke execute on function plantas_trg_material_oficial() from public, anon, authenticated;

create trigger plantas_ingresos_material_oficial
  before insert or update of material on plantas_ingresos
  for each row execute function plantas_trg_material_oficial();
create trigger plantas_vales_material_oficial
  before insert or update of material on plantas_vales
  for each row execute function plantas_trg_material_oficial();

alter table plantas_ingresos
  add constraint plantas_ingresos_material_fkey
  foreign key (material) references plantas_materiales (nombre) on update cascade;
alter table plantas_vales
  add constraint plantas_vales_material_fkey
  foreign key (material) references plantas_materiales (nombre) on update cascade;

-- Fórmulas: cada insumo al nombre exacto del catálogo, o se rechaza.
create or replace function plantas_trg_formula_insumos_oficiales()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_insumo  jsonb;
  v_oficial text;
  v_nuevos  jsonb := '[]'::jsonb;
begin
  if new.insumos is null or jsonb_typeof(new.insumos) <> 'array' then
    return new;
  end if;
  for v_insumo in select * from jsonb_array_elements(new.insumos)
  loop
    v_oficial := plantas_nombre_material_oficial(v_insumo->>'material');
    if v_oficial is null then
      raise exception 'El insumo "%" de la fórmula "%" no está en el catálogo de materiales (Maestros → Materiales).',
        coalesce(v_insumo->>'material', ''), coalesce(new.nombre, '');
    end if;
    v_nuevos := v_nuevos || jsonb_build_array(jsonb_set(v_insumo, '{material}', to_jsonb(v_oficial)));
  end loop;
  new.insumos := v_nuevos;
  return new;
end;
$$;
revoke execute on function plantas_trg_formula_insumos_oficiales() from public, anon, authenticated;

create trigger plantas_formulas_insumos_oficiales
  before insert or update of insumos on plantas_formulas
  for each row execute function plantas_trg_formula_insumos_oficiales();

-- Renombrar un material del catálogo reescribe las fórmulas que lo usan
-- (ingresos y vales ya siguen por la FK ON UPDATE CASCADE).
create or replace function plantas_trg_material_renombrado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update plantas_formulas f
     set insumos = (
       select jsonb_agg(
                case when lower(btrim(e.i->>'material')) = lower(btrim(old.nombre))
                     then jsonb_set(e.i, '{material}', to_jsonb(new.nombre))
                     else e.i end
                order by e.ord)
         from jsonb_array_elements(f.insumos) with ordinality as e(i, ord)
     )
   where exists (
     select 1 from jsonb_array_elements(coalesce(f.insumos, '[]'::jsonb)) x
      where lower(btrim(x->>'material')) = lower(btrim(old.nombre))
   );
  return new;
end;
$$;
revoke execute on function plantas_trg_material_renombrado() from public, anon, authenticated;

create trigger plantas_materiales_renombrado
  after update of nombre on plantas_materiales
  for each row when (old.nombre is distinct from new.nombre)
  execute function plantas_trg_material_renombrado();

-- 6) controla_stock = false no mueve stock ---------------------------------
-- Partiendo de la definición real de producción (pg_get_functiondef,
-- 2026-10-02); el único cambio es el chequeo de controla_stock.
create or replace function public.plantas_aplicar_movimiento_stock(p_material_id uuid, p_tipo text, p_cantidad_kg numeric, p_origen text default null::text, p_numero_remito text default null::text, p_pedido_id uuid default null::uuid, p_vale_id uuid default null::uuid, p_ingreso_id uuid default null::uuid, p_observaciones text default null::text)
 returns plantas_stock_movimientos
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_mov            plantas_stock_movimientos;
  v_actual         numeric;
  v_nuevo          numeric;
  v_delta_aplicado numeric;
  v_observaciones  text := p_observaciones;
begin
  if p_cantidad_kg = 0 or p_material_id is null then
    return null;
  end if;

  -- Migración 50: materiales sin control de stock (AGUA, PURGUE, GAS-OIL,
  -- FRESADO, CAL) no suman ni descuentan.
  if not exists (select 1 from plantas_materiales where id = p_material_id and controla_stock) then
    return null;
  end if;

  insert into plantas_stock (material_id, cantidad_kg)
  values (p_material_id, 0)
  on conflict (material_id) do nothing;

  select cantidad_kg into v_actual from plantas_stock where material_id = p_material_id for update;

  v_nuevo := greatest(0, v_actual + p_cantidad_kg);
  v_delta_aplicado := v_nuevo - v_actual;

  if v_delta_aplicado = 0 then
    return null;
  end if;

  if v_delta_aplicado <> p_cantidad_kg then
    v_observaciones := coalesce(v_observaciones || ' — ', '')
      || format('consumo solicitado %s kg, aplicado %s kg (stock insuficiente, piso en 0)', p_cantidad_kg, v_delta_aplicado);
  end if;

  update plantas_stock
    set cantidad_kg = v_nuevo,
        actualizado_en = now()
    where material_id = p_material_id;

  insert into plantas_stock_movimientos (
    material_id, tipo, cantidad_kg, origen, numero_remito,
    pedido_id, vale_id, ingreso_id, observaciones, usuario_id, responsable_email
  ) values (
    p_material_id, p_tipo, v_delta_aplicado, p_origen, p_numero_remito,
    p_pedido_id, p_vale_id, p_ingreso_id, v_observaciones, auth.uid(), auth.email()
  )
  returning * into v_mov;

  return v_mov;
end;
$function$;
-- Sigue interno (migración 43): sin EXECUTE para anon/authenticated.
revoke execute on function public.plantas_aplicar_movimiento_stock(uuid, text, numeric, text, text, uuid, uuid, uuid, text) from public, anon, authenticated;

-- Controles finales: cualquier falla cancela toda la migración -------------
do $chk$
declare
  v_n int;
begin
  select count(*) into v_n from plantas_materiales;
  if v_n <> 19 then raise exception 'MIG50: se esperaban 19 materiales, hay %', v_n; end if;

  select count(*) into v_n from plantas_materiales
   where nombre in ('0/6','6/20','6/12','0/3','FILLER','ARENA','CEMENTO','ADITIVO','10/30',
                    'ASFALTO CA30','FUEL OIL','12/20','AM3 AUTOVIA',
                    'ASFALTO AM3','AGUA','PURGUE','GAS-OIL','FRESADO','CAL');
  if v_n <> 19 then raise exception 'MIG50: el catálogo no quedó con los 19 nombres esperados (%)', v_n; end if;

  select count(*) into v_n from plantas_materiales where not controla_stock;
  if v_n <> 5 then raise exception 'MIG50: se esperaban 5 materiales sin control de stock, hay %', v_n; end if;

  select count(*) into v_n
    from plantas_formulas f, jsonb_array_elements(coalesce(f.insumos, '[]'::jsonb)) i
   where not exists (select 1 from plantas_materiales m where m.nombre = i->>'material');
  if v_n > 0 then raise exception 'MIG50: % insumos de fórmulas fuera del catálogo', v_n; end if;

  select count(*) into v_n from plantas_ingresos i
   where not exists (select 1 from plantas_materiales m where m.nombre = i.material);
  if v_n > 0 then raise exception 'MIG50: % ingresos con material fuera del catálogo', v_n; end if;
end;
$chk$;
