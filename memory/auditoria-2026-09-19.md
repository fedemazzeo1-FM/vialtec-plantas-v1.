# Auditoría general del sistema — 2026-09-19

Revisión pedida por Federico ("solo investigar y proponer, no tocar nada").
Método: lectura del código (`src/`, router, bundle en `dist/`), consultas de solo
lectura y `EXPLAIN` contra producción (`ejitztewkpnmrckwmvny`), advisors de
Supabase (seguridad y performance, leídos completos) y chequeos de consistencia.
Un `SELECT` como rol `anon` para confirmar la exposición. No se ejecutó ninguna
escritura ni se probó el flujo de explotación del hallazgo 1.

Estado de las correcciones: ver `memory/pending.md` (§2, §3 y "Retomar aquí").

## Datos de contexto medidos

- Filas aproximadas: `plantas_stock_movimientos` 1382, `plantas_vales` 956,
  `plantas_pedidos_historial` 608, `plantas_ingresos` 508, `plantas_pedidos` 204,
  `kv_store` 132 (3,7 MB de jsonb). Nada de negocio cerca del corte de 1000 filas
  de PostgREST salvo movimientos de stock (ya paginado).
- Bundle: rutas con carga perezosa (todas menos Login). `exceljs` 917 KB y el PDF
  580 KB son imports dinámicos. `index` 342 KB. Logo PNG 112 KB.
- `plantas_v_bascula_viva`: 11 ms con 956 filas (3 ms son ramas del legado que
  devuelven 0 filas; el WindowAgg recorre todo el historial antes de filtrar).

## ALTO

1. **Helpers internos de stock ejecutables desde la API.**
   `plantas_aplicar_movimiento_stock`, `plantas_descontar_stock_despacho` y
   `plantas_recalcular_stock_vale`: SECURITY DEFINER, sin `plantas_rol_actual()`,
   sin `raise`, ACL `{postgres, anon, authenticated, service_role}`. Cualquiera
   con la anon key pública podía moverlas por `/rest/v1/rpc/...`. Origen: las
   migraciones 13/22/31 hacían `revoke ... from public`, pero en Supabase `anon`
   y `authenticated` tienen grant propio. → Migración 43 (pendiente de aplicar).
2. **Vistas que se saltaban la RLS.** `plantas_v_stock_movimientos_viva` y
   `plantas_v_despachos_camion` sin `security_invoker`, con SELECT para `anon`.
   Como `anon` devolvían 1382 y 614 filas (las tablas base, 0). Datos expuestos:
   `responsable_email`, patentes, choferes, remitos. → Migración 43.
3. **Funciones de flota ejecutables por `anon`** (`flota_set_pin`, `hash_pin`,
   `verify_pin`, `flota_auth_login`). NO se leyeron sus cuerpos: son del sistema
   de flota. Revisar cuanto antes; cualquier cambio requiere el protocolo de
   `procedimientos.md` (tabla/proyecto compartido).
   Además: el resto de las RPC de Plantas y `rls_auto_enable()` también son
   ejecutables por `anon` (las RPC validan rol adentro, `rls_auto_enable` no).

## MEDIO

4. `plantas_ingresos.numero_remito` sin UNIQUE (solo índice común): el chequeo de
   duplicado vive en la RPC, con carrera posible entre dos pesadas simultáneas.
5. Acciones de `PedidoCard` (8 botones) sin `:disabled`/`:loading`. Las RPC tienen
   lock de fila, así que no corrompe datos; el 2º clic probablemente muestra un
   error tras una acción exitosa. No se probó.
6. Errores: 68 sitios muestran `e.message` crudo (ej. "canceling statement due to
   statement timeout") contra 30 con mensaje propio; sin traducción central. 29
   `Promise.all` y ningún `allSettled`: una query caída vacía la pantalla.
7. 16 materiales con `stock_minimo_kg` null: el semáforo y el banner de alerta de
   Home probablemente no alertan.
8. Vistas puente del legado: ramas de `kv_store` muertas (0 filas) + WindowAgg
   sobre todo el historial. Simplificarlas permitiría cerrar del todo la lectura
   de `kv_store` (hoy solo lectura para `authenticated`, migración 28).
9. Sin paginar (corte silencioso en 1000 filas, lejos hoy):
   `fetchProduccionAnualAsfalto`/`fetchProduccionAnualHormigon` (Home, suman en el
   navegador); `fetchValesDeVariosPedidos`/`fetchCargasHormigonDeVariosPedidos`
   (Informe Mensual, `.in()` sin lotes).
10. Sin tests automáticos (sin script `test` ni archivos de test): el mayor riesgo
    para las RPC de stock y numeración.
11. Datos a revisar (no se sabe si son errores): 36 pedidos de asfalto y 14 de
    hormigón `despachado` sin vales/cargas; 1 cancelado sin motivo (sin CHECK);
    2 pedidos tipo obra sin `obra_id` (PRUEBAS-01, conocidos); 13 vales de asfalto
    sin pedido (permitido por regla de negocio); 2 `nro_remito_global` repetidos
    (esperado: el residual hereda el número, migración 38).
12. `memory/pending.md` tenía 3100 líneas (~83k tokens) y estaba desactualizado
    (daba por pendientes las migraciones 35, 36 y 37, ya aplicadas). Resuelto el
    2026-09-19: archivo histórico en `memory/archivo/`.

## BAJO

- Helpers duplicados: `aTn` ×2, `aFechaISO` ×2, `rangoDelMes` ×3,
  `nombreDestinoPedido` ×2; el patrón "hormigón m³ / asfalto tn" se repite ~20
  veces. `useBascula.js` 962 líneas, `PedidosView.vue` 793.
- Exports sin uso: `fetchDetalleDespachosCamion`, `fetchResumenGeneral`,
  `getFormula`, `appConfig`.
- Índices FK faltantes: `plantas_ingresos.vale_id`, `plantas_stock_movimientos.vale_id`
  y `.ingreso_id`, `plantas_usuarios_roles.rol`. 11 índices sin uso (tablas chicas).
- `plantas_patentes` con 7 policies solapadas (advisor `multiple_permissive_policies`).
- `search_path` mutable en `plantas_buscar_material_id` y `plantas_calcular_consumo_kg`;
  `pg_net` instalado en `public`; protección de contraseñas filtradas desactivada.
- Logo de 112 KB mostrado a ~70×30 px.
- Constraints que faltan: `cancelado` ⇒ motivo; `despachado` ⇒ `cantidad_despachada`;
  unicidad de `plantas_cargas_asfalto.numero_vale` (texto, sin relación con
  `plantas_vales.numero_vale`).

## Lo que está bien

Carga perezosa por ruta y exports pesados dinámicos; todos los listados de UI
paginados con `fetchPagina`/`fetchPaginado`; sin `catch` vacíos; RPC mutantes con
validación de rol y (casi todas) lock de fila; consultas de huérfanos en 0
(ingresos, vales de ingreso, historial, movimientos de stock, stock negativo).

## Lo que NO se verificó

- Tiempos de carga reales en navegador (solo tamaños de bundle y planes SQL).
- El flujo de explotación del hallazgo 1 (habría movido stock real).
- Los cuerpos de las funciones de flota.
- UX y validaciones: solo muestreo del código, no exhaustivo.
- Las migraciones 38–41 una por una (la 40 tiene evidencia en las policies).

## Nota sobre la prueba de la migración 43

Dry-run contra producción, transacción abortada a propósito (nada persistió):
`anon`/`authenticated` sin EXECUTE en los 3 helpers; vistas con `security_invoker`;
admin 1382/614 (~20 ms); plantista 1382/614; encargado 1382/172 (la matriz le da
`stock:ver`, intencional); anon 0/0; `registrar_pesada_bascula` sigue ejecutable.
