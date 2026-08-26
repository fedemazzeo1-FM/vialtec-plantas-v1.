# procedimientos.md — Protocolos operativos

## Deploy — SIEMPRE manual

- El único comando de deploy a producción es:
  ```
  npx vercel --prod
  ```
  ejecutado manualmente, nunca disparado por CI ni por push a GitHub.
- Verificar que el proyecto en Vercel **no** tenga activado el auto-deploy a
  producción desde la integración de Git. Si lo tiene, desactivarlo.
- Antes de deployar a producción:
  1. Confirmar que los cambios están commiteados y con mensaje claro.
  2. Si el cambio toca schema o datos de Supabase, ya se avisó y confirmó con
     Federico (ver abajo) — no deployar cambios de schema sin ese aviso previo.
  3. Correr `npx vercel --prod` desde la rama/estado que se quiere publicar.
  4. Verificar el deploy resultante antes de darlo por cerrado.

## Commits

- Commits claros y acotados a un cambio lógico (no mezclar refactor + feature +
  fix en un mismo commit).
- Mensaje en modo imperativo, describiendo el qué y, si no es obvio, el por qué.
- No commitear credenciales ni claves de Supabase — esas van por variables de
  entorno.

## Reporte previo a Federico ante cambios de schema o datos

**Obligatorio** avisar y esperar confirmación de Federico antes de:
- Crear, alterar o borrar cualquier tabla (`plantas_*` o `flota_*`).
- Correr cualquier migración, script o query que modifique datos existentes en
  producción (UPDATE/DELETE masivos, migración de historial, etc.).
- Tocar cualquier tabla `flota_*`, aunque el cambio parezca menor — es una tabla
  compartida con el sistema de flota en producción y un error ahí puede romper
  ese sistema, no solo VialTec Plantas.

El aviso debe incluir: qué se va a cambiar, por qué, y qué pasa si algo sale mal
(reversibilidad). Recién después de la confirmación se ejecuta.

Ver `architecture.md` (regla de paginación, tablas compartidas) y `pending.md`
(migración de historial, que es el caso donde este protocolo aplica con más
fuerza).
