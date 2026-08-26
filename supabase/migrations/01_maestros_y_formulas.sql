-- ============================================================================
-- Migración 01: Fórmulas y Maestros de planta
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- IMPORTANTE (memory/procedimientos.md): este archivo queda guardado para
-- revisión previa de Federico. NO se ejecutó contra Supabase todavía.
--
-- Alcance: tablas propias de VialTec Plantas (prefijo plantas_*), no toca
-- ninguna tabla flota_*. Corresponde a los services:
--   src/modules/maestros/services/formulas.service.js
--   src/modules/maestros/services/maestros.service.js
--
-- Pendiente de definir antes de aplicar en producción (ver memory/pending.md):
--   - Políticas de RLS por rol (no incluidas en esta migración: por defecto
--     RLS queda deshabilitado en las tablas creadas acá; no habilitar sin
--     antes definir el mapeo de roles flota_* <-> roles del sistema de planta).
--   - Si `plantas_encargados` termina siendo redundante con `flota_usuarios`
--     (encargados de obra ya existentes en flota) o es un catálogo aparte.
-- ============================================================================

-- gen_random_uuid() requiere pgcrypto (suele venir habilitado en Supabase).
create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- plantas_formulas
-- ----------------------------------------------------------------------------
create table if not exists plantas_formulas (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null,
  tipo       text not null check (tipo in ('asfalto', 'hormigon')),
  unidad     text not null check (unidad in ('tn', 'm3')),
  activo     boolean not null default true,
  insumos    jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),

  constraint plantas_formulas_nombre_key unique (nombre)
);

create index if not exists idx_plantas_formulas_tipo on plantas_formulas (tipo);
create index if not exists idx_plantas_formulas_activo on plantas_formulas (activo);

comment on table plantas_formulas is
  'Composición de mezclas de asfalto/hormigón. insumos: [{ id, material, cantidad, unidad }].';

-- ----------------------------------------------------------------------------
-- plantas_encargados
-- ----------------------------------------------------------------------------
create table if not exists plantas_encargados (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null,
  telefono   text,
  activo     boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists idx_plantas_encargados_activo on plantas_encargados (activo);

-- ----------------------------------------------------------------------------
-- plantas_proveedores
-- ----------------------------------------------------------------------------
create table if not exists plantas_proveedores (
  id                 uuid primary key default gen_random_uuid(),
  nombre             text not null,
  material_principal text,
  activo             boolean not null default true,
  created_at         timestamptz not null default now()
);

create index if not exists idx_plantas_proveedores_activo on plantas_proveedores (activo);

-- ----------------------------------------------------------------------------
-- plantas_patentes
-- ----------------------------------------------------------------------------
create table if not exists plantas_patentes (
  id               uuid primary key default gen_random_uuid(),
  patente          text not null,
  tipo_camion      text,
  tara             numeric,
  chofer_habitual  text,
  es_externa       boolean not null default false,
  activo           boolean not null default true,
  created_at       timestamptz not null default now(),

  constraint plantas_patentes_patente_key unique (patente)
);

create index if not exists idx_plantas_patentes_activo on plantas_patentes (activo);
create index if not exists idx_plantas_patentes_es_externa on plantas_patentes (es_externa);

-- ----------------------------------------------------------------------------
-- plantas_choferes
-- ----------------------------------------------------------------------------
create table if not exists plantas_choferes (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null,
  dni        text,
  activo     boolean not null default true,
  created_at timestamptz not null default now(),

  constraint plantas_choferes_dni_key unique (dni)
);

create index if not exists idx_plantas_choferes_activo on plantas_choferes (activo);
