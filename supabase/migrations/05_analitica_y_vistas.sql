-- ============================================================================
-- Migración 05: Analítica de proveedores y vistas de despacho por camión
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- IMPORTANTE (memory/procedimientos.md): este archivo queda guardado para
-- revisión previa de Federico. NO se ejecutó contra Supabase todavía.
--
-- Depende de: 02_pedidos.sql (plantas_pedidos), 04_bascula_y_vales.sql
-- (plantas_vales), flota_obras (ya existe).
--
-- Esta migración agrega DOS tablas que el Dashboard necesita y todavía no
-- existían en el proyecto, más una vista. Quedan notas de diseño abajo.
-- ============================================================================

create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- plantas_ingresos
-- Fuente ÚNICA de ingresos de insumos (manual o vía báscula). Que sea una
-- sola tabla, con `origen` + `vale_id` opcional, es justamente lo que evita
-- que un mismo ingreso pesado en báscula se cuente dos veces en la analítica
-- de proveedores (CAMBIO 7 del prompt que originó esta migración). Hoy la
-- única vía que escribe acá es src/modules/bascula/services/bascula.service.js
-- (registrarPesada, tipo_vale = 'ingreso_arido') — el ingreso MANUAL
-- (origen = 'manual') queda soportado en el schema pero sin UI todavía: es
-- responsabilidad del módulo Stock, que sigue PENDIENTE
-- (memory/modules-status.md #4).
-- ----------------------------------------------------------------------------
create table if not exists plantas_ingresos (
  id            uuid primary key default gen_random_uuid(),
  material      text not null,
  proveedor     text not null,
  numero_remito text,
  cantidad      numeric not null check (cantidad > 0),
  unidad        text not null default 'tn' check (unidad in ('tn', 'kg')),
  origen        text not null default 'manual' check (origen in ('manual', 'bascula')),
  vale_id       uuid references plantas_vales (id),
  fecha_ingreso timestamptz not null default now(),
  observaciones text,
  created_at    timestamptz not null default now()
);

create index if not exists idx_plantas_ingresos_proveedor on plantas_ingresos (proveedor);
create index if not exists idx_plantas_ingresos_fecha_ingreso on plantas_ingresos (fecha_ingreso);
create index if not exists idx_plantas_ingresos_numero_remito on plantas_ingresos (numero_remito);

comment on table plantas_ingresos is
  'Ingresos de insumos (manual o vía báscula). Fuente única para la analítica de proveedores del Dashboard — ver memory/business-rules.md.';

-- NOTA: no se puso UNIQUE en numero_remito. El sistema legado valida "que no
-- esté duplicado", pero lo más probable es que esa unicidad sea por
-- proveedor (cada proveedor tiene su propia numeración de remitos), no
-- global. Queda para decidir con Federico si hace falta esa validación y con
-- qué alcance antes de aplicar esto en producción.

-- ----------------------------------------------------------------------------
-- plantas_cargas_hormigon
-- Despacho por camión de hormigón, con remito real. Hormigón NO pasa por
-- báscula (memory/business-rules.md: "la báscula no se usa para hormigón"),
-- así que no puede vivir en plantas_vales — esta tabla es la pieza que
-- faltaba para que el Dashboard pueda mostrar remito también en hormigón
-- (CAMBIO 8). obra_id se copia del pedido al momento de la carga, mismo
-- patrón que plantas_vales.obra_id.
--
-- Todavía NO hay ninguna UI que escriba acá (el despacho de hormigón en
-- PedidosView.despacharPedido solo carga una cantidad agregada, sin cargas
-- individuales con remito) — ver memory/pending.md. La tabla y la vista de
-- abajo ya están listas para cuando se construya esa captura.
-- ----------------------------------------------------------------------------
create table if not exists plantas_cargas_hormigon (
  id            uuid primary key default gen_random_uuid(),
  pedido_id     uuid not null references plantas_pedidos (id),
  obra_id       bigint references flota_obras (id),
  numero_remito text not null,
  cantidad_m3   numeric not null check (cantidad_m3 > 0),
  patente       text,
  fecha_carga   timestamptz not null default now(),
  observaciones text,
  created_at    timestamptz not null default now()
);

create index if not exists idx_plantas_cargas_hormigon_pedido_id on plantas_cargas_hormigon (pedido_id);
create index if not exists idx_plantas_cargas_hormigon_obra_id on plantas_cargas_hormigon (obra_id);
create index if not exists idx_plantas_cargas_hormigon_fecha_carga on plantas_cargas_hormigon (fecha_carga);

comment on table plantas_cargas_hormigon is
  'Despacho por camión de hormigón (remito por carga). Análogo a plantas_vales pero sin pesaje, ver memory/business-rules.md.';

-- ----------------------------------------------------------------------------
-- Vista: despacho por camión unificado (asfalto + hormigón)
-- numero_remito está garantizado por construcción para los dos materiales:
-- para asfalto es numero_vale (identity, nunca null); para hormigón es la
-- columna numero_remito (not null). Esto es lo que corrige CAMBIO 8 — no
-- depende de que el código de la app recuerde incluirlo en cada query.
-- ----------------------------------------------------------------------------
create or replace view plantas_v_despachos_camion as
  select
    'asfalto'::text as material,
    v.fecha_pesada  as fecha,
    v.obra_id,
    v.pedido_id,
    v.patente,
    v.numero_vale::text as numero_remito,
    v.peso_neto     as volumen,
    v.unidad        as unidad_volumen
  from plantas_vales v
  where v.tipo_vale = 'asfalto'

  union all

  select
    'hormigon'::text as material,
    c.fecha_carga    as fecha,
    c.obra_id,
    c.pedido_id,
    c.patente,
    c.numero_remito,
    c.cantidad_m3    as volumen,
    'm3'::text       as unidad_volumen
  from plantas_cargas_hormigon c;

comment on view plantas_v_despachos_camion is
  'Despacho por camión unificado (asfalto desde plantas_vales, hormigón desde plantas_cargas_hormigon). numero_remito siempre presente en ambos materiales (CAMBIO 8). Ver src/modules/analytics/services/analytics.service.js.';
