-- Migración 30: agrega "Home" (tab `dashboard`) a la matriz de permisos por
-- rol (Administración → Roles), pedido de Federico 2026-09-07.
--
-- Hoy `dashboard` es un caso especial hardcodeado en
-- `auth.store.js#puedeVerTab` ("visible para cualquier usuario activo, sin
-- togglable en la matriz") — no pasa por `plantas_permisos` en absoluto. Esta
-- migración lo suma como un módulo más de la matriz (misma mecánica que
-- `plan_semanal`/`simulador`: en la práctica solo se usa la acción "ver",
-- las otras 5 columnas quedan sin uso real para este módulo, igual que ya
-- pasa con esos dos).
--
-- Semilla 1:1 con el comportamiento de HOY (mismo criterio que la migración
-- 26 original): los 6 roles no-admin quedan con "ver" en true para
-- `dashboard` — aplicar esto no le saca Home a nadie hasta que Federico
-- destilde el switch a propósito. `admin` no necesita fila (bypass total,
-- igual que el resto de los módulos).

alter table plantas_permisos drop constraint if exists plantas_permisos_modulo_check;
alter table plantas_permisos
  add constraint plantas_permisos_modulo_check
  check (modulo in ('dashboard', 'pedidos', 'bascula', 'stock', 'despachos', 'formulas', 'maestros', 'plan_semanal', 'simulador', 'administracion'));

insert into plantas_permisos (rol_id, modulo, accion, habilitado)
select id, 'dashboard', 'ver', true
from plantas_roles
where id <> 'admin'
on conflict (rol_id, modulo, accion) do nothing;
