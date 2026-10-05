-- ============================================================================
-- Migración 55: módulo de Auditoría, etapa 3 — las funciones de pedidos y despachos
-- registran en plantas_auditoria
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Funciones: crear_pedido, actualizar_pedido, confirmar_pedido, cancelar_pedido, postergar_pedido, archivar_pedido, finalizar_despacho, corregir_despacho, registrar_carga_asfalto, registrar_carga_hormigon.
--
-- Cómo está hecha: NO se reescribe el cuerpo a mano. plantas__auditoria_patch
-- (creada en la 54, borrada en la 59) toma la definición REAL de producción (pg_get_functiondef), verifica por
-- md5 que sea la versión esperada, inserta las llamadas de auditoría en
-- anclas que deben aparecer exactamente una vez, verifica el md5 del
-- resultado y recién ahí la recrea (CREATE OR REPLACE conserva los permisos).
-- Si producción cambió desde el relevamiento, la migración falla sin tocar
-- nada. El cuerpo completo resultante queda en
-- supabase/scripts/referencia_funciones_auditadas.sql (mismo md5).
--
-- La auditoría corre en la misma transacción: si no se puede registrar, la
-- operación falla. Requiere las migraciones 53 y 54.
--
-- Reversión: volver a crear cada función con su cuerpo anterior (última
-- migración que la define; md5 anterior en cada llamada de abajo).
-- ============================================================================

select plantas__auditoria_patch('crear_pedido', 'eae64ae761b28b0b0e8823451cb6593f', '2a889ac9e31ff839242613358156b6ac',
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('CREAR', 'pedido', v_pedido.id);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('actualizar_pedido', 'a8bf0e730198faea63670a487cfcafb1', '839f708da9194edf5237b726014fe5a4',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('EDITAR', 'pedido', p_pedido_id, null, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('confirmar_pedido', '12275ebd05d0690e55146ab5adc9f122', 'b540acb86b43464f2ece54848b347a2b',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'pedido', p_pedido_id, null, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('cancelar_pedido', 'e56ec2b71046cd109a9b2b7dfeb61106', '14876c763a228e876db74a13c7e6ecbe',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('ANULAR', 'pedido', p_pedido_id, p_motivo, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('postergar_pedido', '2ad6b0fac6146b765694fcc0e79ac57e', 'd6cdb4cb9d42e2bfd22b9fb2677fa2b0',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'pedido', p_pedido_id, p_motivo, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('archivar_pedido', 'a5a4e7a0dc4f38e0638a01d082ea7290', '1be71fa1d9cdcebf5bdc97d1a2fd3dd4',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'pedido', p_pedido_id, null, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('finalizar_despacho', 'cf059c246454edbcd20f741d43179490', '1ad19320c736f42b3eba6139518d0531',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$      values (v_nuevo_id, 'confirmado', now(), auth.uid(), 'Residual del ' || v_ref);
$a$,
  $b$      values (v_nuevo_id, 'confirmado', now(), auth.uid(), 'Residual del ' || v_ref);

      perform plantas_auditar_pedido('CREAR', 'pedido', v_nuevo_id);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido('CAMBIAR_ESTADO', 'despacho', p_pedido_id, null, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('corregir_despacho', '30b57f36ff6389df2e292a8683f22fde', '97902d48adcf29fb287572e652cd5465',
  $a$
declare
$a$,
  $b$
declare
  v_aud_antes jsonb;
$b$,
  $a$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
$a$,
  $b$  select * into v_pedido from plantas_pedidos where id = p_pedido_id for update;
  v_aud_antes := to_jsonb(v_pedido);
$b$,
  $a$
  return v_pedido;
end;$a$,
  $b$
  perform plantas_auditar_pedido(case when nullif(btrim(p_notas), '') is null then 'EDITAR' else 'CORREGIR' end, 'despacho', p_pedido_id, p_notas, v_aud_antes);

  return v_pedido;
end;$b$
);

select plantas__auditoria_patch('registrar_carga_asfalto', 'f2bd756f1b67a3be0ddccea18fc39c35', '77bd9e931d40805cf17d24eb7b4b2bb5',
  $a$
  return v_carga;
end;$a$,
  $b$
  perform plantas_auditar('CREAR', 'despachos', 'carga_asfalto', v_carga.numero_vale,
    'Carga vale ' || v_carga.numero_vale || ' — ' || plantas_auditoria_label_pedido(p_pedido_id), null, null, to_jsonb(v_carga));

  return v_carga;
end;$b$
);

select plantas__auditoria_patch('registrar_carga_hormigon', '527a8ec5e0b36ac3064277010a5b4ada', '6df4fe172fc7482ca1d2146253c98fd4',
  $a$
  return v_carga;
end;$a$,
  $b$
  perform plantas_auditar('CREAR', 'despachos', 'carga_hormigon', v_carga.numero_remito,
    'Carga remito ' || v_carga.numero_remito || ' — ' || plantas_auditoria_label_pedido(p_pedido_id), null, null, to_jsonb(v_carga));

  return v_carga;
end;$b$
);

do $chk$
declare
  v_mal text;
begin
  select string_agg(p.proname, ', ') into v_mal
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('crear_pedido', 'actualizar_pedido', 'confirmar_pedido', 'cancelar_pedido', 'postergar_pedido', 'archivar_pedido', 'finalizar_despacho', 'corregir_despacho', 'registrar_carga_asfalto', 'registrar_carga_hormigon')
     and (has_function_privilege('anon', p.oid, 'execute')
          or not has_function_privilege('authenticated', p.oid, 'execute')
          or not p.prosecdef);
  if v_mal is not null then
    raise exception 'MIG55: permisos alterados en: %', v_mal;
  end if;
end;
$chk$;
