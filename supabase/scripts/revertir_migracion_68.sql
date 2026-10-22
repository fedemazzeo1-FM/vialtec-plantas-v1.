-- Reversión de la migración 68 (nombre para mostrar en plantas).
-- Antes de correrla, volver el frontend a leer flota_usuarios_email directo
-- (fetchNombresPorEmail y auth.store.js), o la app va a fallar al pedir nombres.
-- La fila de auditoría de "Diego Sanchez" queda (plantas_auditoria no admite
-- borrados); se puede dejar otra fila EDITAR explicando la reversión.

begin;

drop function if exists public.plantas_nombres_usuarios(text[]);

alter table public.plantas_usuarios_roles
  drop constraint if exists plantas_usuarios_roles_nombre_chk;
alter table public.plantas_usuarios_roles
  drop column if exists nombre;

commit;
