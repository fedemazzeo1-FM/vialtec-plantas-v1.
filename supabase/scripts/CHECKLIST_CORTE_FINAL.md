# Checklist técnico — corte de dominio legado → sistema nuevo

Ver `memory/pending.md` ("Plan de corte definitivo" y "Paso 4") para el
contexto completo. Este archivo es la lista de pasos en orden para el día
del corte — no correr nada de esto sin la confirmación explícita de
Federico en cada paso marcado como tal (protocolo de `memory/procedimientos.md`).

## 0. Antes de arrancar

- [ ] Confirmar con Federico que es el día/momento definitivo (el plan
      original decía lunes 7 o martes 8/9/2026, pero es un objetivo, no
      una fecha cerrada — reconfirmar).
- [ ] Avisar a los operadores que van a dejar de cargar en el legado a
      partir de este momento (el corte asume que nadie escribe en
      `produccion.vialtec.app` durante la ventana de migración).

## 1. Re-correr la auditoría del delta (en vivo, justo antes de migrar)

```
supabase/scripts/auditoria_delta_desde_01_09.sql
```

- [ ] Bloque 4b (colisión de `numero_vale`) tiene que dar **0 filas**. Si
      da alguna, **PARAR** — hay que decidir a mano cómo renumerar antes de
      seguir (no hay una regla automática segura para esto, es juicio caso
      por caso: ¿cuál de los dos vales colisionados es el que se queda con
      el número real?).
- [ ] Bloque 6 (relevamientos nuevos en el legado desde el 01/09): revisar
      si hay alguno más aparte del ya encontrado (2026-09-03) — cada uno
      que aparezca ahí es una decisión de negocio sobre el balance de
      stock, no algo que este checklist resuelva solo (ver punto 3).
- [ ] Anotar los conteos de "pendientes" de cada bloque — van a ser la
      base de comparación contra los `total_*` que reporte el dry-run del
      paso 2.

## 2. Dry-run de la migración final (SIEMPRE antes de la corrida real)

```
supabase/scripts/migracion_final_corte.sql   -- tal cual está, termina en `rollback;`
```

- [ ] Correr completo, revisar los 3 chequeos de integridad (deben dar 0)
      y los `total_*` — la diferencia contra los conteos actuales antes de
      correr tiene que coincidir (a favor u en contra) con lo esperado del
      paso 1 (ver nota abajo sobre por qué el número exacto de cargas de
      hormigón puede no calzar 1:1 con el conteo simple de la auditoría —
      es normal si alguno de los pedidos nuevos migrados es de hormigón y
      trae camiones propios, se resuelven dentro de la misma transacción).
- [ ] `secuencia_actual` (última columna del chequeo de totales) tiene que
      quedar en `max_vale_real` — confirma que el `setval()` corrió bien.
- [ ] **Verificado en dry-run 2026-09-06** (referencia, va a cambiar el día
      real si el legado sigue vivo entre medio): +4 pedidos, +18 eventos de
      historial, +5 cargas de hormigón, +23 vales (20 asfalto + 3
      ingreso_arido), +3 ingresos, +3 movimientos de stock. 0 colisiones de
      `numero_vale`, 0 duplicados, 0 huérfanos. Rollback limpio verificado
      (conteos volvieron exactos al valor previo).

## 3. Decisión de Federico — balance final de `plantas_stock` (NO automatizado)

`migracion_final_corte.sql` **no toca** `plantas_stock` a propósito — ver la
nota de alcance al principio de ese archivo. Elegir una opción antes de
seguir:

- [ ] **Opción A — confiar en el ledger nuevo tal cual**: no hacer nada
      más, `plantas_stock` sigue con lo que el sistema nuevo viene
      acumulando de forma independiente desde el 01/09 (despachos, báscula,
      manual). Más simple, pero no reconcilia el relevamiento que se cargó
      en el legado el 2026-09-03.
- [ ] **Opción B — relevamiento físico fresco el día del corte**: contar
      stock real en planta y cargarlo por "Stock → Relevamiento mensual" en
      el sistema nuevo (ya queda auditado como movimiento `ajuste`,
      `saveStockGuard` incluido). Recomendado si hay dudas sobre cuánto
      drift real acumularon los dos sistemas en paralelo.

## 4. Corrida real de la migración (con commit)

- [ ] Confirmación explícita de Federico registrada (qué se va a migrar,
      los conteos del dry-run, reversibilidad — protocolo de
      `memory/procedimientos.md`).
- [ ] Editar `migracion_final_corte.sql`: cambiar la última línea de
      `rollback;` a `commit;`.
- [ ] Correr. Revisar los mismos chequeos de integridad y `total_*` del
      paso 2, ahora en real.
- [ ] Si se eligió la Opción B del paso 3, cargar el relevamiento físico
      recién ahora (después del commit de arriba, para que el `ajuste`
      quede calculado contra el stock ya completo con el delta migrado).

## 5. Deploy a producción

- [ ] `npx vercel --prod` — **manual, siempre** (`memory/CLAUDE.md`,
      `memory/procedimientos.md`), ejecutado a mano después de confirmar
      con Federico. Nunca disparado por CI/push.
- [ ] Verificar el deploy resultante (URL de Vercel) antes de seguir.

## 6. Cambio de DNS — `produccion.vialtec.app` → sistema nuevo

- [ ] Esto lo tiene que hacer Federico (o quien tenga acceso al proveedor
      de DNS del dominio) — Claude no tiene acceso a ese panel. Apuntar el
      registro de `produccion.vialtec.app` al dominio/deployment de Vercel
      del proyecto nuevo (CNAME o A record, según lo que pida Vercel al
      agregar el dominio custom en el proyecto).
- [ ] Verificar propagación de DNS antes de asumir que ya cambió (puede
      tardar minutos a horas según el TTL configurado).

## 7. Verificación post-corte

- [ ] Smoke test end-to-end contra el dominio real ya migrado (no
      `localhost`) — login real, Pedidos, Báscula, Stock, Despachos,
      Dashboard.
- [ ] Confirmar con los operadores que `produccion.vialtec.app` ahora
      carga el sistema nuevo.

## 8. Dar de baja el legado como fuente de escritura

- [ ] Con el dominio ya apuntando al sistema nuevo, nadie debería poder
      seguir escribiendo en el legado (dependiendo de cómo esté desplegado
      ese sistema — si vive en otro dominio/hosting aparte, hay que
      apagarlo o quitarle el acceso explícitamente).
- [ ] **Recién acá** resolver el hallazgo de seguridad pendiente de
      `kv_store` (policy `"Acceso publico kv"` abierta a `public`/`anon`,
      ver `memory/pending.md`) — con el legado apagado, se puede restringir
      esa RLS sin riesgo de romper su escritura en vivo.

## 9. Limpieza / vistas puente (opcional, no bloqueante)

- [ ] Las vistas puente (`plantas_v_bascula_viva`,
      `plantas_v_stock_movimientos_viva`) quedan sin filas "Legado" para
      mostrar una vez migrado todo el delta — pueden quedar tal cual (no
      hacen daño, simplemente no van a tener nada que aportar) o
      simplificarse más adelante, sin apuro.
