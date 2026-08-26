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

## Descuento de stock

- El stock se maneja **internamente en kg**, siempre. La UI puede mostrar tn
  (÷1000), pero todo cálculo interno es en kg.
- El descuento ocurre **al despachar** (no al confirmar), y es automático:
  para cada insumo de la fórmula, `consumo_kg = insumo × cantidadReal` (con la
  conversión de unidad correspondiente: `%`, `tn`, `kg`, `L` — ver fórmula del
  módulo Fórmulas).
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
