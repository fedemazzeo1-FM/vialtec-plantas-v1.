# business-rules.md — Reglas de negocio

Fuente: relevamiento del sistema legado (`Logica sis. plantas v1.rtf` /
`Logica sist plantas v2.rtf` en la raíz del proyecto). Estas reglas son las que el
sistema nuevo debe preservar al migrar.

## Flujo de pedidos

```
SOLICITADO → CONFIRMADO → DESPACHADO
           ↘ POSTERGADO → CONFIRMADO → DESPACHADO
           ↘ CANCELADO (requiere motivo obligatorio, no descuenta stock, no se reactiva)
```

- **Solicitado → Confirmado**: solo plantista/admin. Encargados/supervisores pueden
  crear pedidos (quedan en `solicitado`) pero **no pueden confirmar ni despachar**.
- **Confirmado → Despachado**: solo plantista/admin. Se cargan las cargas
  (una o varias, ej. por camión), `cantidadReal` = suma de las cargas. Si
  `cantidadReal < cantidad` se puede dividir el pedido: se crea automáticamente un
  nuevo pedido `confirmado` con la cantidad residual para una fecha futura.
- **Postergado**: cambia de fecha, el historial guarda fecha original y nueva.
- Todo cambio de estado queda en el historial del pedido (timestamp + usuario).
- Los pedidos **nunca se eliminan**, solo se archivan (pedidos despachados/cancelados
  de semanas anteriores). El archivado no debe romper reportes históricos.

## Fuente de verdad según el tipo de transacción (Federico, 2026-08-31)

Distinción operativa fundamental para Despachos y para el futuro módulo Stock
— dos flujos con fuente de verdad distinta, no intercambiables:

1. **Despachos de asfalto/hormigón (ventas a obra)**: la fuente de verdad del
   total despachado es la `cantidadReal` cargada en **Pedidos**
   (`plantas_pedidos.cantidad_despachada`), tomada del **remito final
   consolidado**. Báscula (`plantas_vales`, tipo asfalto) aporta el detalle
   de vales/camiones **solo para auditoría** — no es de donde sale el total
   oficial ni se suma/dedupe contra `plantas_cargas_asfalto`. Ver
   `plantas_v_despachos_camion` (migración 12): vista de detalle por camión,
   deliberadamente sin deduplicar entre Báscula y Pedidos, y explícitamente
   **no** usada para calcular ningún total oficial (eso sale siempre de
   `plantas_pedidos.cantidad_despachada`).
2. **Ingreso de proveedores y egreso de áridos**: son transacciones
   **directas de Báscula**, sin pasar por Pedidos. Acá la suma/resta de stock
   sí tiene que ser 100% automática a partir del **peso neto real** de cada
   pesada (`plantas_vales.peso_neto`, tipos `ingreso_arido`/`egreso_arido`),
   no de un valor declarado en otro módulo. (Nota: el ingreso de áridos ya es
   la excepción reglada en `business-rules.md` más abajo — ver "Ingresos de
   áridos por báscula": ahí el **stock** se actualiza por la cantidad
   **declarada en el remito**, no por el peso neto; el peso neto solo se
   registra para seguimiento de la diferencia. El egreso de áridos, en
   cambio, no tiene remito de origen — ahí sí el peso neto pesado **es** el
   valor que mueve stock, sin intermediario.)

Cuando se construya el módulo Stock (`plantas_stock`, hoy PENDIENTE), el
descuento por despacho tiene que engancharse a `finalizar_despacho()`/
`corregir_despacho()` (Pedidos), y el movimiento de ingreso/egreso de áridos
tiene que engancharse a `registrar_pesada_bascula()` (Báscula) — dos
integraciones separadas, cada una a su propio "TODO(stock)" ya marcado en el
código (`pedidos.service.js`, `supabase/migrations/09_*.sql` dentro de
`registrar_pesada_bascula`).

## Descuento de stock

- El stock se maneja **internamente en kg**, siempre. La UI puede mostrar tn
  (÷1000), pero todo cálculo interno es en kg.
- El descuento ocurre **al despachar** (no al confirmar), y es automático:
  para cada insumo de la fórmula, `consumo_kg = insumo × cantidadReal` (con la
  conversión de unidad correspondiente: `%`, `tn`, `kg`, `L` — ver fórmula del
  módulo Fórmulas). **cantidadReal acá es siempre `plantas_pedidos.cantidad_despachada`
  (Pedidos), no una suma sobre vales de Báscula** — ver sección de arriba.
- Materiales que **nunca se descuentan**: Agua y Purgue (excluidos explícitamente).
- Antes de modificar stock, siempre se debe leer el valor **fresco desde la DB**
  (nunca el estado en memoria del cliente), para evitar que dos operaciones
  concurrentes se pisen.
- Cualquier guardado de stock que implique una caída anómala (ej. la mayoría de los
  materiales pasan a tener valor "vacío", o el total cae drásticamente) debe
  poder cancelarse y alertar, en vez de aplicarse silenciosamente — es una
  protección contra bugs de UI que vacíen el inventario sin que nadie lo note.

## Alerta de stock sin bloqueo duro

- El sistema **alerta** cuando el stock proyectado no alcanza para los pedidos
  confirmados de la semana (o queda por debajo de un umbral), pero **no bloquea**
  la confirmación de un pedido por falta de stock.
- Es decisión del plantista confirmar igual aunque falte stock (por ejemplo, porque
  sabe que va a entrar un ingreso de material antes de la fecha de despacho). El
  sistema informa, no decide por el usuario.

## Vales de báscula — numeración

- Los vales de pesaje usan una **secuencia numérica nativa y global**, que
  **empieza en 9579** (continuidad con la numeración en papel que ya usaba la
  planta antes del sistema — no se reinicia en 1).
- El acumulado que figura en cada vale (total despachado del día para ese
  pedido/obra) se **recalcula dinámicamente** al momento de imprimir/consultar, no
  se toma como dato fijo guardado — evita inconsistencias si se edita un vale
  anterior.
- Un vale puede no estar asociado a ningún pedido del sistema (despacho de
  emergencia); en ese caso el acumulado se agrupa por nombre de obra/destino.

## Ingresos de áridos por báscula

- El stock se actualiza con la **cantidad declarada en el remito**
  (`cantidadRemito × 1000` kg), **no** con el peso neto pesado en báscula. La
  diferencia entre lo pesado y lo declarado se registra para seguimiento, pero no
  modifica el stock ni el remito (el remito es la cantidad comprometida
  contractualmente con el proveedor).

## Semana operativa

- La semana va de **lunes a domingo**, calculada dinámicamente desde la fecha
  actual (no hardcodeada). Dashboard y plan semanal se basan en esto.

## Roles (heredados del sistema de flota / a reconciliar con `flota_*`)

7 roles: `admin`, `plantista`, `encargado`, `supervisor`, `balancero`, `gerencia`,
`plantista_hormigon`. Un encargado/supervisor solo ve pedidos de sus obras
asignadas, salvo que tenga `verTodasObras = true`. Ventas externas solo visibles
con `verVentas = true`. Confirmar en `pending.md`/con Federico cómo se mapea esto
sobre el modelo de roles/usuarios ya existente en `flota_*`.

Ver `pending.md` para el detalle de qué falta migrar del sistema anterior.
