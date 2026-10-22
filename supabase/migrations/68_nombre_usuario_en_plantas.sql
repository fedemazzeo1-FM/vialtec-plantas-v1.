-- ============================================================================
-- Migración 68 — nombre para mostrar del lado de plantas
-- ESTADO: APLICADA en producción el 2026-10-23 con OK de Federico, después
-- del dry-run OK (supabase/scripts/dry_run_migracion_68.sql). Frontend del pie
-- aplicado el mismo día.
-- (La 67 queda reservada para Simulador → auditoría, ver memory/pending.md.)
-- ============================================================================
--
-- Problema: la tarjeta de Pedidos muestra "🔒 Pesaje cerrado … (email)". La
-- base guarda el email de quien cerró (plantas_pedidos.pesaje_cerrado_por =
-- auth.email(), migración 65). El frontend ya lo traduce a nombre contra
-- flota_usuarios_email (commit del 2026-10-22), pero quien cierra casi
-- siempre es balanza@vialtec.com.ar (Diego Sanchez), que no tiene fila en ese
-- directorio — y no se le crea porque habilitaría su login en flota
-- (decisión (b) de Federico, 19/10: el nombre va en plantas).
--
-- Además, un rol no admin no puede leer las filas ajenas de
-- plantas_usuarios_roles (RLS, migración 21), así que el nombre nuevo no se
-- puede leer directo desde el cliente: se expone con una función que solo
-- devuelve email → nombre.
--
-- Qué hace:
--   1) plantas_usuarios_roles.nombre (text, opcional, sin vacíos).
--   2) Carga "Diego Sanchez" para balanza@vialtec.com.ar, con su fila de
--      auditoría (EDITAR usuario_rol). Solo si la fila existe y no tenía
--      nombre.
--   3) plantas_nombres_usuarios(p_emails text[]) → (email, nombre): prefiere
--      el nombre de plantas y cae al de flota_usuarios_email. Solo
--      authenticated; sin anon. Máx. 500 emails por llamada.
--
-- Qué NO hace (a propósito):
--   - No toca flota_usuarios_email ni el rol de balanza.
--   - No cambia lo que se guarda (pesaje_cerrado_por sigue siendo el email:
--     es la identidad; el nombre se resuelve al mostrar).
--   - No cambia el mensaje de error de registrar_pesada_bascula ("tiene el
--     pesaje cerrado (email, fecha)"). Casi no se ve (un pedido cerrado no se
--     ofrece en las puertas); si se quiere, es otra migración que parchea el
--     cuerpo desde pg_get_functiondef de producción con control de md5.
--
-- Reversión: supabase/scripts/revertir_migracion_68.sql (borra la función y
-- la columna; la fila de auditoría queda, la tabla no admite borrados).
-- ============================================================================

begin;

-- 1) Columna
alter table public.plantas_usuarios_roles
  add column if not exists nombre text;

alter table public.plantas_usuarios_roles
  drop constraint if exists plantas_usuarios_roles_nombre_chk;
alter table public.plantas_usuarios_roles
  add constraint plantas_usuarios_roles_nombre_chk
  check (nombre is null or length(btrim(nombre)) > 0);

comment on column public.plantas_usuarios_roles.nombre is
  'Nombre para mostrar en plantas. Tiene prioridad sobre flota_usuarios_email.nombre (migración 68).';

-- 2) Diego Sanchez para la cuenta de báscula, con auditoría
do $$
declare
  v_antes public.plantas_usuarios_roles;
  v_despues public.plantas_usuarios_roles;
begin
  select * into v_antes
    from public.plantas_usuarios_roles
   where email = 'balanza@vialtec.com.ar'
   for update;

  if not found then
    raise exception 'No existe balanza@vialtec.com.ar en plantas_usuarios_roles: revisar antes de aplicar.';
  end if;
  if v_antes.nombre is not null then
    raise exception 'balanza@vialtec.com.ar ya tiene nombre (%): revisar antes de aplicar.', v_antes.nombre;
  end if;

  update public.plantas_usuarios_roles
     set nombre = 'Diego Sanchez'
   where id = v_antes.id
  returning * into v_despues;

  perform public.plantas_auditar(
    'EDITAR', 'usuarios', 'usuario_rol',
    v_despues.email, v_despues.email || ' — ' || v_despues.rol,
    'Nombre de la persona que usa la cuenta de báscula en plantas',
    jsonb_build_object('nombre', null),
    jsonb_build_object('nombre', v_despues.nombre)
  );
end;
$$;

-- 3) Lectura de nombres (email → nombre)
create or replace function public.plantas_nombres_usuarios(p_emails text[])
returns table (email text, nombre text)
language sql
stable
security definer
set search_path = public
as $$
  select e.email, coalesce(r.nombre, f.nombre) as nombre
    from (
      select distinct lower(btrim(x)) as email
        from unnest(p_emails[1:500]) as x
       where x is not null and btrim(x) <> ''
    ) e
    left join public.plantas_usuarios_roles r on lower(r.email) = e.email
    left join lateral (
      select fu.nombre
        from public.flota_usuarios_email fu
       where lower(fu.email) = e.email
       limit 1
    ) f on true
   where auth.uid() is not null
     and coalesce(r.nombre, f.nombre) is not null;
$$;

revoke all on function public.plantas_nombres_usuarios(text[]) from public, anon;
grant execute on function public.plantas_nombres_usuarios(text[]) to authenticated;

commit;

-- ----------------------------------------------------------------------------
-- Chequeos post-aplicación (solo lectura)
-- ----------------------------------------------------------------------------
-- select email, rol, nombre from plantas_usuarios_roles where email = 'balanza@vialtec.com.ar';
-- select proacl from pg_proc where proname = 'plantas_nombres_usuarios';   -- sin anon
-- select * from plantas_auditoria where entidad = 'usuario_rol' order by id desc limit 1;

-- ----------------------------------------------------------------------------
-- Frontend, recién DESPUÉS de aplicar (un solo cambio, alcanza a Pedidos,
-- Báscula, Stock y Auditoría, que ya usan fetchNombresPorEmail):
--
--   // src/services/flota.service.js#fetchNombresPorEmail
--   const { data, error } = await supabase.rpc('plantas_nombres_usuarios', { p_emails: unicos })
--
-- (las claves del mapa vuelven en minúscula: comparar en minúscula al leer).
-- Y en auth.store.js#_cargarPerfil sumar `nombre` al select de
-- plantas_usuarios_roles (la fila propia sí es legible) y preferirlo:
--   this.nombre = rolRow.nombre ?? perfilFlota?.nombre ?? email
-- ----------------------------------------------------------------------------
