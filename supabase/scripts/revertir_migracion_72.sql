-- Reversión de la migración 72: devuelve a anon los permisos de tabla que
-- tenía (grant por defecto de Supabase) en plantas_formulas y
-- plantas_usuarios_roles. La RLS no cambia.
grant select, insert, update, delete, truncate, references, trigger on table public.plantas_formulas to anon;
grant select, insert, update, delete, truncate, references, trigger on table public.plantas_usuarios_roles to anon;
