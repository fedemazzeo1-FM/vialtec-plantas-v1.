-- ============================================================================
-- Migración 71 — fecha de despacho de las cargas de mixer + vista que lee Obras
-- ESTADO: APLICADA en producción el 2026-10-28 con OK de Federico (dry-run OK: supabase/scripts/dry_run_migracion_71.sql).
-- Reversión: supabase/scripts/revertir_migracion_71.sql.
-- Decisión de Federico (28/10/2026): opciones (a) y (b) juntas.
-- ============================================================================
--
-- Problema (aviso de Obras, Moorlands Pilar): plantas_cargas_hormigon.fecha_carga
-- es el momento en que se registra la carga en el sistema (el modal no pide
-- fecha), casi siempre el día hábil siguiente al despacho real. Obras lee
-- plantas_v_despachos_camion (obras_remitos_plantas) y ve los despachos 1 a 3
-- días tarde. Además la vista pone 'hormigon' y 'm3' fijos a todo lo que sale
-- por mixer: la mezcla cemento (tn) le llega como hormigón.
--
-- Qué hace:
--   1) plantas_cargas_hormigon.fecha_despacho (date, opcional): el día real
--      del despacho. fecha_carga sigue siendo el momento de registro.
--   2) registrar_carga_hormigon recibe p_fecha_despacho (date, opcional, al
--      final). Rechaza una fecha futura (día de Argentina). Firma nueva: se
--      borra la anterior antes de crear (evita overload ambiguo); mismos
--      permisos (authenticated sí, anon no).
--   3) plantas_v_despachos_camion, rama mixer:
--        - material = tipo del pedido (hormigon | mezcla_cemento);
--        - unidad = m3 para hormigón, tn para mezcla cemento (gemela de
--          src/config/tipos-producto.js);
--        - fecha = fecha_despacho; para las cargas viejas (sin fecha_despacho),
--          la fecha del pedido. Se expresa como timestamptz a las 12:00 de
--          Argentina para que el ::date en hora AR de Obras dé ese día.
--      Las ramas de asfalto no cambian.
--
-- Qué NO hace: no reescribe fecha_carga de ninguna carga ni toca pedidos.
--
-- AVISO PARA OBRAS (antes de aplicar): obras_remitos_plantas va a recibir
-- material 'mezcla_cemento' (antes todo era 'hormigon') con unidad 'tn', y las
-- fechas de mixer cambian a la del despacho/pedido. Ver memory/pending.md.
-- ============================================================================

-- 1) Columna --------------------------------------------------------------
alter table public.plantas_cargas_hormigon add column if not exists fecha_despacho date;
comment on column public.plantas_cargas_hormigon.fecha_despacho is
  'Día real del despacho (lo carga el plantista, precargado con la fecha del pedido). fecha_carga es el momento de registro en el sistema. Migración 71.';

-- 2) RPC: parche del cuerpo de producción con control de md5 ---------------
do $mig$
declare
  c_md5_antes constant text := '865c753f93641fb08a5fbde915cad25d';
  v_def       text := pg_get_functiondef('public.registrar_carga_hormigon(uuid, text, numeric, text, text, timestamp with time zone, text)'::regprocedure);
  v_nuevo     text;
  c_reempl    constant text[][] := array[
    array[$a$p_observaciones text DEFAULT NULL::text)$a$,
          $a$p_observaciones text DEFAULT NULL::text, p_fecha_despacho date DEFAULT NULL::date)$a$],
    array[$a$  if v_pedido.estado <> 'confirmado' then$a$,
          $a$  if p_fecha_despacho > (now() at time zone 'America/Argentina/Buenos_Aires')::date then
    raise exception 'La fecha de despacho no puede ser futura.';
  end if;
  if v_pedido.estado <> 'confirmado' then$a$],
    array[$a$pedido_id, obra_id, numero_remito, volumen_m3, patente_mixer, chofer, fecha_carga, observaciones
  ) values ($a$,
          $a$pedido_id, obra_id, numero_remito, volumen_m3, patente_mixer, chofer, fecha_carga, observaciones, fecha_despacho
  ) values ($a$],
    array[$a$p_patente_mixer, p_chofer, p_fecha_carga, p_observaciones
  )$a$,
          $a$p_patente_mixer, p_chofer, p_fecha_carga, p_observaciones, p_fecha_despacho
  )$a$]
  ];
  i int;
begin
  if md5(v_def) <> c_md5_antes then
    raise exception 'registrar_carga_hormigon cambió en producción (md5 %): revisar antes de aplicar la 71', md5(v_def);
  end if;
  v_nuevo := v_def;
  for i in 1 .. array_length(c_reempl, 1) loop
    if (length(v_nuevo) - length(replace(v_nuevo, c_reempl[i][1], ''))) / length(c_reempl[i][1]) <> 1 then
      raise exception 'Parche % de registrar_carga_hormigon: el texto a reemplazar no aparece exactamente una vez', i;
    end if;
    v_nuevo := replace(v_nuevo, c_reempl[i][1], c_reempl[i][2]);
  end loop;

  drop function public.registrar_carga_hormigon(uuid, text, numeric, text, text, timestamp with time zone, text);
  execute v_nuevo;
end;
$mig$;

revoke execute on function public.registrar_carga_hormigon(uuid, text, numeric, text, text, timestamp with time zone, text, date) from public, anon;
grant execute on function public.registrar_carga_hormigon(uuid, text, numeric, text, text, timestamp with time zone, text, date) to authenticated;

-- 3) Vista ----------------------------------------------------------------
create or replace view public.plantas_v_despachos_camion with (security_invoker = true) as
 SELECT 'asfalto'::text AS material,
    v.fecha_pesada AS fecha,
    v.obra_id,
    v.pedido_id,
    v.patente,
    v.chofer,
    (v.numero_vale)::text AS numero_remito,
    v.peso_neto AS volumen,
    v.unidad AS unidad_volumen
   FROM plantas_vales v
  WHERE (v.tipo_vale = 'asfalto'::text)
UNION ALL
 SELECT 'asfalto'::text AS material,
    ca.fecha_carga AS fecha,
    ca.obra_id,
    ca.pedido_id,
    ca.patente,
    NULL::text AS chofer,
    ca.numero_vale AS numero_remito,
    ca.cantidad_tn AS volumen,
    'tn'::text AS unidad_volumen
   FROM plantas_cargas_asfalto ca
UNION ALL
 SELECT coalesce(p.tipo, 'hormigon'::text) AS material,
    ((coalesce(c.fecha_despacho, p.fecha_programada, (c.fecha_carga at time zone 'America/Argentina/Buenos_Aires')::date) + time '12:00')
      at time zone 'America/Argentina/Buenos_Aires') AS fecha,
    c.obra_id,
    c.pedido_id,
    c.patente_mixer AS patente,
    c.chofer,
    c.numero_remito,
    c.volumen_m3 AS volumen,
    CASE WHEN coalesce(p.tipo, 'hormigon'::text) = 'hormigon'::text THEN 'm3'::text ELSE 'tn'::text END AS unidad_volumen
   FROM plantas_cargas_hormigon c
   LEFT JOIN plantas_pedidos p ON p.id = c.pedido_id;

-- ----------------------------------------------------------------------------
-- Chequeos después de aplicar (correr a mano):
--   select oid::regprocedure, proacl from pg_proc where proname = 'registrar_carga_hormigon';
--   select material, unidad_volumen, count(*) from plantas_v_despachos_camion group by 1, 2;
--   select reloptions from pg_class where relname = 'plantas_v_despachos_camion';
-- ----------------------------------------------------------------------------
