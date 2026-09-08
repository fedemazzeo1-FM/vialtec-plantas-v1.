-- ============================================================================
-- Migración 32: Obras — archivado LOCAL de visibilidad en Plantas.
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Pedido de Federico (2026-09-08), después de confirmar que Flota ya tiene
-- un CRUD completo de Obras (crear/pausar/finalizar) en su propio Maestros
-- — decisión explícita de NO duplicar esa lógica ni escribir sobre
-- `flota_obras` (tabla compartida, propiedad de Flota, memory/architecture.md).
-- Esto es únicamente un FILTRO DE VISIBILIDAD local: una obra "archivada acá"
-- sigue existiendo tal cual en Flota, esto solo le dice a Plantas "no la
-- muestres más en los desplegables operativos" (Pedidos, Báscula, Despachos,
-- Plan Semanal, Dashboard, Usuarios y Permisos).
--
-- `plantas_obras_locales` es una tabla PROPIA de Plantas (no altera el
-- schema de flota_obras en absoluto) — fila dispersa: solo existe una fila
-- para una obra si alguna vez se archivó acá. Sin fila = visible (default).
-- ============================================================================

create table if not exists plantas_obras_locales (
  obra_id       bigint primary key references flota_obras (id),
  archivada     boolean not null default false,
  archivada_en  timestamptz,
  archivada_por text,
  created_at    timestamptz not null default now()
);

comment on table plantas_obras_locales is
  'Filtro de visibilidad LOCAL de Plantas sobre flota_obras (tabla compartida, solo lectura — nunca se escribe ahí). Una obra sin fila acá está visible por default. archivada=true la saca de fetchObras()/plantas_v_obras_visibles (dropdowns de Pedidos/Báscula/Despachos/Plan Semanal/Dashboard) y la muestra en el tab "Archivadas" de Maestros → Obras. No tiene relación con el estado real de Flota (activa/pausada/finalizada) — eso se sigue gestionando en equipos2.vialtec.app.';

alter table plantas_obras_locales enable row level security;

create policy "plantas_obras_locales: leer" on plantas_obras_locales
  for select to authenticated using (true);

-- Escritura restringida a admin/plantista — mismo criterio que la migración
-- 23 ya aplicó a los demás catálogos de Maestros (materiales, proveedores,
-- patentes, choferes, encargados, fórmulas): ocultar una obra de todos los
-- desplegables operativos es una acción de impacto similar.
create policy "plantas_obras_locales: escribir admin/plantista" on plantas_obras_locales
  for all to authenticated
  using (plantas_rol_actual() in ('admin', 'plantista'))
  with check (plantas_rol_actual() in ('admin', 'plantista'));

-- ----------------------------------------------------------------------------
-- plantas_v_obras_visibles — vista de lectura para fetchObras({ soloActivas: true }),
-- el service transversal que ya usan todos los módulos (src/services/flota.service.js).
-- Un solo cambio acá alcanza para que TODOS los desplegables dejen de mostrar
-- una obra archivada localmente, sin tocar cada módulo por separado.
-- ----------------------------------------------------------------------------
create or replace view plantas_v_obras_visibles
with (security_invoker = true) as
select fo.id, fo.nombre, fo.codigo
from flota_obras fo
left join plantas_obras_locales pol on pol.obra_id = fo.id
where fo.activo = true
  and coalesce(pol.archivada, false) = false;

grant select on plantas_v_obras_visibles to authenticated;
