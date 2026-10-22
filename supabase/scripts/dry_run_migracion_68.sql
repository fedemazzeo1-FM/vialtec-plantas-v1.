-- ============================================================================
-- Dry-run de la migración 68 (nombre para mostrar en plantas) + ensayo de la
-- vuelta atrás, contra producción. Termina SIEMPRE con raise exception: no
-- persiste nada. La única secuencia que se consume (plantas_auditoria_id_seq,
-- por la fila de auditoría de Diego Sanchez) se devuelve al final, también si
-- falla. Bloquea plantas_usuarios_roles y plantas_auditoria mientras corre
-- (unos segundos).
--
-- Generado el 2026-10-22: cabecera + migración 68 tal cual (sin begin/commit)
-- + pruebas + revertir_migracion_68.sql tal cual (sin begin/commit). Si se
-- cambia la migración o la reversión, regenerar este archivo.
--
-- Pruebas:
--   A. Estado previo: la columna nombre no existe, balanza@ existe sin nombre.
--   B. Migración: balanza@ = "Diego Sanchez", rol/activo sin cambio, una fila
--      EDITAR usuario_rol con el motivo.
--   C. Por rol (un usuario activo de cada rol, sesión simulada como
--      authenticated): plantas_nombres_usuarios devuelve
--        - balanza@vialtec.com.ar → Diego Sanchez
--        - un usuario de flota → su nombre de flota_usuarios_email
--        - un email desconocido → sin fila (la app muestra el email)
--      y el resultado es el mismo para todos los roles.
--   D. Sin sesión (authenticated sin usuario): 0 filas.
--   E. Permisos: anon y public sin EXECUTE (y anon falla al llamarla);
--      authenticated con EXECUTE; la función es SECURITY DEFINER.
--   F. Vuelta atrás: corre revertir_migracion_68.sql; la función y la
--      columna desaparecen, balanza@ sigue igual (rol, activo), la fila de
--      auditoría queda.
-- Resultado esperado: ERROR "DRYRUN 68 OK — …" con el detalle de cada paso.
-- Cualquier otro error = algo falló (el texto dice qué).
-- ============================================================================
do $dry$
declare
  v_balanza constant text := 'balanza@vialtec.com.ar';
  v_desconocido constant text := 'desconocido-dryrun-68@ejemplo.test';
  v_flota_email text; v_flota_nombre text;
  v_antes plantas_usuarios_roles%rowtype;
  v_r record; v_n int; v_m int; v_txt text; v_ok text := ''; v_err text;
  v_roles text[] := array['admin','plantista','balancero','gerencia','encargado','supervisor','plantista_hormigon'];
  v_rol text; v_email text; v_res jsonb; v_res_ref jsonb; v_sin_usuario text := '';
  s5 bigint; c5 boolean; v_aud_ini bigint;
begin
  lock table plantas_usuarios_roles, plantas_auditoria in share row exclusive mode;
  select last_value, is_called into s5, c5 from plantas_auditoria_id_seq;
  select coalesce(max(id), 0) into v_aud_ini from plantas_auditoria;
  perform set_config('request.jwt.claims', '', true);

  begin
  -- ===== A. Estado previo =====
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'plantas_usuarios_roles' and column_name = 'nombre') then
    raise exception 'DRY FALLA A: la columna plantas_usuarios_roles.nombre ya existe (¿la 68 ya se aplicó?)';
  end if;
  if exists (select 1 from pg_proc where proname = 'plantas_nombres_usuarios') then
    raise exception 'DRY FALLA A: plantas_nombres_usuarios ya existe';
  end if;
  select * into v_antes from plantas_usuarios_roles where email = v_balanza;
  if v_antes.id is null then
    raise exception 'DRY FALLA A: no existe % en plantas_usuarios_roles', v_balanza;
  end if;
  v_ok := 'A: estado previo OK (balanza@ rol ' || v_antes.rol || ', activo ' || v_antes.activo || ')';

  -- Usuario de flota para la prueba: activo en plantas, con nombre en flota.
  select r.email, f.nombre into v_flota_email, v_flota_nombre
    from plantas_usuarios_roles r
    join flota_usuarios_email f on lower(f.email) = lower(r.email)
   where r.activo and r.email <> v_balanza and nullif(btrim(f.nombre), '') is not null
   order by r.email limit 1;
  if v_flota_email is null then
    raise exception 'DRY FALLA A: no hay ningún usuario de plantas con nombre en flota_usuarios_email para probar';
  end if;

  -- ===== B. Migración 68 =====
  execute $m68$
-- ============================================================================
-- Migración 68 — nombre para mostrar del lado de plantas
-- ESTADO: BORRADOR, NO APLICADA. No tiene dry-run todavía (la sesión del
-- 2026-10-22 no podía tocar la base). Orden: dry-run → OK de Federico →
-- aplicar → frontend (ver al final) → build → deploy.
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

$m68$;

  select * into v_r from plantas_usuarios_roles where email = v_balanza;
  if v_r.nombre is distinct from 'Diego Sanchez' or v_r.rol <> v_antes.rol or v_r.activo <> v_antes.activo then
    raise exception 'DRY FALLA B: balanza@ quedó nombre=%, rol=%, activo=%', v_r.nombre, v_r.rol, v_r.activo;
  end if;
  select count(*) into v_n from plantas_usuarios_roles where nombre is not null;
  if v_n <> 1 then raise exception 'DRY FALLA B: % filas con nombre (esperaba 1)', v_n; end if;
  select count(*) into v_n from plantas_auditoria
   where id > v_aud_ini and tipo_accion = 'EDITAR' and entidad = 'usuario_rol' and entidad_ref = v_balanza
     and motivo = 'Nombre de la persona que usa la cuenta de báscula en plantas'
     and valores_despues ->> 'nombre' = 'Diego Sanchez';
  select count(*) into v_m from plantas_auditoria where id > v_aud_ini;
  if v_n <> 1 or v_m <> 1 then
    raise exception 'DRY FALLA B: auditoría esperada 1 fila EDITAR usuario_rol, hay % de % nuevas', v_n, v_m;
  end if;
  select usuario_email into v_txt from plantas_auditoria where id > v_aud_ini;
  v_ok := v_ok || ' || B: balanza@ = Diego Sanchez, rol/activo sin cambio, 1 fila de auditoría (usuario: ' || coalesce(v_txt, 'null') || ')';

  -- ===== C. Por rol =====
  v_res_ref := jsonb_build_object(v_balanza, 'Diego Sanchez', lower(v_flota_email), v_flota_nombre);
  foreach v_rol in array v_roles loop
    v_email := null;
    select r.email into v_email from plantas_usuarios_roles r
     where r.rol = v_rol and r.activo
       and exists (select 1 from auth.users u where lower(u.email) = lower(r.email))
     order by r.email limit 1;
    if v_email is null then
      v_sin_usuario := v_sin_usuario || v_rol || ' ';
      continue;
    end if;
    perform set_config('request.jwt.claims', json_build_object(
      'email', v_email,
      'sub', (select id from auth.users where lower(email) = lower(v_email)),
      'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    select coalesce(jsonb_object_agg(email, nombre), '{}'::jsonb) into v_res
      from plantas_nombres_usuarios(array[v_balanza, upper(v_flota_email), v_desconocido, null, '']);
    execute 'reset role';
    if v_res <> v_res_ref then
      raise exception 'DRY FALLA C (%): esperaba %, devolvió %', v_rol, v_res_ref, v_res;
    end if;
    if v_res ? v_desconocido then
      raise exception 'DRY FALLA C (%): el email desconocido devolvió fila', v_rol;
    end if;
    v_ok := v_ok || ' || C ' || v_rol || ' OK';
  end loop;
  perform set_config('request.jwt.claims', '', true);
  v_ok := v_ok || ' (balanza@ → Diego Sanchez; ' || v_flota_email || ' → ' || v_flota_nombre
                || '; desconocido → sin fila)';
  if v_sin_usuario <> '' then
    v_ok := v_ok || ' [roles sin usuario activo para probar: ' || btrim(v_sin_usuario) || ']';
  end if;

  -- ===== D. Sin sesión =====
  perform set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from plantas_nombres_usuarios(array[v_balanza, v_flota_email]);
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  if v_n <> 0 then raise exception 'DRY FALLA D: sin usuario devolvió % filas', v_n; end if;
  v_ok := v_ok || ' || D: sin sesión 0 filas';

  -- ===== E. Permisos =====
  if has_function_privilege('anon', 'public.plantas_nombres_usuarios(text[])', 'EXECUTE') then
    raise exception 'DRY FALLA E: anon tiene EXECUTE';
  end if;
  if not has_function_privilege('authenticated', 'public.plantas_nombres_usuarios(text[])', 'EXECUTE') then
    raise exception 'DRY FALLA E: authenticated no tiene EXECUTE';
  end if;
  select proacl::text into v_txt from pg_proc where proname = 'plantas_nombres_usuarios';
  if exists (select 1 from pg_proc p, aclexplode(p.proacl) a
              where p.proname = 'plantas_nombres_usuarios' and a.grantee = 0 and a.privilege_type = 'EXECUTE') then
    raise exception 'DRY FALLA E: PUBLIC tiene EXECUTE (%)', v_txt;
  end if;
  if not (select prosecdef from pg_proc where proname = 'plantas_nombres_usuarios') then
    raise exception 'DRY FALLA E: la función no es SECURITY DEFINER';
  end if;
  begin
    execute 'set local role anon';
    perform * from plantas_nombres_usuarios(array[v_balanza]);
    execute 'reset role';
    raise exception 'DRY FALLA E: anon pudo ejecutar la función';
  exception when insufficient_privilege then
    execute 'reset role';
  end;
  v_ok := v_ok || ' || E: anon sin EXECUTE (rechazado al llamar), authenticated con EXECUTE, SECURITY DEFINER, acl ' || v_txt;

  -- ===== F. Vuelta atrás =====
  execute $r68$
-- Reversión de la migración 68 (nombre para mostrar en plantas).
-- Antes de correrla, volver el frontend a leer flota_usuarios_email directo
-- (fetchNombresPorEmail y auth.store.js), o la app va a fallar al pedir nombres.
-- La fila de auditoría de "Diego Sanchez" queda (plantas_auditoria no admite
-- borrados); se puede dejar otra fila EDITAR explicando la reversión.


drop function if exists public.plantas_nombres_usuarios(text[]);

alter table public.plantas_usuarios_roles
  drop constraint if exists plantas_usuarios_roles_nombre_chk;
alter table public.plantas_usuarios_roles
  drop column if exists nombre;


$r68$;

  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'plantas_usuarios_roles' and column_name = 'nombre') then
    raise exception 'DRY FALLA F: la columna nombre sigue existiendo';
  end if;
  if exists (select 1 from pg_proc where proname = 'plantas_nombres_usuarios') then
    raise exception 'DRY FALLA F: la función sigue existiendo';
  end if;
  select count(*) into v_n from plantas_usuarios_roles
   where email = v_balanza and rol = v_antes.rol and activo = v_antes.activo and id = v_antes.id;
  if v_n <> 1 then raise exception 'DRY FALLA F: balanza@ cambió con la reversión'; end if;
  select count(*) into v_n from plantas_auditoria where id > v_aud_ini;
  if v_n <> 1 then raise exception 'DRY FALLA F: auditoría tiene % filas nuevas (esperaba 1)', v_n; end if;
  v_ok := v_ok || ' || F: reversión OK (sin columna ni función, balanza@ igual, la fila de auditoría queda)';

  exception when others then
    v_err := sqlerrm;
    perform setval('plantas_auditoria_id_seq', s5, c5);
    raise exception 'DRYRUN 68 FALLÓ (secuencia restaurada): %', v_err;
  end;

  perform setval('plantas_auditoria_id_seq', s5, c5);
  raise exception 'DRYRUN 68 OK — %', v_ok;
end;
$dry$;
