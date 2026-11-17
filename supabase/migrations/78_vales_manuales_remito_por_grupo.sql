-- ============================================================================
-- Migración 78: un remito para varios vales manuales — 17/11/2026, pedido de Federico
-- ("la simulación de varios vales, para que en el remito salgan los vales de ese remito").
--
-- Igual que Báscula sin pedido (plantas_acumulado_asfalto / obtenerAcumuladoHastaFecha: por obra y día de
-- Argentina): los vales manuales del MISMO destino (obra o cliente) y del MISMO día AR forman un grupo que
-- comparte UN número de remito. El primero que genera remito toma el siguiente número de la numeración común
-- (plantas_remitos_numero_seq); los demás del grupo reusan ese número (al generar el suyo). El remito muestra el
-- acumulado y la leyenda de los vales del grupo (eso lo arma el front).
--
-- Cambios:
--   - Se saca el UNIQUE de plantas_vales_manuales.numero_remito (ahora lo comparten varios vales).
--   - plantas_grupo_vale_manual(): clave del grupo (destino + día AR).
--   - generar_remito_vale_manual(): reusa el número del grupo si ya hay uno (también de un vale anulado del grupo:
--     ese número ya se usó para ese destino y día); si no, toma uno nuevo. Lock por grupo para que dos generaciones
--     simultáneas no saquen dos números.
-- Sigue sin tocar producción ni stock. Ensayo: supabase/scripts/dry_run_migracion_78.sql.
-- Reversión: supabase/scripts/revertir_migracion_78.sql.
-- ============================================================================

alter table plantas_vales_manuales drop constraint plantas_vales_manuales_numero_remito_key;
create index plantas_vales_manuales_remito_idx on plantas_vales_manuales (numero_remito) where numero_remito is not null;

create function plantas_grupo_vale_manual(p_vale plantas_vales_manuales)
returns text
language sql
stable
set search_path = public
as $$
  select coalesce('obra:' || p_vale.obra_id, 'cliente:' || lower(p_vale.cliente_externo)) || '|'
         || ((p_vale.fecha_pesada at time zone 'America/Argentina/Buenos_Aires')::date)::text
$$;

revoke execute on function plantas_grupo_vale_manual(plantas_vales_manuales) from public, anon;

create or replace function generar_remito_vale_manual(p_vale_id uuid)
returns plantas_vales_manuales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes  plantas_vales_manuales;
  v_vale   plantas_vales_manuales;
  v_grupo  text;
  v_numero bigint;
begin
  if not plantas_tiene_permiso('despachos', 'aprobar') then
    raise exception 'Tu rol (%) no puede generar remitos.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;

  select * into v_antes from plantas_vales_manuales where id = p_vale_id;
  if not found then
    raise exception 'El vale manual % no existe.', p_vale_id;
  end if;
  v_grupo := plantas_grupo_vale_manual(v_antes);
  perform pg_advisory_xact_lock(hashtext('plantas_vales_manuales_remito:' || v_grupo));

  select * into v_antes from plantas_vales_manuales where id = p_vale_id for update;
  if v_antes.numero_remito is not null then
    return v_antes;
  end if;
  if v_antes.anulado then
    raise exception 'El vale % está anulado: no se le puede generar remito.', plantas_etiqueta_vale_manual(v_antes.numero);
  end if;

  select max(numero_remito) into v_numero
    from plantas_vales_manuales
   where numero_remito is not null
     and plantas_grupo_vale_manual(plantas_vales_manuales) = v_grupo;
  v_numero := coalesce(v_numero, nextval('plantas_remitos_numero_seq'));

  update plantas_vales_manuales
     set numero_remito       = v_numero,
         remito_generado_en  = now(),
         remito_generado_por = coalesce(auth.email(), 'sistema (SQL)')
   where id = p_vale_id
  returning * into v_vale;

  perform plantas_auditar('EDITAR', 'despachos', 'vale_manual', plantas_etiqueta_vale_manual(v_vale.numero),
    plantas_auditoria_label_vale_manual(v_vale) || ' — remito ' || lpad(v_vale.numero_remito::text, 5, '0'),
    null, to_jsonb(v_antes), to_jsonb(v_vale));

  return v_vale;
end;
$$;

comment on function generar_remito_vale_manual is
  'Asigna el N° de remito a un vale manual (migración 78): los vales del mismo destino y día AR comparten un remito; el primero toma el siguiente de plantas_remitos_numero_seq y los demás reusan ese número. Idempotente. Permiso despachos/aprobar.';
