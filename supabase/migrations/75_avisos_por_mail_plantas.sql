-- ============================================================================
-- Migración 75 — avisos por mail de Plantas en la bandeja compartida de VT360
-- ESTADO: BORRADOR, sin aplicar (16/11/2026). Necesita ensayo y OK de Federico.
-- Ensayo: supabase/scripts/dry_run_migracion_75.sql (correr DESPUÉS de este
-- archivo sin begin/commit, en la misma transacción; termina con ERROR
-- "DRYRUN 75 OK — …" y revierte todo).
-- Reversión: supabase/scripts/revertir_migracion_75.sql.
-- ============================================================================
--
-- La bandeja (core_notificaciones, core_notificar, notificaciones-enviar con
-- Resend desde avisos@avisos.vialtec.app) es de Flota y NO se toca: acá solo
-- se anotan los eventos de Plantas, sus destinatarios y lo que los dispara.
--
-- 1. Informe mensual (Federico, 16/11/2026): evento informe_plantas_mensual
--    (modo informe) a los mismos 7 destinatarios del informe viejo. El cron
--    informe-produccion-vialtec (día 1, 11:00 UTC = 08:00 AR) pasa a mandar el
--    secreto de Vault (core_secreto_llamada), como informe-flota; antes tenía
--    el secreto viejo escrito en el comando. El comando viejo queda en
--    plantas_avisos_respaldo para la vuelta atrás (no en el repo: tiene el
--    secreto).
-- 2. Stock crítico (Federico, 16/11/2026): evento plantas_stock_critico
--    (inmediato) a Félix Pereyra, Daniel Natel, Alejandro Fernández y Federico.
--    Mismo semáforo que el Home (calcularEstadoSemaforo de stock.service.js y
--    useAlertaStockSemana.js), pero SOLO rojo (el amarillo no manda mail):
--      · actual: el saldo de plantas_stock en rojo (en cero o debajo del mínimo);
--      · proyectado: saldo − consumo de los pedidos CONFIRMADOS de la semana
--        (lunes a domingo, fecha programada, fórmula × cantidad solicitada, sin
--        agua ni purgue) en rojo.
--    Un mail por cambio de estado, no por movimiento: se guarda el último
--    estado de cada material (plantas_avisos_stock_estado) y se avisa al
--    ENTRAR en crítico, o al pasar de "crítico proyectado" a "crítico actual"
--    (se terminó de verdad). Salir de crítico no avisa; volver a entrar, sí.
--    Si varios materiales entran juntos (un mismo despacho), va un solo mail.
--    Lo evalúa un trigger por sentencia sobre plantas_stock, plantas_pedidos,
--    plantas_materiales y plantas_formulas. Si la evaluación falla, el trigger
--    deja un WARNING y NO frena la operación (un aviso nunca bloquea un despacho).
--    Sin mínimo cargado el material nunca está en rojo (igual que el Home).
--    No se excluye a quien hizo el cambio: el aviso le llega a los 4 siempre.
--    Reglas de la bandeja que aplican: lo generado entre las 20 y las 7 (AR)
--    sale a las 7; más de 5 inmediatos al mismo destinatario en 10 min pasan
--    al resumen de las 18.
-- ============================================================================

set local lock_timeout = '5s';

-- ===== Respaldo para la vuelta atrás =====
create table public.plantas_avisos_respaldo (objeto text primary key, definicion text not null, guardado_at timestamptz not null default now());
alter table public.plantas_avisos_respaldo enable row level security;
revoke all on public.plantas_avisos_respaldo from public, anon, authenticated;
insert into public.plantas_avisos_respaldo (objeto, definicion)
select 'cron:' || jobname, schedule || E'\n' || command from cron.job where jobname = 'informe-produccion-vialtec';

-- ===== Eventos y destinatarios =====
insert into public.core_notificacion_eventos (clave, app, nombre, descripcion, modo_default) values
  ('informe_plantas_mensual', 'plantas', 'Informe mensual de Plantas',
   'Día 1, 08:00, mes anterior cerrado: tarjetas con variación, gráfico de producción y el Excel de Despachos.', 'informe'),
  ('plantas_stock_critico', 'plantas', 'Stock crítico en Plantas',
   'Un material pasa a crítico (rojo): por el stock actual o por los pedidos confirmados de la semana. Un mail por cambio de estado.', 'inmediato');

insert into public.core_notificacion_reglas (evento, tipo_destino, valor, creado_por, notas)
select 'informe_plantas_mensual', 'email', e, 'Plantas migración 75 (16/11/2026)', 'Los mismos 7 del informe viejo (Federico, 16/11)'
  from unnest(array['federico.mazzeo@vialtec.com.ar', 'fernando.mazzeo@vialtec.com.ar', 'diego.vitale@vialtec.com.ar',
                    'damian.esteban@vialtec.com.ar', 'felix.pereyra@vialtec.com.ar', 'mariano.clifford@vialtec.com.ar',
                    'daniel.natel@vialtec.com.ar']) e
union all
select 'plantas_stock_critico', 'email', e, 'Plantas migración 75 (16/11/2026)', 'Félix, Daniel Natel, Alejandro y Federico (16/11)'
  from unnest(array['felix.pereyra@vialtec.com.ar', 'daniel.natel@vialtec.com.ar', 'alejandro.fernandez@vialtec.com.ar',
                    'federico.mazzeo@vialtec.com.ar']) e;

-- ===== Semáforo (gemela de calcularEstadoSemaforo, src/services/stock.service.js) =====
create function public.plantas_semaforo_stock(p_cantidad_kg numeric, p_minimo_kg numeric, p_maximo_kg numeric)
 returns text language sql immutable set search_path to 'public'
as $f$
  select case
    when p_minimo_kg is null then 'verde'
    when p_cantidad_kg <= 0 or p_cantidad_kg < p_minimo_kg then 'rojo'
    when p_cantidad_kg < coalesce(p_minimo_kg + 0.2 * (p_maximo_kg - p_minimo_kg), p_minimo_kg * 1.2) then 'amarillo'
    else 'verde'
  end
$f$;

-- ===== Estado actual y proyectado de cada material (lo mismo que muestra el Home) =====
create function public.plantas_stock_estados(p_hoy date default (now() at time zone 'America/Argentina/Buenos_Aires')::date)
 returns table (material_id uuid, material text, stock_kg numeric, consumo_semana_kg numeric, minimo_kg numeric,
                maximo_kg numeric, estado_actual text, estado_proyectado text)
 language sql stable security definer set search_path to 'public'
as $f$
  with semana as (select date_trunc('week', p_hoy)::date as lunes),
  consumo as (
    select lower(trim(i ->> 'material')) as clave,
           sum(plantas_calcular_consumo_kg(i, p.cantidad_solicitada)) as kg
      from plantas_pedidos p
      join plantas_formulas f on f.id = p.formula_id
      cross join semana s
      cross join lateral jsonb_array_elements(coalesce(f.insumos, '[]'::jsonb)) i
     where p.estado = 'confirmado'
       and p.fecha_programada between s.lunes and s.lunes + 6
       and coalesce(p.cantidad_solicitada, 0) > 0
       and i ->> 'unidad' in ('%', 'tn', 'kg', 'L')
       and lower(trim(i ->> 'material')) not in ('agua', 'purgue')
     group by 1)
  select m.id, m.nombre, coalesce(s.cantidad_kg, 0), coalesce(c.kg, 0), m.stock_minimo_kg, m.stock_maximo_kg,
         plantas_semaforo_stock(coalesce(s.cantidad_kg, 0), m.stock_minimo_kg, m.stock_maximo_kg),
         case when c.kg > 0 then plantas_semaforo_stock(coalesce(s.cantidad_kg, 0) - c.kg, m.stock_minimo_kg, m.stock_maximo_kg) end
    from plantas_materiales m
    left join plantas_stock s on s.material_id = m.id
    left join consumo c on c.clave = lower(trim(m.nombre))
   where m.activo and m.controla_stock
$f$;
revoke all on function public.plantas_stock_estados(date) from public, anon;
grant execute on function public.plantas_stock_estados(date) to authenticated, service_role;

-- ===== Último estado avisado por material =====
-- critico: null (no está en rojo), 'proyectado' (los pedidos de la semana lo dejarían en rojo) o 'actual'.
create table public.plantas_avisos_stock_estado (
  material_id uuid primary key references public.plantas_materiales(id) on delete cascade,
  critico text check (critico in ('proyectado', 'actual')),
  cambiado_at timestamptz not null default now()
);
alter table public.plantas_avisos_stock_estado enable row level security;
revoke all on public.plantas_avisos_stock_estado from public, anon, authenticated;
grant all on public.plantas_avisos_stock_estado to service_role;

-- es-AR: 1.234,5
create function public.plantas_numero_ar(p_valor numeric, p_decimales int default 1)
 returns text language sql immutable set search_path to 'public'
as $f$
  select translate(to_char(round(p_valor, p_decimales),
                           'FM999,999,999,990' || case when p_decimales > 0 then '.' || repeat('0', p_decimales) else '' end),
                   ',.', '.,')
$f$;

-- ===== Evaluar y avisar =====
-- Devuelve cuántos mails quedaron en la bandeja. Serializado con un lock de transacción para que dos despachos al
-- mismo tiempo no avisen dos veces lo mismo.
create function public.plantas_avisos_stock_revisar()
 returns int language plpgsql security definer set search_path to 'public'
as $f$
declare
  v_filas jsonb := '[]'::jsonb;
  v_nombres text[] := '{}';
  v_actual int := 0;
  r record;
begin
  perform pg_advisory_xact_lock(hashtext('plantas_avisos_stock'));
  for r in
    select e.*, a.critico as antes,
           case when e.estado_actual = 'rojo' then 'actual' when e.estado_proyectado = 'rojo' then 'proyectado' end as ahora
      from plantas_stock_estados() e
      left join plantas_avisos_stock_estado a on a.material_id = e.material_id
     order by e.material
  loop
    if r.ahora is distinct from r.antes then
      insert into plantas_avisos_stock_estado (material_id, critico, cambiado_at) values (r.material_id, r.ahora, now())
      on conflict (material_id) do update set critico = excluded.critico, cambiado_at = excluded.cambiado_at;
      -- Avisa al entrar en crítico o cuando pasa de proyectado a actual; salir (o bajar de actual a proyectado) no.
      if r.ahora is not null and (r.antes is null or (r.antes = 'proyectado' and r.ahora = 'actual')) then
        v_nombres := v_nombres || r.material;
        if r.ahora = 'actual' then v_actual := v_actual + 1; end if;
        v_filas := v_filas || jsonb_build_array(jsonb_build_array(
          r.material,
          plantas_numero_ar(r.stock_kg / 1000) || ' tn',
          case when r.consumo_semana_kg > 0 then plantas_numero_ar(r.consumo_semana_kg / 1000) || ' tn' else '—' end,
          plantas_numero_ar((r.stock_kg - r.consumo_semana_kg) / 1000) || ' tn',
          plantas_numero_ar(r.minimo_kg / 1000) || ' tn',
          case r.ahora when 'actual' then 'Stock actual' else 'Pedidos de la semana' end));
      end if;
    end if;
  end loop;

  if cardinality(v_nombres) = 0 then return 0; end if;

  return core_notificar(
    'plantas_stock_critico',
    case when cardinality(v_nombres) = 1 then 'Stock crítico en Plantas: ' || v_nombres[1]
         else 'Stock crítico en Plantas: ' || cardinality(v_nombres) || ' materiales' end,
    null,
    jsonb_build_object(
      'tono', 'critico',
      'etiqueta', 'Plantas · Stock crítico',
      'titulo', case when cardinality(v_nombres) = 1 then v_nombres[1] || ' en stock crítico'
                     else cardinality(v_nombres) || ' materiales en stock crítico' end,
      'mensaje', case when v_actual > 0
                      then 'El stock quedó en cero o debajo del mínimo. Revisá los ingresos previstos antes de despachar.'
                      else 'Con los pedidos confirmados de esta semana, el stock quedaría debajo del mínimo. Revisá los ingresos previstos.' end,
      'preencabezado', array_to_string(v_nombres, ', ') || ' en crítico',
      'secciones', jsonb_build_array(jsonb_build_object(
        'titulo', 'Materiales en crítico',
        'columnas', jsonb_build_array(
          jsonb_build_object('texto', 'Material'),
          jsonb_build_object('texto', 'Stock', 'derecha', true),
          jsonb_build_object('texto', 'Pedidos semana', 'derecha', true),
          jsonb_build_object('texto', 'Queda', 'derecha', true),
          jsonb_build_object('texto', 'Mínimo', 'derecha', true),
          jsonb_build_object('texto', 'Por')),
        'filas', v_filas)),
      'accion', jsonb_build_object('texto', 'Ver stock', 'url', 'https://produccion.vialtec.app/stock'),
      'nota', 'Sale una vez cuando un material entra en crítico (en cero o debajo del mínimo, ahora o con los pedidos confirmados de la semana). Vuelve a avisar solo si sale de crítico y vuelve a entrar. No bloquea pedidos.'),
    'plantas_stock', null, '{}'::jsonb, null,
    'plantas_stock_critico:' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'));
end $f$;
revoke all on function public.plantas_avisos_stock_revisar() from public, anon, authenticated;
grant execute on function public.plantas_avisos_stock_revisar() to service_role;

create function public.plantas_trg_avisos_stock()
 returns trigger language plpgsql security definer set search_path to 'public'
as $f$
begin
  begin
    perform plantas_avisos_stock_revisar();
  exception when others then
    raise warning 'Aviso de stock crítico no evaluado (%): %', sqlstate, sqlerrm;
  end;
  return null;
end $f$;
revoke all on function public.plantas_trg_avisos_stock() from public, anon, authenticated;

create trigger plantas_avisos_stock after insert or update or delete on public.plantas_stock
  for each statement execute function public.plantas_trg_avisos_stock();
create trigger plantas_avisos_stock after insert or update or delete on public.plantas_pedidos
  for each statement execute function public.plantas_trg_avisos_stock();
create trigger plantas_avisos_stock after update on public.plantas_materiales
  for each statement execute function public.plantas_trg_avisos_stock();
create trigger plantas_avisos_stock after update on public.plantas_formulas
  for each statement execute function public.plantas_trg_avisos_stock();

-- Punto de partida: el estado de hoy, sin avisar (no manda mails al aplicar).
insert into public.plantas_avisos_stock_estado (material_id, critico)
select material_id, case when estado_actual = 'rojo' then 'actual' when estado_proyectado = 'rojo' then 'proyectado' end
  from public.plantas_stock_estados();

-- ===== Cron del informe: secreto de Vault (mismo día y hora) =====
select cron.alter_job(
  (select jobid from cron.job where jobname = 'informe-produccion-vialtec'),
  schedule := '0 11 1 * *',
  command := $c$
  select net.http_post(
    url := 'https://ejitztewkpnmrckwmvny.supabase.co/functions/v1/informe-produccion',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-informe-secret', public.core_secreto_llamada()),
    timeout_milliseconds := 180000)
$c$);
