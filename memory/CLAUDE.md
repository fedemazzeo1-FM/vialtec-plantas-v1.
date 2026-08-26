# memory/CLAUDE.md — Instrucciones de sesión

## Lectura obligatoria al inicio

Toda sesión nueva sobre este proyecto DEBE, antes de la primera respuesta o acción:

1. Leer los 7 archivos de `memory/` en orden (`CLAUDE.md`, `architecture.md`,
   `business-rules.md`, `conventions.md`, `modules-status.md`, `pending.md`,
   `procedimientos.md`).
2. Confirmar la lectura con un resumen de **una línea por archivo**.

Esto no es opcional ni se puede saltear por "ya lo leí antes" — cada sesión es nueva.

## Política de deploy — manual, siempre

- El deploy a producción se hace **exclusivamente** con `npx vercel --prod`, ejecutado
  a mano después de confirmar con Federico.
- **Nunca** debe configurarse ni depender de auto-deploy de Vercel al hacer push a
  GitHub. Si el proyecto de Vercel tiene la integración de Git conectada con deploy
  automático a producción activado, hay que desactivarlo.
- Detalle del protocolo completo (commits, checklist previo, aviso a Federico ante
  cambios de schema/datos) en `memory/procedimientos.md`.

## Contexto compartido con el sistema de flota

Este proyecto comparte el proyecto de Supabase `ejitztewkpnmrckwmvny` con el sistema
de flota existente. Antes de tocar cualquier tabla `flota_*`, revisar
`memory/architecture.md` para no romper el sistema de flota en producción.

Ver `architecture.md`, `business-rules.md` y `pending.md` para el detalle.
