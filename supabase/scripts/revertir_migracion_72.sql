-- Reversión de la migración 72: devuelve a anon los permisos de tabla que
-- tenía (grant por defecto de Supabase) en las 25 tablas y vistas plantas_*.
-- La RLS no cambia.
grant select, insert, update, delete, truncate, references, trigger on table
  public.plantas_cargas_asfalto,
  public.plantas_cargas_hormigon,
  public.plantas_choferes,
  public.plantas_clientes,
  public.plantas_encargados,
  public.plantas_formulas,
  public.plantas_ingresos,
  public.plantas_materiales,
  public.plantas_obras_locales,
  public.plantas_patentes,
  public.plantas_pedidos,
  public.plantas_pedidos_historial,
  public.plantas_permisos,
  public.plantas_proveedores,
  public.plantas_remitos_manuales,
  public.plantas_remitos_manuales_items,
  public.plantas_roles,
  public.plantas_stock,
  public.plantas_stock_movimientos,
  public.plantas_usuarios_roles,
  public.plantas_vales,
  public.plantas_v_bascula_viva,
  public.plantas_v_despachos_camion,
  public.plantas_v_obras_visibles,
  public.plantas_v_stock_movimientos_viva
to anon;
