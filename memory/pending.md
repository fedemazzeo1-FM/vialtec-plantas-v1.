# pending.md — Pendientes vigentes

> Solo lo que está ABIERTO o es estado actual. El historial completo (3100 líneas,
> hasta 2026-09-19: migración de datos, corte legado → nuevo, fixes de Báscula,
> Stock, Pedidos, Mobile, etc.) está archivado sin cambios en
> `memory/archivo/pending-historico-hasta-2026-09-19.md`. Consultarlo con grep
> cuando haga falta el detalle de una decisión; no hace falta leerlo entero.
> Regla: cuando algo se cierra, se saca de acá y su detalle vive en el archivo.

## 1. Migraciones — estado real (verificado contra producción 2026-09-19)

| N° | Contenido | Estado |
|----|-----------|--------|
| 35 | `plantas_clientes` + tab Clientes en Maestros | **Aplicada** (tabla existe, 3 filas). Este archivo la daba por pendiente: estaba desactualizado. |
| 36 | Remito automático + `plantas_remitos_manuales` | **Aplicada** (tabla existe). |
| 37 | `plantas_remitos_manuales_items` | **Aplicada** (tabla existe). |
| 38–41 | Remito residual hereda N°, remito con origen en Báscula, CRUD camiones, edición de pedidos por creador | Sin verificar una por una. La 40 tiene evidencia (policies de `plantas_patentes` por balancero). |
| 42 | Numeración propia ingreso/egreso de áridos (`I-00001`) | **BORRADOR, NO aplicada.** Ver §2. |
| 43 | Seguridad: revoke de helpers de stock + `security_invoker` en 2 vistas | **Escrita, dry-run OK, NO aplicada.** Ver §3. |

## 2. Migración 42 — numeración `I-00001` (commit `b69aa61`, sin deploy)

Pedido de Federico: la numeración de asfalto no se mezcla con la de ingresos.
Ingreso y egreso de áridos comparten `plantas_vales.numero_vale_arido`
(`I-00001`, desde 1); `numero_vale` queda solo para asfalto/hormigón.
- Archivo: `supabase/migrations/42_numeracion_ingreso_egreso_aridos.sql`.
  `numero_vale` deja de ser identity (nullable, secuencia común que conserva su
  posición, próximo asfalto = 10065), renumera los 514 ingresos/egresos
  existentes por fecha guardando el N° previo en `datos_legados->>'numero_vale_previo'`,
  CHECK anti-mezcla, recrea `registrar_pesada_bascula`/`corregir_vale_bascula`/
  `anular_vale_bascula` y `plantas_v_bascula_viva`.
- Estado medido en producción antes de escribirla: asfalto 442 (9581–10064),
  ingreso 508, egreso 6 (3 anulados), secuencia en 10064.
- **Nunca se ejecutó, ni siquiera el dry-run**: el clasificador de permisos de
  Claude Code bloqueó la prueba (razón "Production Deploy").
- **Orden obligatorio: aplicar la 42 ANTES de deployar el código.** El frontend
  ya consulta `numero_vale_arido`; sin la migración, el header de Báscula
  muestra un error al cargar. Por eso el deploy está en pausa.
- Los 6 egresos con N° de papel del legado también se renumeran (decisión al
  elegir "ingreso y egreso comparten N°").

## 3. Migración 43 — seguridad (archivo escrito, falta aplicar)

Archivo: `supabase/migrations/43_seguridad_helpers_stock_y_vistas.sql`.
Origen: auditoría del 2026-09-19. Autorizada por Federico.
1. `revoke execute` a public/anon/authenticated de `plantas_aplicar_movimiento_stock`,
   `plantas_descontar_stock_despacho`, `plantas_recalcular_stock_vale`. Eran
   SECURITY DEFINER sin chequeo de rol y ejecutables con la anon key pública:
   permitían mover stock real sin login. Sus 7 llamadores son SECURITY DEFINER
   con dueño postgres, no se rompen.
2. `security_invoker = true` en `plantas_v_stock_movimientos_viva` y
   `plantas_v_despachos_camion`. Sin login se leían 1382 movimientos de stock
   (con `responsable_email`) y 614 despachos por camión.
- **Dry-run ejecutado contra producción y revertido (2026-09-19): OK.** admin ve
  1382/614 (~20 ms), plantista 1382/614, encargado 1382/172 (por la matriz, que
  le da `stock:ver`; es intencional), anon 0/0; `anon` y `authenticated` sin
  EXECUTE en los 3 helpers; `registrar_pesada_bascula` sigue ejecutable.
- **Aplicación real bloqueada** por el clasificador ("Protected-Scope IaC
  Apply"). Pendiente: aplicarla desde el SQL Editor de Supabase o habilitar la
  acción en la configuración de permisos, y recién ahí deployar.
- Verificación posterior sugerida: como anon, contar las 2 vistas (debe dar 0) y
  probar Stock → Historial y Báscula con un usuario real.

## 4. Auditoría 2026-09-19 — hallazgos abiertos

**Alto**
- Funciones de flota ejecutables por `anon` (`flota_set_pin`, `hash_pin`,
  `verify_pin`, `flota_auth_login`): SIN analizar, son del sistema de flota
  (tabla/proyecto compartido). Revisar sus cuerpos cuanto antes.
- Además de los 3 helpers de la 43: el resto de las RPC de Plantas siguen
  ejecutables por `anon` (validan rol adentro, pero no hace falta exponerlas);
  `rls_auto_enable()` también.

**Medio**
- `plantas_ingresos.numero_remito` sin UNIQUE: el duplicado solo se valida en la
  RPC (carrera posible entre dos pesadas simultáneas).
- Acciones de `PedidoCard` (8 botones) sin `:disabled`/`:loading`: doble clic
  probablemente muestra un error tras una acción exitosa.
- 68 lugares muestran `e.message` crudo de Postgres vs 30 con mensaje propio;
  29 `Promise.all` sin `allSettled` (una query caída vacía la pantalla).
- 16 materiales con `stock_minimo_kg` null: el semáforo y el banner de alerta de
  Home no pueden alertar bien.
- Vistas puente del legado (`plantas_v_bascula_viva`, `plantas_v_stock_movimientos_viva`):
  sus ramas de `kv_store` devuelven 0 filas hoy (código muerto) y el WindowAgg de
  `acumulado_dia_tn` recorre todo el historial (11 ms con 956 filas, crece lineal).
  Se pueden simplificar y recién ahí cerrar del todo la lectura de `kv_store`.
- `fetchProduccionAnualAsfalto/Hormigon` (Home) sin paginar; `fetchValesDeVariosPedidos`
  y `fetchCargasHormigonDeVariosPedidos` (Informe Mensual) con `.in()` sin
  paginar/lotear. Lejos del límite hoy (`plantas_vales`: 956 filas totales).
- Sin tests automáticos (no hay script `test`).
- Datos a revisar: 36 pedidos de asfalto y 14 de hormigón `despachado` sin
  vales ni cargas; 1 cancelado sin motivo (sin CHECK); 2 pedidos tipo obra sin
  `obra_id` (PRUEBAS-01, ya conocidos).

**Bajo**
- Helpers duplicados (`aTn` ×2, `aFechaISO` ×2, `rangoDelMes` ×3,
  `nombreDestinoPedido` ×2) y el patrón "hormigón m³ / asfalto tn" ×20.
- Exports sin uso: `fetchDetalleDespachosCamion`, `fetchResumenGeneral`,
  `getFormula`, `appConfig`.
- `useBascula.js` con 962 líneas.
- Índices FK faltantes: `plantas_ingresos.vale_id`, `plantas_stock_movimientos.vale_id`
  y `.ingreso_id`, `plantas_usuarios_roles.rol`.
- `plantas_patentes` con 7 policies solapadas; `search_path` mutable en
  `plantas_buscar_material_id` y `plantas_calcular_consumo_kg`; `pg_net` en
  `public`; protección de contraseñas filtradas desactivada.
- Logo de 112 KB mostrado a ~70×30 px.

No medido: tiempos de carga reales en navegador; el flujo de explotación del
punto 1 de la 43 no se probó (habría movido stock real).

## 5. Pendientes operativos (heredados del histórico, sin confirmar en vivo)

- Impresión física: confirmar con una hoja real el rediseño del remito
  (portrait) y el margen de corte del vale.
- Probar en celular real el roadmap Mobile (nav inferior, columnas secundarias,
  autoscroll de Plan Semanal).
- Probar con un email real el flujo "¿Olvidaste tu contraseña?" del login.
- Probar en vivo Editar/Eliminar (anular) de vales de Báscula con un vale de cada
  tipo y el archivado local de Obras (Maestros → Obras).
- Confirmar que el toast de WhatsApp al crear un pedido abre el chat de Daniel
  Natel, y que el filtro de fecha de Báscula sobrevive a imprimir.
- Exportar un Excel y confirmar que el logo ya no sale estirado.
- Migración 36: la secuencia de remitos arranca en 1; si Federico quería que el
  primero diga 0, es un `alter sequence plantas_remitos_numero_seq restart with 0`.
- Baja del legado como fuente de escritura (checklist del corte, §8) y decidir si
  se cierra del todo `kv_store` (hoy: solo lectura para `authenticated`, migración 28).
- Catálogos: 7 clientes del legado sin migrar (la tabla ya existe); umbrales
  mín/máx de stock a transcribir a mano; patente `AD-648-EA` con columnas
  cruzadas; 3 usuarios sin nombre en `flota_usuarios_email` (angel.moreira,
  balanza, juan.heinrich).
- Decididas para después del corte: módulo Auditoría (pantalla), exports
  faltantes (Excel de Pedidos y 5 botones de Despachos). Backup: NO se desarrolla
  (backups de Supabase + export manual).

## 6. Reglas vigentes que salieron del histórico

- Deploy siempre manual `npx vercel --prod`; nunca auto-deploy (ver `procedimientos.md`).
- Pedidos no tiene vista puente con el legado (decisión de Federico, ya cortado).
- Para stock: el descuento por despacho sale de `plantas_pedidos.cantidad_despachada`
  (Pedidos); Báscula es solo auditoría de asfalto. Ingreso/egreso de áridos mueve
  stock directo desde Báscula (`business-rules.md`).
- Antes de tocar una vista con anti-join contra una tabla con RLS, materializar
  la lectura (lección de la migración 25).
- Al recrear una vista, partir de la definición REAL de producción
  (`pg_get_viewdef`), no de un script del repo (falló con la migración 31).
- `revoke ... from public` NO alcanza en Supabase: `anon` y `authenticated` tienen
  grants propios sobre las funciones nuevas (origen del hallazgo crítico de la 43).
  Toda función SECURITY DEFINER interna debe revocarse también a esos dos roles.
