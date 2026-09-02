-- ============================================================================
-- MIGRACIÓN DE HISTORIAL v2 — desde kv_store (legado) hacia plantas_* (v2)
--
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Corrección importante respecto de `supabase/scripts/migracion_historial_borrador.sql`
-- (que asumía un origen externo desconocido, "staging_legado_*"): el legado
-- vive en ESTE MISMO proyecto, dentro de una tabla genérica `kv_store(key
-- text, value jsonb, updated_at timestamptz)`. No hay tablas `vt_*` reales —
-- son claves dentro de esa tabla (`vt_p9`, `vt_s9`, `vt_f9`, `vt_vales9`,
-- `vt_ingaridos9`, `vt_egaridos9`, `vt_m9`, `vt_usuarios9`, `vt_maestros9`).
-- Confirmado en vivo, sesión 2026-09-01, leyendo su contenido real (no
-- inventado): 182 pedidos, 19 fórmulas, 382 vales, 499 ingresos de áridos,
-- 3 egresos de áridos, 678 movimientos de stock, 15 usuarios, 14 obras
-- propias, 18 materiales, 8 proveedores, 32+23 patentes.
--
-- ¡¡¡ ESTO SIGUE SIENDO UN BORRADOR PARA CORRER A MANO !!! No numerado junto
-- a supabase/migrations/*.sql (no es schema, es carga de datos — memory/
-- procedimientos.md, protocolo de aviso previo, aplica con más fuerza acá).
-- Corre entero dentro de una transacción con ROLLBACK por defecto: la
-- primera vez que se ejecute este archivo NO debe persistir nada. Revisar
-- los conteos de la sección 9 y recién ahí cambiar `rollback;` por `commit;`
-- a mano.
--
-- Decisiones de esta pasada (aprobadas por Federico, sesión 2026-09-01):
--   1. `flota_obras` (y cualquier otra tabla `flota_*`) es SOLO LECTURA para
--      este script — instrucción explícita de Federico: nunca insertar,
--      modificar ni tocar esas tablas, son del sistema de flota. Las 13
--      obras reales del legado (excluida "PRUEBAS MEZCLA ASFALTO", obra de
--      prueba del propio legado) se RECONCILIAN por lectura contra las 22
--      filas ya existentes de `flota_obras`, nunca se crean filas nuevas:
--        - 9 matchean exacto por `codigo` (incluye "Predio Vialtec"→PV-01→
--          "Planta Asfalto Marini VT" y "BARRIO ALTOS DEL BARRANCO"→BAR-01→
--          "El Barranco", ambigüedades que habían quedado sin resolver en
--          la Fase 2 de Usuarios).
--        - 3 matchean por nombre equivalente pero código distinto o
--          ausente en el legado — confirmado a mano contra flota_obras,
--          se mapean con una lista explícita (ver sección 1 del script):
--          "Barrio La Barranca - Campana"(o1) → id 10 "La Barranca-Campana"
--          (código real BRC-01, el legado trae CAM-01); "B°SOLARES DEL
--          TALAR"(yjscoq2) → id 26 "Solares del Talar" (código real SDT-01,
--          el legado trae SLT-01); "PLANTA A° MARINI"(f4stkay) → id 2
--          "Planta Asfalto Marini VT" (mismo predio físico que "Predio
--          Vialtec", entrada duplicada en el legado sin código — 0 pedidos
--          la referencian, impacto nulo).
--        - 1 (`cjlmpvj`, "Municipalidad exaltacion de la cruz") NO tiene
--          ninguna fila equivalente en `flota_obras` — no se crea (no
--          podemos escribir ahí). Los 3 pedidos que la referencian quedan
--          con `obra_id = null`, dato preservado igual en `datos_legados`.
--          Si Federico quiere esa obra resuelta, alguien con acceso al
--          sistema de flota tiene que crearla ahí primero; después
--          alcanza un UPDATE puntual sobre esos 3 pedidos.
--   2. `plantas_usuarios_roles` suma columna `telefono`. Los 15 usuarios
--      reales de `vt_usuarios9` ya tienen roles que matchean 1:1 nuestro
--      enum (no hizo falta ningún fallback a 'encargado' en la práctica,
--      pero el CASE defensivo queda igual). Se cargan `obra_ids` reales
--      (mapeados vía el punto 1) y `ver_todas_obras=false` para quien tenga
--      obras asignadas — esto SÍ activa la restricción real por obra que
--      había quedado pospuesta en la Fase 2. `angel.moreira@vialtec.com.ar`
--      (plantista_hormigon) y `juan.heinrich@vialtec.com.ar` (encargado,
--      inactivo) no tenían fila todavía (no están en flota_usuarios_email)
--      — se crean acá. El campo `password` de `vt_usuarios9` NUNCA se lee
--      ni se migra a ningún lado, ni siquiera a un jsonb de auditoría.
--   3. `vt_m9` (678 movimientos) → `plantas_stock_movimientos`:
--        'ingreso_aridos' Y 'ingreso' (mismo significado real, dos formatos
--          del legado) -> 'ingreso_proveedor'
--        'egreso_aridos' -> 'egreso_arido' (NO 'egreso_despacho' como se
--          había indicado en la instrucción original — son egresos directos
--          de áridos crudos, ej. consumo de Fuel Oil, no consumo por
--          fórmula de un despacho; 'egreso_arido' es el tipo semánticamente
--          correcto que ya existe en el enum. Avisar si se prefiere forzar
--          'egreso_despacho' igual.)
--        'salida' -> 'egreso_manual' (motivo/remito/responsable manual,
--          matchea ese tipo exacto — no lo mandé al catch-all 'ajuste')
--        'relevamiento' -> 'ajuste' (instrucción original, sin cambios)
--        cualquier otro tipo no listado arriba -> 'ajuste' (catch-all
--        pedido explícito)
--
-- Fuera de alcance de esta pasada, a propósito:
--   - `plantas_cargas_asfalto`: el array `camiones` de un pedido de asfalto
--     trae `nroVale: null` en todas las muestras reales que vi (a
--     diferencia de hormigón, que sí trae `nroRemito` siempre completo) —
--     `plantas_cargas_asfalto.numero_vale` es NOT NULL, así que no hay con
--     qué completarlo sin inventar un valor. El detalle auditable de
--     despachos de asfalto ya queda cubierto por `plantas_vales` (migrado
--     completo, con numero real). Si más adelante aparece de dónde sacar
--     el vale de cada camión de asfalto, se suma en una pasada aparte.
--   - `stock_minimo_kg`/`stock_maximo_kg` de `plantas_materiales`: el
--     legado tiene un campo `stockMinimo` pero está vacío ("") en el 100%
--     de los 18 materiales reales — no hay ningún valor real para migrar.
--     `stockMaximo` no existe como campo en ningún lado del legado (cierra
--     en negativo la pregunta abierta del relevamiento: "¿dónde se
--     configura el máximo?" — no se configura, no existe). Quedan NULL,
--     Federico los carga a mano en Maestros → Materiales cuando quiera.
--   - `plantas_clientes_frecuentes`: no existe esa tabla todavía (gap #3
--     del relevamiento) — los 7 `vt_maestros9.clientes` no se migran como
--     catálogo aparte; igual quedan preservados como texto libre dentro de
--     `plantas_pedidos.cliente_externo` en cada pedido de venta migrado.
--   - `fecha_programada_anterior`/`nueva` en el historial de pedidos
--     postergados: igual que el borrador anterior, requeriría reconstruir
--     con lag()/lead() sobre el propio array `historial` de cada pedido.
--     Queda NULL en los eventos migrados — no bloquea nada, es solo un dato
--     de contexto que se pierde en los históricos (los postergados nuevos,
--     hechos con `postergar_pedido()`, sí lo guardan bien).
--   - `plantas_stock.cantidad_kg` final: se setea DIRECTO desde `vt_s9`
--     (el estado actual real, snapshot vivo), NO como la suma de los
--     movimientos migrados de `plantas_stock_movimientos`. Motivo: el
--     consumo de stock por despacho (fórmula × cantidadReal) NUNCA se
--     registró como una fila de movimiento en el legado (`vt_m9` no tiene
--     ningún tipo relacionado a despachos) — está "horneado" en el número
--     final de `vt_s9`, pero no hay forma de reconstruirlo evento por
--     evento. Los movimientos migrados sirven como auditoría histórica de
--     ingresos/egresos/ajustes reales, pero deliberadamente NO van a sumar
--     exacto contra el stock final — no es un bug del script, es un límite
--     real de qué guardaba el legado.
-- ============================================================================

begin;

set local timezone to 'America/Argentina/Buenos_Aires';

-- ----------------------------------------------------------------------------
-- 1) Obras: reconciliar vt_maestros9.obras (13, sin la de pruebas) contra
--    flota_obras — SOLO LECTURA, nunca se inserta/modifica flota_obras.
-- ----------------------------------------------------------------------------

create temporary table stg_obras_legado on commit drop as
select
  o ->> 'id'                       as obra_id_legado,
  nullif(trim(o ->> 'codigo'), '') as codigo,
  trim(o ->> 'nombre')             as nombre
from kv_store, jsonb_array_elements(value -> 'obras') as o
where key = 'vt_maestros9';

-- Obra de prueba del propio legado — no existe ni debe existir en
-- flota_obras. Los pedidos que la referencian quedan con obra_id null.
delete from stg_obras_legado where codigo = 'PRUEBAS-01';

create temporary table stg_obras_mapeadas on commit drop as
select sl.obra_id_legado, sl.codigo, sl.nombre, fo.id as flota_obra_id
from stg_obras_legado sl
left join flota_obras fo
  on fo.codigo is not null and upper(trim(fo.codigo)) = upper(sl.codigo);

-- Fallback por nombre exacto (normalizado) contra flota_obras.
update stg_obras_mapeadas som
  set flota_obra_id = fo.id
  from flota_obras fo
  where som.flota_obra_id is null
    and upper(trim(fo.nombre)) = upper(som.nombre);

-- Overrides manuales confirmados a mano (nombre/código no coinciden
-- exacto, pero son la misma obra real en flota_obras) — ver detalle en el
-- encabezado, punto 1. Ninguno inserta fila nueva, solo resuelve el id ya
-- existente. "cjlmpvj" (Municipalidad exaltacion de la cruz) queda afuera
-- a propósito: no tiene equivalente en flota_obras.
update stg_obras_mapeadas som
  set flota_obra_id = ov.flota_obra_id
  from (values
    ('o1',      10), -- Barrio La Barranca - Campana -> La Barranca-Campana (BRC-01)
    ('yjscoq2', 26), -- B°SOLARES DEL TALAR -> Solares del Talar (SDT-01)
    ('f4stkay',  2)  -- PLANTA A° MARINI -> Planta Asfalto Marini VT (mismo predio que Predio Vialtec)
  ) as ov(obra_id_legado, flota_obra_id)
  where som.obra_id_legado = ov.obra_id_legado
    and som.flota_obra_id is null;

-- ----------------------------------------------------------------------------
-- 2) plantas_usuarios_roles: columna telefono + datos reales de vt_usuarios9 (15)
-- ----------------------------------------------------------------------------

alter table plantas_usuarios_roles add column if not exists telefono text;

create temporary table stg_usuarios_legado on commit drop as
select
  u ->> 'email'                            as email,
  u ->> 'rol'                              as rol_legado,
  coalesce((u ->> 'activo')::boolean, true) as activo,
  nullif(u ->> 'telefono', '')             as telefono,
  coalesce(u -> 'obraIds', '[]'::jsonb)    as obra_ids_legado
from kv_store, jsonb_array_elements(value) as u
where key = 'vt_usuarios9';

insert into plantas_usuarios_roles (email, rol, ver_todas_obras, ver_ventas, obra_ids, activo, telefono)
select
  sul.email,
  case when sul.rol_legado in ('admin','plantista','encargado','supervisor','balancero','gerencia','plantista_hormigon')
       then sul.rol_legado
       else 'encargado' end,
  (jsonb_array_length(sul.obra_ids_legado) = 0),
  case when sul.rol_legado in ('admin','plantista','gerencia','encargado') then true else false end,
  coalesce((
    select array_agg(distinct som.flota_obra_id)
    from jsonb_array_elements_text(sul.obra_ids_legado) as oid
    join stg_obras_mapeadas som on som.obra_id_legado = oid
    where som.flota_obra_id is not null
  ), '{}'),
  sul.activo,
  sul.telefono
from stg_usuarios_legado sul
on conflict (email) do update set
  rol             = excluded.rol,
  ver_todas_obras = excluded.ver_todas_obras,
  obra_ids        = excluded.obra_ids,
  activo          = excluded.activo,
  telefono        = coalesce(excluded.telefono, plantas_usuarios_roles.telefono);
  -- ver_ventas NO se pisa en el conflicto a propósito: ya quedó seteado
  -- razonable en las migraciones 18/19 para los usuarios ya existentes.

-- ----------------------------------------------------------------------------
-- 3) Catálogos de Maestros
-- ----------------------------------------------------------------------------

insert into plantas_materiales (nombre, unidad, categoria, activo)
select trim(m ->> 'nombre'), nullif(m ->> 'unidad', ''), nullif(m ->> 'categoria', ''), true
from kv_store, jsonb_array_elements(value -> 'materiales') as m
where key = 'vt_maestros9'
on conflict (nombre) do nothing;

update plantas_materiales set controla_stock = false
where lower(trim(nombre)) in ('agua', 'purgue');

insert into plantas_proveedores (nombre, material_principal, activo)
select trim(p ->> 'nombre'), nullif(trim(p ->> 'material'), ''), true
from kv_store, jsonb_array_elements(value -> 'proveedores') as p
where key = 'vt_maestros9'
and not exists (select 1 from plantas_proveedores pp where pp.nombre = trim(p ->> 'nombre'));

-- notas:
--   - `tara` en vt_maestros9.patentes/patenteExternas viene con coma decimal
--     (ej. "13,62"), no punto — replace() antes del cast a numeric.
--   - `patente` se normaliza a mayúsculas: hay 4 casos reales del mismo
--     vehículo duplicado con casing distinto entre patentes/patenteExternas
--     (ej. "Emh-928" vs "EMH-928") — plantas_patentes.patente es UNIQUE
--     case-sensitive, así que sin normalizar quedarían 2 filas para el
--     mismo camión. on conflict do nothing en vez de not exists por lo
--     mismo (dedupe case-insensitive real).
insert into plantas_patentes (patente, tipo_camion, tara, chofer_habitual, es_externa, activo)
select upper(trim(p ->> 'nombre')), nullif(p ->> 'tipo', ''), nullif(replace(p ->> 'tara', ',', '.'), '')::numeric, nullif(p ->> 'chofer', ''), false, true
from kv_store, jsonb_array_elements(value -> 'patentes') as p
where key = 'vt_maestros9'
on conflict (patente) do nothing;

insert into plantas_patentes (patente, tipo_camion, tara, chofer_habitual, es_externa, activo)
select upper(trim(p ->> 'nombre')), nullif(p ->> 'tipo', ''), nullif(replace(p ->> 'tara', ',', '.'), '')::numeric, nullif(p ->> 'chofer', ''), true, true
from kv_store, jsonb_array_elements(value -> 'patenteExternas') as p
where key = 'vt_maestros9'
on conflict (patente) do nothing;

-- ----------------------------------------------------------------------------
-- 4) plantas_formulas (19) — se preserva el id legado en datos_legados, para
--    poder resolver formulaId de cada pedido por lookup exacto (no por
--    nombre, a diferencia del borrador anterior). datos_legados no existía
--    en esta tabla (a diferencia de plantas_pedidos/plantas_vales, que sí
--    la tienen) — se agrega acá, mismo patrón que `telefono` en la sección 2.
-- ----------------------------------------------------------------------------

alter table plantas_formulas add column if not exists datos_legados jsonb;

insert into plantas_formulas (nombre, tipo, unidad, activo, insumos, datos_legados)
select
  trim(f ->> 'nombre'),
  f ->> 'tipo',
  case f ->> 'unidad' when 'm³' then 'm3' else f ->> 'unidad' end,  -- plantas_formulas_unidad_check exige 'tn'/'m3', el legado trae 'm³' (con supíndice)
  true,
  coalesce((
    select jsonb_agg(jsonb_build_object(
      'material', ins ->> 'nombre',
      'unidad', ins ->> 'unidad',
      'cantidad', (ins ->> 'cantidad')::numeric
    ))
    from jsonb_array_elements(coalesce(f -> 'insumos', '[]'::jsonb)) as ins
  ), '[]'::jsonb),
  f
from kv_store, jsonb_array_elements(value) as f
where key = 'vt_f9'
and not exists (select 1 from plantas_formulas pf where pf.datos_legados ->> 'id' = f ->> 'id');

-- ----------------------------------------------------------------------------
-- 5) plantas_pedidos + plantas_pedidos_historial (182 pedidos)
-- ----------------------------------------------------------------------------

create temporary table stg_pedidos_legado on commit drop as
select
  p                     as raw,
  p ->> 'id'             as id_legado,
  p ->> 'obraId'         as obra_id_legado,
  p ->> 'formulaId'      as formula_id_legado
from kv_store, jsonb_array_elements(value) as p
where key = 'vt_p9';

insert into plantas_pedidos (
  obra_id, formula_id, tipo, cantidad_solicitada, cantidad_despachada,
  fecha_programada, estado, tipo_pedido, cliente_externo, encargado,
  observaciones, ubicacion, nro_remito_global, nro_vale_global,
  motivo, motivo_en, archivado, created_at, datos_legados
)
select
  som.flota_obra_id,
  pf.id,
  pf.tipo,
  nullif(sp.raw ->> 'cantidad', '')::numeric,
  nullif(sp.raw ->> 'cantidadReal', '')::numeric,
  nullif(sp.raw ->> 'fecha', '')::date,
  sp.raw ->> 'estado',                                  -- ya verificado: los 182 caen dentro del catálogo (solicitado/confirmado/despachado/postergado/cancelado)
  case when nullif(sp.raw ->> 'tipoPedido', '') = 'venta' then 'venta' else 'obra' end,  -- plantas_pedidos_tipo_pedido_check exige 'obra'/'venta'; el legado también trae 'interno' (22 casos, siempre con obraId real y clienteExterno vacío -> semánticamente 'obra') y null (91 casos, ídem -> 'obra')
  nullif(sp.raw ->> 'clienteExterno', ''),
  nullif(trim(sp.raw ->> 'encargado'), ''),
  nullif(sp.raw ->> 'notas', ''),
  nullif(sp.raw ->> 'ubicacion', ''),
  nullif(sp.raw ->> 'nroRemito', ''),
  nullif(sp.raw ->> 'nroVale', ''),
  nullif(sp.raw ->> 'motivo', ''),
  nullif(sp.raw ->> 'motivoEn', '')::timestamptz,
  false,
  coalesce(nullif(sp.raw ->> 'creadoEn', '')::timestamptz, now()),
  sp.raw
from stg_pedidos_legado sp
left join stg_obras_mapeadas som on som.obra_id_legado = sp.obra_id_legado
left join plantas_formulas pf on pf.datos_legados ->> 'id' = sp.formula_id_legado
where pf.id is not null                                  -- sin fórmula matcheada, no se inserta (revisar cola en sección 9)
and coalesce(nullif(sp.raw ->> 'cantidad', '')::numeric, 1) > 0  -- 1 pedido (wmcde37, cancelado) trae cantidad="-1" en el legado; cantidad_solicitada es NOT NULL + CHECK > 0, no hay valor real que migrar — se excluye, ver 9b
and not exists (select 1 from plantas_pedidos pp where pp.datos_legados ->> 'id' = sp.id_legado);

-- Idempotencia (fix 2026-09-01): sin el `not exists` de abajo, correr el
-- script dos veces duplicaría cada evento — `plantas_pedidos` sí está
-- guardado contra reinserción, pero esta tabla no tenía guarda propia.
insert into plantas_pedidos_historial (pedido_id, estado, fecha_evento, usuario_legado, motivo, datos_legados)
select
  pp.id,
  evento ->> 'estado',
  nullif(evento ->> 'fecha', '')::timestamptz,
  nullif(evento ->> 'usuario', ''),
  nullif(evento ->> 'motivo', ''),
  evento
from stg_pedidos_legado sp
join plantas_pedidos pp on pp.datos_legados ->> 'id' = sp.id_legado
cross join lateral jsonb_array_elements(coalesce(sp.raw -> 'historial', '[]'::jsonb)) as evento
where (evento ->> 'estado') in ('solicitado','confirmado','despachado','postergado','cancelado')
and not exists (
  select 1 from plantas_pedidos_historial pph
  where pph.pedido_id = pp.id and pph.datos_legados = evento
);

-- ----------------------------------------------------------------------------
-- 6) plantas_cargas_hormigon — desde el array `camiones` de cada pedido de
--    hormigón (nroRemito siempre presente en las muestras reales, a
--    diferencia de asfalto que trae nroVale=null — ver nota de alcance).
-- ----------------------------------------------------------------------------

-- Idempotencia (fix 2026-09-01): mismo patrón que plantas_formulas —
-- datos_legados no existía en esta tabla, se agrega para poder dedupear
-- por el objeto `camion` crudo (sin esto, correr el script dos veces
-- duplicaría cada carga).
alter table plantas_cargas_hormigon add column if not exists datos_legados jsonb;

insert into plantas_cargas_hormigon (pedido_id, obra_id, numero_remito, volumen_m3, patente_mixer, datos_legados)
select
  pp.id,
  pp.obra_id,
  nullif(camion ->> 'nroRemito', ''),
  (camion ->> 'cantidad')::numeric,
  nullif(camion ->> 'patente', ''),
  camion
from stg_pedidos_legado sp
join plantas_pedidos pp on pp.datos_legados ->> 'id' = sp.id_legado
join plantas_formulas pf on pf.id = pp.formula_id
cross join lateral jsonb_array_elements(coalesce(sp.raw -> 'camiones', '[]'::jsonb)) as camion
where pf.tipo = 'hormigon'
  and (camion ->> 'nroRemito') is not null and camion ->> 'nroRemito' <> ''
  and (camion ->> 'cantidad') is not null
  and not exists (
    select 1 from plantas_cargas_hormigon pch
    where pch.pedido_id = pp.id and pch.datos_legados = camion
  );

-- ----------------------------------------------------------------------------
-- 7) plantas_vales — asfalto (382, numero real preservado), ingreso_arido
--    (499, numero nuevo — el legado no numera estos) + plantas_ingresos,
--    egreso_arido (3, numero real preservado).
-- ----------------------------------------------------------------------------

insert into plantas_vales (
  numero_vale, tipo_vale, pedido_id, obra_id, patente, chofer,
  peso_bruto, tara, peso_neto, unidad, fecha_pesada, temperatura, datos_legados
)
overriding system value
select
  (v ->> 'numero')::bigint,
  'asfalto',
  pp.id,
  coalesce(pp.obra_id, som.flota_obra_id),
  nullif(v ->> 'patente', ''),
  nullif(v ->> 'chofer', ''),
  (v ->> 'pesoBruto')::numeric,
  (v ->> 'tara')::numeric,
  (v ->> 'pesoNeto')::numeric,
  'tn',
  ((v ->> 'fecha') || ' ' || coalesce(nullif(v ->> 'hora', ''), '00:00'))::timestamp
    at time zone 'America/Argentina/Buenos_Aires',
  nullif(v ->> 'temperatura', '')::numeric,
  v
from kv_store, jsonb_array_elements(value) as v
left join plantas_pedidos pp on pp.datos_legados ->> 'id' = v ->> 'pedidoId'
left join stg_obras_mapeadas som on som.nombre = trim(v ->> 'obra')  -- ventas externas: vale trae nombre de obra/cliente, no obraId
where key = 'vt_vales9'
and not exists (select 1 from plantas_vales pv where pv.numero_vale = (v ->> 'numero')::bigint);

-- egreso_arido (3, numero real preservado) — se inserta ANTES que
-- ingreso_arido a propósito (fix 2026-09-01: el orden original insertaba
-- ingreso_arido primero, asignando números nuevos vía nextval() mientras la
-- secuencia todavía estaba desincronizada de los números reales de asfalto
-- ya insertados arriba — nextval() habría repartido números que ya
-- ocupaba un vale real de asfalto, violando el unique de numero_vale.
-- Insertando también egreso_arido con sus números reales ANTES de
-- sincronizar, el setval() de abajo queda calculado sobre el máximo real
-- verdadero (asfalto + egreso), y recién ahí ingreso_arido reparte números
-- nuevos sin riesgo de colisión).
insert into plantas_vales (
  numero_vale, tipo_vale, obra_id, patente, chofer,
  peso_bruto, tara, peso_neto, unidad, fecha_pesada, material, datos_legados
)
overriding system value
select
  (e ->> 'numero')::bigint,
  'egreso_arido',
  som.flota_obra_id,
  nullif(e ->> 'patente', ''),
  nullif(e ->> 'chofer', ''),
  (e ->> 'pesoBruto')::numeric,
  (e ->> 'tara')::numeric,
  (e ->> 'pesoNeto')::numeric,
  'tn',
  ((e ->> 'fecha') || ' ' || coalesce(nullif(e ->> 'hora', ''), '00:00'))::timestamp
    at time zone 'America/Argentina/Buenos_Aires',
  nullif(e ->> 'material', ''),
  e
from kv_store, jsonb_array_elements(value) as e
left join stg_obras_mapeadas som on som.nombre = trim(e ->> 'destino')
where key = 'vt_egaridos9'
and not exists (select 1 from plantas_vales pv where pv.numero_vale = (e ->> 'numero')::bigint);

-- Sincroniza la secuencia al máximo real ya insertado (asfalto + egreso)
-- ANTES de que ingreso_arido reparta números nuevos vía nextval() — ver nota
-- arriba. `is_called=true` para que el próximo nextval() devuelva
-- max+1, no max otra vez.
select setval(
  pg_get_serial_sequence('plantas_vales', 'numero_vale'),
  (select max(numero_vale) from plantas_vales),
  true
);

create temporary table stg_ingaridos_legado on commit drop as
select i as raw
from kv_store, jsonb_array_elements(value) as i
where key = 'vt_ingaridos9';

-- El vale se crea primero: plantas_ingresos.vale_id es FK hacia
-- plantas_vales.id (el ingreso referencia al vale, no al revés — al revés
-- de como estaba armado antes de verificar el esquema real).
with insertados_vales as (
  insert into plantas_vales (numero_vale, tipo_vale, patente, peso_bruto, tara, peso_neto, unidad, fecha_pesada, datos_legados)
  overriding system value
  select
    nextval(pg_get_serial_sequence('plantas_vales', 'numero_vale')),  -- sin numero en el legado: se asigna uno nuevo, secuencia ya sincronizada arriba
    'ingreso_arido',
    nullif(sil.raw ->> 'patente', ''),
    (sil.raw ->> 'pesoBruto')::numeric,
    (sil.raw ->> 'tara')::numeric,
    (sil.raw ->> 'pesoNeto')::numeric,
    'tn',
    ((sil.raw ->> 'fecha') || ' ' || coalesce(nullif(sil.raw ->> 'hora', ''), '00:00'))::timestamp
      at time zone 'America/Argentina/Buenos_Aires',
    sil.raw
  from stg_ingaridos_legado sil
  where not exists (
    select 1 from plantas_ingresos pi
    where pi.numero_remito = nullif(sil.raw ->> 'remito', '')
      and pi.material = trim(sil.raw ->> 'material')
  )
  returning id, datos_legados
)
insert into plantas_ingresos (material, proveedor, numero_remito, cantidad, unidad, origen, vale_id, fecha_ingreso, observaciones)
select
  trim(iv.datos_legados ->> 'material'),
  trim(iv.datos_legados ->> 'proveedor'),
  nullif(iv.datos_legados ->> 'remito', ''),
  coalesce((iv.datos_legados ->> 'cantidadRemito')::numeric, (iv.datos_legados ->> 'pesoNeto')::numeric),
  'tn',
  'manual',                                              -- migrado del legado, no vino de nuestra báscula
  iv.id,
  ((iv.datos_legados ->> 'fecha') || ' ' || coalesce(nullif(iv.datos_legados ->> 'hora', ''), '00:00'))::timestamp
    at time zone 'America/Argentina/Buenos_Aires',
  nullif(iv.datos_legados ->> 'observaciones', '')
from insertados_vales iv;

-- ----------------------------------------------------------------------------
-- 8) plantas_stock_movimientos (678, desde vt_m9) + plantas_stock final
--    (directo desde vt_s9 — ver nota de alcance en el encabezado).
-- ----------------------------------------------------------------------------

-- Fix 2026-09-01: `hora` (130 de 678) viene vacío y el fallback real es
-- `fechaHora`, que a diferencia de `hora` en el resto del legado (vales,
-- pedidos) NO es una hora suelta ("18:01") sino un timestamp ISO completo
-- ("2026-08-24T18:01:23.563Z") — concatenarlo con `fecha` producía
-- "2026-08-24 2026-08-24T18:01:23.563Z", inválido para timestamptz.
-- Confirmado contra los 130 casos reales: fechaHora siempre trae el ISO
-- completo cuando está presente, nunca solo una hora.
create temporary table stg_movimientos_legado on commit drop as
select
  m,
  m ->> 'tipo' as tipo_legado,
  case
    when nullif(m ->> 'hora', '') is not null
      then ((m ->> 'fecha') || ' ' || (m ->> 'hora'))::timestamp at time zone 'America/Argentina/Buenos_Aires'
    when nullif(m ->> 'fechaHora', '') is not null
      then (m ->> 'fechaHora')::timestamptz
    else (m ->> 'fecha')::date::timestamp at time zone 'America/Argentina/Buenos_Aires'
  end as fecha_evento,
  trim(coalesce(m ->> 'insumo', m ->> 'material')) as material_nombre
from kv_store, jsonb_array_elements(value) as m
where key = 'vt_m9';

-- Idempotencia (fix 2026-09-01): mismo patrón que plantas_formulas/
-- plantas_cargas_hormigon — datos_legados no existía en esta tabla, se
-- agrega para poder dedupear (8a) por el evento crudo `m` y (8b) por
-- material+fecha del delta de relevamiento. Sin esto, correr el script dos
-- veces duplicaría los 779 movimientos migrados.
alter table plantas_stock_movimientos add column if not exists datos_legados jsonb;

-- 8a) Movimientos de una sola cantidad (todo salvo 'relevamiento')
insert into plantas_stock_movimientos (material_id, tipo, cantidad_kg, origen, numero_remito, observaciones, fecha_movimiento, responsable_email, datos_legados)
select
  pm.id,
  case sml.tipo_legado
    when 'ingreso_aridos' then 'ingreso_proveedor'
    when 'ingreso'        then 'ingreso_proveedor'
    when 'egreso_aridos'  then 'egreso_arido'
    when 'salida'         then 'egreso_manual'
    else 'ajuste'
  end,
  case
    when sml.tipo_legado in ('ingreso_aridos', 'ingreso') then abs(coalesce((sml.m ->> 'cantidadKg')::numeric, (sml.m ->> 'cantidad')::numeric))
    else -abs(coalesce((sml.m ->> 'cantidadKg')::numeric, (sml.m ->> 'cantidad')::numeric))
  end,
  coalesce(nullif(sml.m ->> 'proveedor', ''), nullif(sml.m ->> 'motivo', '')),
  nullif(sml.m ->> 'nroRemito', ''),
  nullif(sml.m ->> 'observaciones', ''),
  sml.fecha_evento,
  null,                                                   -- responsable_email real no disponible (el legado guarda nombre, no email — ver plantas_materiales/nombre debajo)
  sml.m
from stg_movimientos_legado sml
join plantas_materiales pm on lower(trim(pm.nombre)) = lower(sml.material_nombre)
where sml.tipo_legado <> 'relevamiento'
  and coalesce((sml.m ->> 'cantidadKg')::numeric, (sml.m ->> 'cantidad')::numeric, 0) <> 0
  and not exists (
    select 1 from plantas_stock_movimientos psm
    where psm.material_id = pm.id and psm.datos_legados = sml.m
  );

-- 8b) 'relevamiento' (23 eventos, snapshot completo de 16 materiales cada
--     uno): se migra como delta contra el relevamiento INMEDIATO ANTERIOR
--     del mismo material — no contra el estado real minuto a minuto (eso
--     exigiría reconstruir cronológicamente TODOS los tipos de movimiento
--     juntos, fuera de alcance de esta pasada). El primer relevamiento de
--     cada material queda sin migrar (no hay base anterior confiable).
with relevamientos as (
  select
    sml.fecha_evento,
    mat.key as material_nombre,
    (mat.value)::numeric as cantidad_kg
  from stg_movimientos_legado sml
  cross join lateral jsonb_each_text(sml.m -> 'detalle') as mat
  where sml.tipo_legado = 'relevamiento'
),
con_anterior as (
  select
    material_nombre,
    fecha_evento,
    cantidad_kg,
    lag(cantidad_kg) over (partition by material_nombre order by fecha_evento) as cantidad_kg_anterior
  from relevamientos
)
insert into plantas_stock_movimientos (material_id, tipo, cantidad_kg, origen, fecha_movimiento, datos_legados)
select
  pm.id,
  'ajuste',
  ca.cantidad_kg - ca.cantidad_kg_anterior,
  'Relevamiento mensual (migrado)',
  ca.fecha_evento,
  jsonb_build_object('tipo', 'relevamiento_delta', 'material', ca.material_nombre, 'fecha_evento', ca.fecha_evento)
from con_anterior ca
join plantas_materiales pm on lower(trim(pm.nombre)) = lower(ca.material_nombre)
where ca.cantidad_kg_anterior is not null
  and ca.cantidad_kg <> ca.cantidad_kg_anterior
  and not exists (
    select 1 from plantas_stock_movimientos psm
    where psm.material_id = pm.id
      and psm.datos_legados = jsonb_build_object('tipo', 'relevamiento_delta', 'material', ca.material_nombre, 'fecha_evento', ca.fecha_evento)
  );

-- 8c) Stock final: directo desde vt_s9 (estado real actual), no calculado.
insert into plantas_stock (material_id, cantidad_kg)
select pm.id, (kv.value ->> pm.nombre)::numeric
from kv_store kv
join plantas_materiales pm on kv.value ? pm.nombre
where kv.key = 'vt_s9'
on conflict (material_id) do update set
  cantidad_kg = excluded.cantidad_kg,
  actualizado_en = now();

-- ----------------------------------------------------------------------------
-- 9) Chequeos de cierre — correr y revisar ANTES de cambiar rollback por commit
-- ----------------------------------------------------------------------------

-- 9a) Obras del legado que NO se pudieron mapear a flota_obras (esperado: 1
--     fila, "cjlmpvj" / Municipalidad exaltacion de la cruz — ver encabezado):
--   select * from stg_obras_mapeadas where flota_obra_id is null;

-- 9b) Pedidos legados sin fórmula matcheada (no se insertaron):
--   select sp.id_legado, sp.raw ->> 'formulaId' as formula_id_legado
--   from stg_pedidos_legado sp
--   where not exists (select 1 from plantas_pedidos pp where pp.datos_legados ->> 'id' = sp.id_legado);

-- 9c) Movimientos de vt_m9 cuyo material no matcheó contra plantas_materiales
--     (se descartan silenciosamente por el join — revisar antes de confiar
--     en los conteos):
--   select distinct material_nombre from stg_movimientos_legado
--   where not exists (select 1 from plantas_materiales pm where lower(trim(pm.nombre)) = lower(material_nombre));

-- 9d) Conteo final de referencia (comparar contra los reales: 182 pedidos,
--     19 fórmulas, 382 vales asfalto, 499 ingresos, 3 egresos, 678 - 23 +
--     (23 - materiales sin relevamiento previo) movimientos, etc.):
--   select
--     (select count(*) from plantas_pedidos)             as pedidos_migrados,
--     (select count(*) from plantas_pedidos_historial)    as eventos_historial,
--     (select count(*) from plantas_formulas)             as formulas_migradas,
--     (select count(*) from plantas_vales)                as vales_migrados,
--     (select count(*) from plantas_ingresos)              as ingresos_migrados,
--     (select count(*) from plantas_stock_movimientos)     as movimientos_migrados,
--     (select count(*) from plantas_cargas_hormigon)       as cargas_hormigon_migradas,
--     (select count(*) from plantas_materiales)            as materiales_migrados,
--     (select count(*) from plantas_proveedores)           as proveedores_migrados,
--     (select count(*) from plantas_patentes)              as patentes_migradas;

-- AUTORIZADO por Federico, 2026-09-01: migración definitiva ejecutada con
-- `commit;`. Validado end-to-end en dos dry-runs previos (transacción
-- completa con rollback, 0 filas persistidas, conteos 100% conformes,
-- idempotencia probada corriendo los bloques nuevos dos veces) — detalle
-- completo en memory/pending.md. Este archivo queda como referencia
-- histórica de la migración ya aplicada; no se debe volver a correr.
-- commit;
commit;
