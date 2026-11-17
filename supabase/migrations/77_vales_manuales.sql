-- ============================================================================
-- Migración 77: Vales manuales (simulaciones) — 17/11/2026, pedido de Federico
-- Proyecto Supabase compartido con el sistema de flota (ref: ejitztewkpnmrckwmvny)
--
-- Qué es: un vale con el mismo formato que el de balanza, generado a mano desde
-- Despachos, para retiros que no pasaron por la báscula. Federico (17/11):
-- "son simulaciones", "no suma", "prioridad que quede bien armado y no ensucie
-- la producción". Por eso:
--   - Tabla PROPIA (plantas_vales_manuales), no plantas_vales: no entra en los
--     acumulados por pedido, ni en Báscula, ni en Despachos/Home/analítica/
--     informe mensual (todos leen plantas_pedidos o plantas_vales).
--   - Sin pedido: destino = una obra (flota_obras) o un cliente externo (texto,
--     como plantas_pedidos.cliente_externo).
--   - No toca stock: no llama a plantas_aplicar_movimiento_stock ni a ninguna
--     función de stock.
--   - Bruto y tara de libre escritura (como en Báscula); neto = bruto − tara.
--   - Numeración propia: plantas_vales_manuales_numero_seq → "M-00001".
--   - Remito: "Generar remito" le asigna UNA vez el siguiente N° de la numeración
--     de remitos (plantas_remitos_numero_seq, la misma de asfalto y remitos
--     manuales); reimprimir usa el mismo número.
--   - Nunca se borra ni se edita: se anula con motivo. Todo queda en
--     plantas_auditoria (módulo despachos, entidad vale_manual).
--   - Escritura solo por las 3 RPC (SECURITY DEFINER), con el permiso
--     despachos/aprobar (el mismo que generar_remito_manual: admin, plantista,
--     plantista_hormigon).
--
-- No modifica ninguna tabla ni función existente; solo agrega una fila al
-- catálogo plantas_auditoria_entidades. Ensayo: supabase/scripts/
-- dry_run_migracion_77.sql. Reversión: supabase/scripts/revertir_migracion_77.sql.
-- ============================================================================

create sequence plantas_vales_manuales_numero_seq minvalue 1;

create table plantas_vales_manuales (
  id                    uuid primary key default gen_random_uuid(),
  numero                bigint not null unique default nextval('plantas_vales_manuales_numero_seq'),
  fecha_pesada          timestamptz not null,
  obra_id               bigint references flota_obras (id),
  cliente_externo       text,
  formula_id            uuid not null references plantas_formulas (id),
  patente               text,
  chofer                text,
  peso_bruto            numeric not null check (peso_bruto > 0),
  tara                  numeric not null check (tara >= 0),
  peso_neto             numeric not null check (peso_neto > 0),
  temperatura           numeric,
  observaciones         text,
  numero_remito         bigint unique,
  remito_generado_en    timestamptz,
  remito_generado_por   text,
  creado_por            text not null,
  created_at            timestamptz not null default now(),
  anulado               boolean not null default false,
  anulado_en            timestamptz,
  anulado_por           text,
  motivo_anulacion      text,
  constraint plantas_vales_manuales_neto_chk check (peso_neto = peso_bruto - tara),
  constraint plantas_vales_manuales_destino_chk check (num_nonnulls(obra_id, cliente_externo) = 1),
  constraint plantas_vales_manuales_anulacion_chk check (
    (not anulado and anulado_en is null and motivo_anulacion is null)
    or (anulado and anulado_en is not null and nullif(btrim(motivo_anulacion), '') is not null)
  ),
  constraint plantas_vales_manuales_remito_chk check ((numero_remito is null) = (remito_generado_en is null))
);

alter sequence plantas_vales_manuales_numero_seq owned by plantas_vales_manuales.numero;

comment on table plantas_vales_manuales is
  'Vales manuales (migración 77, 17/11/2026): SIMULACIONES con el formato del vale de balanza, para retiros que no pasaron por la báscula. No suman a producción/despachos ni tocan stock (tabla propia, nadie la lee para totales). Sin pedido. Numeración propia (M-00001). Solo se escribe por generar_vale_manual / generar_remito_vale_manual / anular_vale_manual.';

create index plantas_vales_manuales_fecha_idx on plantas_vales_manuales (fecha_pesada desc);

alter table plantas_vales_manuales enable row level security;

-- Solo lectura para quien puede ver Despachos; ninguna escritura directa.
revoke all on plantas_vales_manuales from anon, authenticated;
grant select on plantas_vales_manuales to authenticated;
revoke all on sequence plantas_vales_manuales_numero_seq from anon, authenticated;

create policy "plantas_vales_manuales: leer" on plantas_vales_manuales
  for select to authenticated using (plantas_tiene_permiso('despachos', 'ver'));

insert into plantas_auditoria_entidades (modulo, entidad, modulo_etiqueta, entidad_etiqueta, orden)
values ('despachos', 'vale_manual', 'Despachos', 'Vale manual', 23);

-- Etiqueta visible: "M-00001" (gemela de formatearNumeroValeManual en el front).
create function plantas_etiqueta_vale_manual(p_numero bigint)
returns text
language sql
immutable
set search_path = public
as $$
  select 'M-' || lpad(p_numero::text, 5, '0')
$$;

create function plantas_auditoria_label_vale_manual(p_vale plantas_vales_manuales)
returns text
language sql
stable
set search_path = public
as $$
  select 'Vale manual ' || plantas_etiqueta_vale_manual(p_vale.numero) || ' — '
         || coalesce((select nombre from flota_obras where id = p_vale.obra_id), p_vale.cliente_externo, '?')
         || ' — ' || plantas_numero_ar(p_vale.peso_neto, 2) || ' tn'
$$;

-- ----------------------------------------------------------------------------
-- generar_vale_manual
-- ----------------------------------------------------------------------------
create function generar_vale_manual(
  p_fecha_pesada    timestamptz,
  p_formula_id      uuid,
  p_peso_bruto      numeric,
  p_tara            numeric,
  p_obra_id         bigint default null,
  p_cliente_externo text default null,
  p_patente         text default null,
  p_chofer          text default null,
  p_temperatura     numeric default null,
  p_observaciones   text default null
)
returns plantas_vales_manuales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_vale    plantas_vales_manuales;
  v_cliente text := nullif(btrim(coalesce(p_cliente_externo, '')), '');
begin
  if not plantas_tiene_permiso('despachos', 'aprobar') then
    raise exception 'Tu rol (%) no puede generar vales manuales.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;
  if p_fecha_pesada is null then
    raise exception 'La fecha es obligatoria.';
  end if;
  if num_nonnulls(p_obra_id, v_cliente) <> 1 then
    raise exception 'Elegí una obra o un cliente externo (uno solo).';
  end if;
  if p_obra_id is not null and not exists (select 1 from flota_obras where id = p_obra_id) then
    raise exception 'La obra % no existe.', p_obra_id;
  end if;
  if not exists (select 1 from plantas_formulas where id = p_formula_id and tipo = 'asfalto') then
    raise exception 'Elegí una mezcla de asfalto.';
  end if;
  if not (p_peso_bruto > 0) then
    raise exception 'El peso bruto debe ser mayor a 0.';
  end if;
  if not (p_tara >= 0) then
    raise exception 'La tara no puede ser negativa.';
  end if;
  if not (p_peso_bruto > p_tara) then
    raise exception 'El peso bruto debe ser mayor que la tara.';
  end if;

  insert into plantas_vales_manuales (
    fecha_pesada, obra_id, cliente_externo, formula_id, patente, chofer,
    peso_bruto, tara, peso_neto, temperatura, observaciones, creado_por
  ) values (
    p_fecha_pesada, p_obra_id, v_cliente, p_formula_id,
    nullif(upper(btrim(coalesce(p_patente, ''))), ''), nullif(btrim(coalesce(p_chofer, '')), ''),
    p_peso_bruto, p_tara, p_peso_bruto - p_tara, p_temperatura,
    nullif(btrim(coalesce(p_observaciones, '')), ''), coalesce(auth.email(), 'sistema (SQL)')
  )
  returning * into v_vale;

  perform plantas_auditar('CREAR', 'despachos', 'vale_manual', plantas_etiqueta_vale_manual(v_vale.numero),
    plantas_auditoria_label_vale_manual(v_vale), null, null, to_jsonb(v_vale));

  return v_vale;
end;
$$;

comment on function generar_vale_manual is
  'Genera un vale manual (simulación, migración 77): no suma a producción ni toca stock. Permiso despachos/aprobar. Queda auditado.';

-- ----------------------------------------------------------------------------
-- generar_remito_vale_manual: asigna el N° de remito una sola vez (idempotente:
-- reimprimir devuelve el mismo número y no audita de nuevo).
-- ----------------------------------------------------------------------------
create function generar_remito_vale_manual(p_vale_id uuid)
returns plantas_vales_manuales
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
     set numero_remito       = nextval('plantas_remitos_numero_seq'),
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
  'Asigna (una sola vez) el N° de remito a un vale manual, de la misma numeración que los remitos de asfalto y los remitos manuales (migración 77). Idempotente. Permiso despachos/aprobar.';

-- ----------------------------------------------------------------------------
-- anular_vale_manual: motivo obligatorio; no se borra.
-- ----------------------------------------------------------------------------
create function anular_vale_manual(p_vale_id uuid, p_motivo text)
returns plantas_vales_manuales
language plpgsql
security definer
set search_path = public
as $$
declare
  v_antes plantas_vales_manuales;
  v_vale  plantas_vales_manuales;
begin
  if not plantas_tiene_permiso('despachos', 'aprobar') then
    raise exception 'Tu rol (%) no puede anular vales manuales.', coalesce(plantas_rol_actual(), 'sin rol asignado');
  end if;
  if nullif(btrim(coalesce(p_motivo, '')), '') is null then
    raise exception 'El motivo de anulación es obligatorio.';
  end if;

  select * into v_antes from plantas_vales_manuales where id = p_vale_id for update;
  if not found then
    raise exception 'El vale manual % no existe.', p_vale_id;
  end if;
  if v_antes.anulado then
    raise exception 'El vale % ya está anulado.', plantas_etiqueta_vale_manual(v_antes.numero);
  end if;

  update plantas_vales_manuales
     set anulado          = true,
         anulado_en       = now(),
         anulado_por      = coalesce(auth.email(), 'sistema (SQL)'),
         motivo_anulacion = btrim(p_motivo)
   where id = p_vale_id
  returning * into v_vale;

  perform plantas_auditar('ANULAR', 'despachos', 'vale_manual', plantas_etiqueta_vale_manual(v_vale.numero),
    plantas_auditoria_label_vale_manual(v_vale), btrim(p_motivo), to_jsonb(v_antes), to_jsonb(v_vale));

  return v_vale;
end;
$$;

comment on function anular_vale_manual is
  'Anula un vale manual con motivo obligatorio (no se borra). Si ya tenía remito, ese número queda usado; un vale anulado no se vuelve a imprimir. Permiso despachos/aprobar. Migración 77.';

-- Permisos de ejecución: solo authenticated (nunca anon ni public).
revoke execute on function generar_vale_manual(timestamptz, uuid, numeric, numeric, bigint, text, text, text, numeric, text) from public, anon;
revoke execute on function generar_remito_vale_manual(uuid) from public, anon;
revoke execute on function anular_vale_manual(uuid, text) from public, anon;
revoke execute on function plantas_etiqueta_vale_manual(bigint) from public, anon;
revoke execute on function plantas_auditoria_label_vale_manual(plantas_vales_manuales) from public, anon;
grant execute on function generar_vale_manual(timestamptz, uuid, numeric, numeric, bigint, text, text, text, numeric, text) to authenticated;
grant execute on function generar_remito_vale_manual(uuid) to authenticated;
grant execute on function anular_vale_manual(uuid, text) to authenticated;
