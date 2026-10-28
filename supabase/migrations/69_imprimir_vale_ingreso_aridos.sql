-- ============================================================================
-- Migración 69 — registrar_impresion acepta vales de ingreso de áridos
-- ESTADO: APLICADA en producción el 2026-10-28 con OK de Federico (dry-run OK).
-- Reversión: supabase/scripts/revertir_migracion_69.sql.
-- ============================================================================
--
-- Problema (26/10/2026 15:41): balanza@ imprimió desde Báscula el vale de
-- ingreso I-00856 y la base respondió "Este tipo de vale no se imprime."
-- Báscula ofrece el botón "Vale" para ingresos desde el 08/09 (a propósito:
-- ValeImprimible.vue tiene los campos de Proveedor/Remito), pero la migración
-- 65 dejó registrar_impresion solo para asfalto y egreso de áridos. El vale se
-- imprimía igual (el frontend avisa y sigue), sin fila IMPRIMIR en Auditoría.
--
-- Qué hace: suma 'ingreso_arido' a la lista de tipos que se imprimen, solo en
-- modo vale (el remito sigue siendo solo de asfalto: esa validación está
-- antes y no cambia). Parchea el cuerpo de producción con control de md5
-- (mismo método que las migraciones 54 a 59): si el cuerpo no es el esperado,
-- no hace nada y falla.
-- ============================================================================
do $mig$
declare
  c_md5_antes constant text := 'd0a41bd80b470b0ddab76e5bf92564da';
  c_viejo     constant text := $v$if v_vale.tipo_vale not in ('asfalto', 'egreso_arido') then$v$;
  c_nuevo     constant text := $v$if v_vale.tipo_vale not in ('asfalto', 'egreso_arido', 'ingreso_arido') then$v$;
  v_def       text := pg_get_functiondef('public.registrar_impresion(uuid, text, text, text)'::regprocedure);
begin
  if md5(v_def) <> c_md5_antes then
    raise exception 'registrar_impresion cambió en producción (md5 %): revisar antes de aplicar la 69', md5(v_def);
  end if;
  if (length(v_def) - length(replace(v_def, c_viejo, ''))) / length(c_viejo) <> 1 then
    raise exception 'No se encontró exactamente una vez la validación de tipo de vale';
  end if;
  execute replace(v_def, c_viejo, c_nuevo);
end;
$mig$;

-- create or replace conserva los grants (authenticated sí, anon no).
-- Chequeo después de aplicar:
--   select md5(pg_get_functiondef('registrar_impresion'::regproc)), proacl from pg_proc where proname = 'registrar_impresion';
