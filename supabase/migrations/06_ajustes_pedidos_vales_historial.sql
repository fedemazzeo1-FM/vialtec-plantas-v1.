-- ============================================================================
-- Migración 06: Ajustes de schema para autonomía operativa + historial de pedidos
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- IMPORTANTE (memory/procedimientos.md): este archivo queda guardado para
-- revisión previa de Federico. NO se ejecutó contra Supabase todavía.
--
-- Depende de: 02_pedidos.sql (plantas_pedidos), 04_bascula_y_vales.sql
-- (plantas_vales) — ambas TAMPOCO aplicadas todavía. Este archivo asume que
-- 01/02/04/05 se aplican primero, en orden, antes que este.
--
-- Decisiones confirmadas por Federico (ver la propuesta de mapeo de
-- migración de historial legado -> plantas_*):
--   1. obra_id pasa a nullable en plantas_pedidos (ventas externas sin obra
--      real — memory/business-rules.md, tipoPedido='venta').
--   2. Se agregan columnas operativas a plantas_pedidos para que la app
--      pueda gestionar el ciclo completo del pedido desde la UI (no son
--      solo para la migración de historial): encargado, tipo_pedido,
--      cliente_externo, motivo, motivo_en, archivado, nro_remito_global,
--      nro_vale_global.
--   3. En vez de columnas sueltas de auditoría por campo (obra_nombre_legado,
--      mezcla_nombre_legado, etc.), se agrega datos_legados jsonb a
--      plantas_pedidos y plantas_vales: guarda el objeto crudo del sistema
--      legado tal cual, para trazabilidad permanente sin tener que anticipar
--      cada campo posible.
--   4. Se crea plantas_pedidos_historial y se reintroduce el estado
--      'postergado' (existía en el sistema legado — memory/business-rules.md
--      — se había simplificado a 4 estados en 02_pedidos.sql).
--   5. Zona horaria fija America/Argentina/Buenos_Aires para combinar
--      fecha+hora del legado (se aplica en el script de carga de datos, no
--      acá — ver supabase/scripts/migracion_historial_borrador.sql).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) plantas_pedidos: obra_id nullable (ventas externas sin obra real)
-- ----------------------------------------------------------------------------
alter table plantas_pedidos
  alter column obra_id drop not null;

-- NOTA: plantas_vales.obra_id YA es nullable desde 04_bascula_y_vales.sql
-- (nunca tuvo `not null`) — no hace falta ALTER ahí.

-- ----------------------------------------------------------------------------
-- 2) plantas_pedidos: columnas operativas nuevas
--    Defaults pensados para que un pedido creado desde la UI (no solo
--    migrado desde el legado) tenga valores razonables sin que el
--    formulario deba completar todo — objetivo de autonomía total de
--    gestión desde la interfaz.
-- ----------------------------------------------------------------------------
alter table plantas_pedidos
  add column if not exists encargado         text,
  add column if not exists tipo_pedido        text not null default 'obra'
                            check (tipo_pedido in ('obra', 'venta')),
  add column if not exists cliente_externo    text,
  add column if not exists motivo             text,
  add column if not exists motivo_en          timestamptz,
  add column if not exists archivado          boolean not null default false,
  add column if not exists nro_remito_global  text,
  add column if not exists nro_vale_global    text;

comment on column plantas_pedidos.tipo_pedido is
  '''obra'' = pedido interno de una obra propia; ''venta'' = venta externa (usa cliente_externo, obra_id puede ser null). No confundir con plantas_pedidos.tipo (asfalto/hormigon), que distingue el material: un pedido puede ser tipo=''asfalto'' y tipo_pedido=''venta'' al mismo tiempo.';
comment on column plantas_pedidos.nro_vale_global is
  'Campo de referencia/display heredado del legado (asfalto interno: campo único del pedido; ventas: primer camión). El vínculo real pedido<->vale es plantas_vales.pedido_id, no este campo.';
comment on column plantas_pedidos.nro_remito_global is
  'Campo de referencia/display heredado del legado (hormigón: primer camión; ventas: campo global opcional). El detalle real por carga vive en plantas_cargas_hormigon.numero_remito.';

-- ----------------------------------------------------------------------------
-- 3) plantas_pedidos: reintroducir 'postergado' en el ciclo de estados
--
--    OJO al aplicar en producción: el nombre de constraint de abajo
--    (`plantas_pedidos_estado_check`) es el que Postgres genera por defecto
--    para un `check` inline sin nombre explícito como el de 02_pedidos.sql.
--    Verificar el nombre real antes de correr esto contra la instancia
--    productiva (`select conname from pg_constraint where conrelid =
--    'plantas_pedidos'::regclass and contype = 'c';`) por si 02_pedidos.sql
--    se aplicó con alguna variación.
-- ----------------------------------------------------------------------------
alter table plantas_pedidos
  drop constraint if exists plantas_pedidos_estado_check;

alter table plantas_pedidos
  add constraint plantas_pedidos_estado_check
  check (estado in ('solicitado', 'confirmado', 'despachado', 'postergado', 'cancelado'));

-- ----------------------------------------------------------------------------
-- 4) plantas_pedidos / plantas_vales: datos_legados jsonb
--    Guarda el objeto crudo del pedido/vale tal cual venía en el sistema
--    legado (blobs vt_*). Reemplaza el enfoque de columnas de auditoría
--    sueltas que se había propuesto inicialmente (obra_nombre_legado,
--    mezcla_nombre_legado, tipo_camion, operador_legado, etc.) — todo eso
--    queda disponible dentro de datos_legados sin necesidad de anticipar
--    cada campo como columna.
--
--    Se indexa por el id legado (datos_legados->>'id') en plantas_pedidos
--    para poder resolver referencias cruzadas (historial, vales) durante la
--    migración y para que la carga sea idempotente si se reintenta.
-- ----------------------------------------------------------------------------
alter table plantas_pedidos
  add column if not exists datos_legados jsonb;

alter table plantas_vales
  add column if not exists datos_legados jsonb;

create unique index if not exists idx_plantas_pedidos_datos_legados_id
  on plantas_pedidos ((datos_legados ->> 'id'))
  where datos_legados ->> 'id' is not null;

comment on column plantas_pedidos.datos_legados is
  'Objeto crudo del pedido tal cual estaba en el sistema legado (JSON), preservado para trazabilidad. No es la fuente de verdad operativa — esa son las columnas relacionales.';
comment on column plantas_vales.datos_legados is
  'Objeto crudo del vale tal cual estaba en el sistema legado (JSON), preservado para trazabilidad. numero_vale sigue siendo la clave natural/idempotente para vales (se preserva exacto desde el legado), no hace falta indexar datos_legados->>''id'' para eso.';

-- ----------------------------------------------------------------------------
-- 5) plantas_pedidos_historial (tabla nueva)
--    Un evento por cambio de estado del pedido (legado: array embebido
--    `historial: [{estado, fecha, usuario, motivo}]`, ver
--    "Logica sis. plantas v1.rtf" §2.2).
-- ----------------------------------------------------------------------------
create table if not exists plantas_pedidos_historial (
  id                        uuid primary key default gen_random_uuid(),
  pedido_id                 uuid not null references plantas_pedidos (id),
  estado                    text not null
                            check (estado in ('solicitado', 'confirmado', 'despachado', 'postergado', 'cancelado')),
  fecha_evento              timestamptz not null,

  -- Solo se completan para eventos estado='postergado'. El legado no trae
  -- explícitamente el par antes/después por evento (solo un `fecha` por
  -- evento) — se reconstruye a partir del evento previo en el array. Ver
  -- nota de mapeo en la propuesta de migración; supuesto pendiente de
  -- validar contra un dato real del legado.
  fecha_programada_anterior date,
  fecha_programada_nueva    date,

  -- Usuario que hizo el cambio. usuario_id queda nullable hasta que se
  -- resuelva el mapeo de roles/usuarios contra flota_* (memory/pending.md).
  usuario_legado            text,
  usuario_id                uuid,

  motivo                    text,

  -- Objeto crudo del evento de historial, mismo criterio que en
  -- plantas_pedidos.datos_legados y plantas_vales.datos_legados.
  datos_legados              jsonb,

  created_at                timestamptz not null default now()
);

create index if not exists idx_plantas_pedidos_historial_pedido_id
  on plantas_pedidos_historial (pedido_id);
create index if not exists idx_plantas_pedidos_historial_pedido_fecha
  on plantas_pedidos_historial (pedido_id, fecha_evento);

comment on table plantas_pedidos_historial is
  'Historial de cambios de estado de un pedido (append-only, nunca se edita ni se borra). Migrado desde el array historial del sistema legado. Ver memory/business-rules.md.';

-- ----------------------------------------------------------------------------
-- Notas para revisión (no bloquean la migración, pero hay que tenerlas presentes):
--
-- 1. RLS: igual que en 01_maestros_y_formulas.sql, esta migración no agrega
--    políticas de RLS sobre las tablas/columnas nuevas — sigue pendiente
--    hasta resolver el mapeo de roles (memory/pending.md).
--
-- 2. usuario_id / operador (vales, vía datos_legados) quedan sin resolver a
--    un uuid real de flota_usuarios hasta que exista ese mapeo. No bloquea
--    la migración de historial/vales, sí bloquea reportes que necesiten
--    agrupar por usuario real en vez de por el texto crudo del legado.
-- ----------------------------------------------------------------------------
