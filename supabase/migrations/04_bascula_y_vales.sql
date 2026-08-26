-- ============================================================================
-- Migración 04: Báscula y Vales
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- IMPORTANTE (memory/procedimientos.md): este archivo queda guardado para
-- revisión previa de Federico. NO se ejecutó contra Supabase todavía.
--
-- Depende de:
--   01_maestros_y_formulas.sql (no la usa directamente, pero es del mismo dominio)
--   02_pedidos.sql             (plantas_pedidos, FK de pedido_id)
--   flota_obras                (ya existe y está activa — FK de obra_id)
--
-- No depende de una migración "03": ese número está reservado para el módulo
-- Stock (todavía PENDIENTE, ver memory/modules-status.md #4). El descuento de
-- stock al pesar NO está implementado en el código todavía por eso mismo —
-- ver el TODO en src/modules/bascula/services/bascula.service.js.
-- ============================================================================

create extension if not exists pgcrypto;

create table if not exists plantas_vales (
  id                uuid primary key default gen_random_uuid(),

  -- Secuencia nativa global de vales, arranca en 9579 para dar continuidad a
  -- la numeración en papel que ya usaba la planta (memory/business-rules.md).
  -- Un identity column (no un MAX()+1 calculado en la app) es necesario acá
  -- porque el módulo admite varios slots de báscula pesando en paralelo.
  numero_vale       bigint generated always as identity (start with 9579) unique,

  tipo_vale         text not null check (tipo_vale in ('asfalto', 'hormigon', 'ingreso_arido')),
  pedido_id         uuid references plantas_pedidos (id),
  obra_id           bigint references flota_obras (id),
  patente           text,
  chofer            text,
  peso_bruto        numeric not null check (peso_bruto > 0),
  tara              numeric not null check (tara >= 0),
  peso_neto         numeric not null check (peso_neto > 0),
  unidad            text not null default 'tn' check (unidad in ('tn', 'kg')),

  -- Foto del acumulado al momento de pesar, a título informativo/auditoría.
  -- El remito impreso NUNCA lee de acá: siempre se recalcula dinámico con
  -- obtenerAcumuladoObraHastaFecha() (memory/business-rules.md).
  acumulado_obra_tn numeric,

  fecha_pesada      timestamptz not null default now(),
  observaciones     text,
  created_at        timestamptz not null default now(),

  constraint plantas_vales_peso_neto_check check (peso_neto = peso_bruto - tara)
);

create index if not exists idx_plantas_vales_pedido_id on plantas_vales (pedido_id);
create index if not exists idx_plantas_vales_obra_id on plantas_vales (obra_id);
create index if not exists idx_plantas_vales_tipo_vale on plantas_vales (tipo_vale);
create index if not exists idx_plantas_vales_fecha_pesada on plantas_vales (fecha_pesada);

-- Índice compuesto para el cálculo de acumulado por obra (obra + tipo + rango
-- de fecha, ver obtenerAcumuladoObraHastaFecha en bascula.service.js).
create index if not exists idx_plantas_vales_obra_tipo_fecha on plantas_vales (obra_id, tipo_vale, fecha_pesada);

comment on table plantas_vales is
  'Vales de pesaje de báscula (asfalto/ingreso de áridos). numero_vale es una secuencia global desde 9579. Ver memory/business-rules.md.';

-- ----------------------------------------------------------------------------
-- Notas para revisión (no bloquean la migración, pero hay que decidirlas):
--
-- 1. tipo_vale incluye 'hormigon' porque así lo pide el schema de este
--    módulo, pero memory/business-rules.md (relevamiento del sistema legado)
--    documenta explícitamente que "la báscula NO se usa para hormigón" — el
--    hormigón se controla por remito de carga, no por pesaje. El código de
--    src/views/BasculaView.vue NO ofrece ningún flujo para crear un vale de
--    tipo 'hormigon' por eso mismo. Si en algún momento se decide pesar
--    hormigón, el schema ya lo soporta; si no, se podría sacar del check acá.
--
-- 2. Ingreso de áridos (tipo_vale = 'ingreso_arido') en el sistema legado
--    lleva material, proveedor, número de remito y cantidad según remito —
--    ninguno de esos campos está en esta tabla (el prompt que originó esta
--    migración no los pidió). Por ahora esos datos se anotan en
--    `observaciones` como texto libre (ver el aviso en BasculaView.vue). Si
--    se necesita ese detalle estructurado, hace falta una migración
--    adicional agregando esas columnas (o una tabla aparte).
-- ----------------------------------------------------------------------------
