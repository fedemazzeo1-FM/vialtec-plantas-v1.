-- ============================================================================
-- Migración 53: módulo de Auditoría, etapa 2 — tabla plantas_auditoria,
-- catálogo de entidades y función plantas_auditar
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Plan aprobado por Federico (2026-10-03, memory/pending.md) y diseño de la
-- etapa 2 aprobado el 2026-10-05. Objetivo: saber quién hizo cada acción;
-- lo ve solo el admin.
--
-- Qué crea (todo arranca vacío; los historiales existentes no se copian):
--   1) plantas_auditoria_entidades: catálogo cerrado de módulo/entidad
--      (decisión: en tabla, no en un CHECK — agregar una entidad es una fila
--      y la pantalla de la etapa 5 arma sus filtros desde acá).
--   2) plantas_auditoria: una fila por acción. Solo agregado:
--      - sin grants de escritura para anon/authenticated;
--      - trigger que rechaza UPDATE, DELETE y TRUNCATE para cualquiera,
--        también por SQL directo (para corregir una fila hay que
--        desactivarlo a propósito);
--      - lectura solo rol admin, FIJA en la policy (no depende de la matriz
--        de permisos editable).
--   3) plantas_auditar(...): única vía de escritura. SECURITY DEFINER, sin
--      EXECUTE para anon NI authenticated: solo la llaman las RPC del
--      sistema (etapa 3) y los triggers (etapa 4), así un usuario logueado
--      no puede inventar filas desde el navegador. La identidad sale de la
--      sesión (auth.email/auth.uid + plantas_usuarios_roles + nombre de
--      flota_usuarios_email, solo lectura); sin sesión queda 'sistema (SQL)'.
--      Regla de valores (decisión 3): CREAR/ELIMINAR guardan el registro
--      completo; el resto solo los campos que cambiaron; nunca datos_legados.
--      Un EDITAR sin ningún cambio no se registra (devuelve null).
--
-- No toca tablas flota_* (solo lee flota_usuarios_email). No cambia default
-- privileges del schema public. Sin cambios de frontend.
--
-- Reversión:
--   drop function plantas_auditar(text, text, text, text, text, text, jsonb, jsonb);
--   drop table plantas_auditoria;            -- arrastra triggers e índices
--   drop function plantas_auditoria_inmutable();
--   drop table plantas_auditoria_entidades;
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Catálogo de módulos y entidades
-- ----------------------------------------------------------------------------
create table plantas_auditoria_entidades (
  modulo           text not null,
  entidad          text not null,
  modulo_etiqueta  text not null,
  entidad_etiqueta text not null,
  orden            integer not null,
  primary key (modulo, entidad),
  unique (entidad)
);

insert into plantas_auditoria_entidades (modulo, entidad, modulo_etiqueta, entidad_etiqueta, orden) values
  ('pedidos',   'pedido',            'Pedidos',   'Pedido',               10),
  ('despachos', 'despacho',          'Despachos', 'Despacho',             20),
  ('despachos', 'carga_asfalto',     'Despachos', 'Carga de asfalto',     21),
  ('despachos', 'carga_hormigon',    'Despachos', 'Carga de mixer',       22),
  ('bascula',   'vale',              'Báscula',   'Vale',                 30),
  ('bascula',   'ingreso',           'Báscula',   'Ingreso de áridos',    31),
  ('stock',     'movimiento_manual', 'Stock',     'Movimiento manual',    40),
  ('stock',     'relevamiento',      'Stock',     'Relevamiento',         41),
  ('remitos',   'remito_manual',     'Remitos',   'Remito manual',        50),
  ('formulas',  'formula',           'Fórmulas',  'Fórmula',              60),
  ('maestros',  'material',          'Maestros',  'Material',             70),
  ('maestros',  'cliente',           'Maestros',  'Cliente',              71),
  ('maestros',  'proveedor',         'Maestros',  'Proveedor',            72),
  ('maestros',  'chofer',            'Maestros',  'Chofer',               73),
  ('maestros',  'patente',           'Maestros',  'Patente',              74),
  ('maestros',  'encargado',         'Maestros',  'Encargado',            75),
  ('maestros',  'obra_local',        'Maestros',  'Obra (archivado local)', 76),
  ('usuarios',  'usuario_rol',       'Usuarios',  'Usuario',              80),
  ('usuarios',  'rol',               'Usuarios',  'Rol',                  81),
  ('usuarios',  'permiso',           'Usuarios',  'Permiso',              82);

alter table plantas_auditoria_entidades enable row level security;

create policy "plantas_auditoria_entidades: lee solo admin"
  on plantas_auditoria_entidades for select to authenticated
  using ((select plantas_rol_actual()) = 'admin');

revoke all on table plantas_auditoria_entidades from public, anon, authenticated;
grant select on table plantas_auditoria_entidades to authenticated;

-- ----------------------------------------------------------------------------
-- 2) Registro de auditoría
-- ----------------------------------------------------------------------------
create table plantas_auditoria (
  id              bigint generated always as identity primary key,
  fecha_hora      timestamptz not null default clock_timestamp(),
  -- Fecha en hora de Argentina (la base corre en UTC).
  fecha_negocio   date not null default ((clock_timestamp() at time zone 'America/Argentina/Buenos_Aires')::date),
  usuario_email   text not null,
  usuario_id      uuid,
  usuario_nombre  text not null,
  usuario_rol     text,
  tipo_accion     text not null
    check (tipo_accion in ('CREAR', 'EDITAR', 'CAMBIAR_ESTADO', 'ANULAR', 'CORREGIR', 'REASIGNAR', 'ELIMINAR')),
  modulo          text not null,
  entidad         text not null,
  entidad_ref     text not null check (btrim(entidad_ref) <> ''),
  entidad_label   text,
  motivo          text,
  valores_antes   jsonb,
  valores_despues jsonb,
  dispositivo     text,
  constraint plantas_auditoria_entidad_fkey
    foreign key (modulo, entidad) references plantas_auditoria_entidades (modulo, entidad),
  constraint plantas_auditoria_motivo_obligatorio_chk
    check (tipo_accion not in ('ANULAR', 'CORREGIR', 'REASIGNAR', 'ELIMINAR')
           or nullif(btrim(motivo), '') is not null)
);

create index plantas_auditoria_fecha_idx   on plantas_auditoria (fecha_hora desc, id desc);
create index plantas_auditoria_entidad_idx on plantas_auditoria (entidad, entidad_ref);
create index plantas_auditoria_usuario_idx on plantas_auditoria (usuario_email, fecha_hora desc);

alter table plantas_auditoria enable row level security;

create policy "plantas_auditoria: lee solo admin"
  on plantas_auditoria for select to authenticated
  using ((select plantas_rol_actual()) = 'admin');

revoke all on table plantas_auditoria from public, anon, authenticated;
grant select on table plantas_auditoria to authenticated;
revoke all on sequence plantas_auditoria_id_seq from public, anon, authenticated;

create function plantas_auditoria_inmutable()
returns trigger
language plpgsql
set search_path to 'public'
as $fn$
begin
  raise exception 'El registro de auditoría es de solo agregado: no se permite % sobre plantas_auditoria.', tg_op;
end;
$fn$;

revoke execute on function plantas_auditoria_inmutable() from public, anon, authenticated;

create trigger plantas_auditoria_sin_update_delete
  before update or delete on plantas_auditoria
  for each row execute function plantas_auditoria_inmutable();

create trigger plantas_auditoria_sin_truncate
  before truncate on plantas_auditoria
  for each statement execute function plantas_auditoria_inmutable();

-- ----------------------------------------------------------------------------
-- 3) plantas_auditar: única vía de escritura
-- ----------------------------------------------------------------------------
create function plantas_auditar(
  p_tipo_accion   text,
  p_modulo        text,
  p_entidad       text,
  p_entidad_ref   text,
  p_entidad_label text default null,
  p_motivo        text default null,
  p_antes         jsonb default null,
  p_despues       jsonb default null
)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_email   text := nullif(btrim(auth.email()), '');
  v_uid     uuid;
  v_nombre  text;
  v_rol     text;
  v_ua      text;
  v_disp    text;
  v_antes   jsonb := p_antes;
  v_despues jsonb := p_despues;
  v_a       jsonb;
  v_d       jsonb;
  v_ahora   timestamptz := clock_timestamp();
  v_id      bigint;
begin
  -- Identidad: sale de la sesión, nunca de un parámetro.
  if v_email is null then
    v_email  := 'sistema (SQL)';
    v_nombre := 'sistema (SQL)';
  else
    v_uid := auth.uid();
    select rol into v_rol from plantas_usuarios_roles where email = lower(v_email) limit 1;
    select nombre into v_nombre from flota_usuarios_email where lower(email) = lower(v_email) limit 1;
    v_nombre := coalesce(nullif(btrim(v_nombre), ''), v_email);
  end if;

  -- Valores: nunca datos_legados; salvo en CREAR/ELIMINAR, solo lo que cambió.
  if jsonb_typeof(v_antes) = 'object' then v_antes := v_antes - 'datos_legados'; end if;
  if jsonb_typeof(v_despues) = 'object' then v_despues := v_despues - 'datos_legados'; end if;

  if p_tipo_accion not in ('CREAR', 'ELIMINAR')
     and jsonb_typeof(v_antes) = 'object' and jsonb_typeof(v_despues) = 'object' then
    select jsonb_object_agg(t.k, v_antes -> t.k) filter (where v_antes ? t.k),
           jsonb_object_agg(t.k, v_despues -> t.k) filter (where v_despues ? t.k)
      into v_a, v_d
      from (select jsonb_object_keys(v_antes || v_despues) as k) t
     where (v_antes -> t.k) is distinct from (v_despues -> t.k);

    if v_a is null and v_d is null and p_tipo_accion = 'EDITAR' then
      return null;  -- se guardó sin cambiar nada: no hay nada que auditar
    end if;
    v_antes := v_a;
    v_despues := v_d;
  end if;

  -- Dispositivo: derivado del navegador que hizo el pedido (lo informa la API,
  -- no el cliente). Sin request (SQL directo) queda null.
  begin
    v_ua := nullif(current_setting('request.headers', true), '')::json ->> 'user-agent';
  exception when others then
    v_ua := null;
  end;
  if v_ua is not null then
    v_disp :=
      case when v_ua ~* '(iPad|Tablet)' then 'Tablet'
           when v_ua ~* '(Android|iPhone|Mobile)' then 'Celular'
           else 'PC' end
      || ' · ' ||
      case when v_ua ~ 'Edg/' then 'Edge'
           when v_ua ~ 'SamsungBrowser' then 'Samsung Internet'
           when v_ua ~ 'OPR/' then 'Opera'
           when v_ua ~ 'Firefox/' then 'Firefox'
           when v_ua ~ 'Chrome/' then 'Chrome'
           when v_ua ~ 'Safari/' then 'Safari'
           else 'otro navegador' end
      || ' · ' ||
      case when v_ua ~ 'Windows' then 'Windows'
           when v_ua ~ 'Android' then 'Android'
           when v_ua ~ '(iPhone|iPad)' then 'iOS'
           when v_ua ~ 'Mac OS X' then 'macOS'
           when v_ua ~ 'Linux' then 'Linux'
           else 'otro sistema' end;
  end if;

  insert into plantas_auditoria (
    fecha_hora, fecha_negocio, usuario_email, usuario_id, usuario_nombre, usuario_rol,
    tipo_accion, modulo, entidad, entidad_ref, entidad_label, motivo,
    valores_antes, valores_despues, dispositivo
  ) values (
    v_ahora, (v_ahora at time zone 'America/Argentina/Buenos_Aires')::date,
    v_email, v_uid, v_nombre, v_rol,
    p_tipo_accion, p_modulo, p_entidad, p_entidad_ref, p_entidad_label, nullif(btrim(p_motivo), ''),
    v_antes, v_despues, v_disp
  )
  returning id into v_id;

  return v_id;
end;
$fn$;

-- Sin EXECUTE para nadie de afuera (lección de la migración 43: en Supabase
-- anon y authenticated tienen grants propios, revocar a PUBLIC no alcanza).
revoke execute on function plantas_auditar(text, text, text, text, text, text, jsonb, jsonb)
  from public, anon, authenticated;

-- Control final.
do $chk$
declare
  v_mal text := '';
begin
  if (select count(*) from plantas_auditoria_entidades) <> 20 then v_mal := v_mal || 'catálogo incompleto; '; end if;
  if not (select relrowsecurity from pg_class where oid = 'public.plantas_auditoria'::regclass) then v_mal := v_mal || 'RLS apagada; '; end if;
  if not (select relrowsecurity from pg_class where oid = 'public.plantas_auditoria_entidades'::regclass) then v_mal := v_mal || 'RLS del catálogo apagada; '; end if;
  if has_table_privilege('anon', 'public.plantas_auditoria', 'select, insert, update, delete, truncate') then v_mal := v_mal || 'anon con permisos en la tabla; '; end if;
  if has_table_privilege('authenticated', 'public.plantas_auditoria', 'insert, update, delete, truncate') then v_mal := v_mal || 'authenticated con escritura; '; end if;
  if not has_table_privilege('authenticated', 'public.plantas_auditoria', 'select') then v_mal := v_mal || 'authenticated sin lectura; '; end if;
  if has_function_privilege('anon', 'public.plantas_auditar(text, text, text, text, text, text, jsonb, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.plantas_auditar(text, text, text, text, text, text, jsonb, jsonb)', 'execute') then
    v_mal := v_mal || 'plantas_auditar ejecutable desde afuera; ';
  end if;
  if v_mal <> '' then raise exception 'MIG53: %', v_mal; end if;
end;
$chk$;
