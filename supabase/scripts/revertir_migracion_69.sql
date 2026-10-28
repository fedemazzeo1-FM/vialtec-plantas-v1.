-- Reversión de la migración 69: registrar_impresion vuelve a rechazar los
-- vales de ingreso de áridos (md5 d0a41bd80b470b0ddab76e5bf92564da). No toca
-- las filas IMPRIMIR que ya se hayan registrado.
do $rev$
declare
  c_viejo constant text := $v$if v_vale.tipo_vale not in ('asfalto', 'egreso_arido', 'ingreso_arido') then$v$;
  c_nuevo constant text := $v$if v_vale.tipo_vale not in ('asfalto', 'egreso_arido') then$v$;
  v_def   text := pg_get_functiondef('public.registrar_impresion(uuid, text, text, text)'::regprocedure);
begin
  if position(c_viejo in v_def) = 0 then
    raise exception 'registrar_impresion no tiene la versión de la migración 69';
  end if;
  execute replace(v_def, c_viejo, c_nuevo);
  if md5(pg_get_functiondef('public.registrar_impresion(uuid, text, text, text)'::regprocedure)) <> 'd0a41bd80b470b0ddab76e5bf92564da' then
    raise exception 'La reversión no dejó el cuerpo original';
  end if;
end;
$rev$;
