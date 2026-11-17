-- ============================================================================
-- Vuelta atrás de la migración 78: cada vale manual vuelve a tener su propio remito.
-- Solo se puede si ningún N° de remito quedó compartido entre dos vales (si lo hay, el UNIQUE falla y no se
-- revierte nada: primero hay que decidir qué hacer con esos vales).
-- ============================================================================
begin;
set local lock_timeout = '5s';
create or replace function public.generar_remito_vale_manual(p_vale_id uuid)
returns public.plantas_vales_manuales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes plantas_vales_manuales;
  v_vale  plantas_vales_manuales;
begin
  if not plantas_tiene_permiso('despachos', 'aprobar') then
    raise exception 'Tu rol (%) no puede generar remitos.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;
  select * into v_antes from plantas_vales_manuales where id = p_vale_id for update;
  if not found then
    raise exception 'El vale manual % no existe.', p_vale_id;
  end if;
  if v_antes.numero_remito is not null then
    return v_antes;
  end if;
  if v_antes.anulado then
    raise exception 'El vale % está anulado: no se le puede generar remito.', plantas_etiqueta_vale_manual(v_antes.numero);
  end if;
  update plantas_vales_manuales
     set numero_remito = nextval('plantas_remitos_numero_seq'), remito_generado_en = now(),
         remito_generado_por = coalesce(auth.email(), 'sistema (SQL)')
   where id = p_vale_id
  returning * into v_vale;
  perform plantas_auditar('EDITAR', 'despachos', 'vale_manual', plantas_etiqueta_vale_manual(v_vale.numero),
    plantas_auditoria_label_vale_manual(v_vale) || ' — remito ' || lpad(v_vale.numero_remito::text, 5, '0'),
    null, to_jsonb(v_antes), to_jsonb(v_vale));
  return v_vale;
end;
$$;
drop function if exists public.plantas_grupo_vale_manual(public.plantas_vales_manuales);
drop index if exists public.plantas_vales_manuales_remito_idx;
alter table public.plantas_vales_manuales add constraint plantas_vales_manuales_numero_remito_key unique (numero_remito);
commit;
