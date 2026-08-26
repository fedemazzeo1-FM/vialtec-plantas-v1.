# VialTec Plantas — CLAUDE.md (raíz)

## OBLIGATORIO al iniciar CUALQUIER sesión

Antes de responder o ejecutar cualquier acción, es **obligatorio** leer, en este orden,
los 7 archivos de `memory/`:

1. `memory/CLAUDE.md`
2. `memory/architecture.md`
3. `memory/business-rules.md`
4. `memory/conventions.md`
5. `memory/modules-status.md`
6. `memory/pending.md`
7. `memory/procedimientos.md`

Al terminar de leerlos, confirmar con un **resumen de una línea por archivo** (7 líneas)
antes de continuar con la tarea pedida por el usuario.

## Deploy — regla no negociable

**Deploy SIEMPRE manual: `npx vercel --prod`.**
**NUNCA auto-deploy desde GitHub** (ni integración de Vercel con push a `main`, ni CI/CD
que dispare deploy a producción). Ver detalle y protocolo en `memory/procedimientos.md`.

## Sobre este proyecto

VialTec Plantas es el sistema de gestión de producción (asfalto y hormigón) de VialTec.
Comparte el proyecto de Supabase con el sistema de flota (`ejitztewkpnmrckwmvny`):
usa las tablas compartidas `flota_*` (obras, empresas, usuarios, roles) y agrega sus
propias tablas relacionales `plantas_*`. Migra y reutiliza el historial del sistema
anterior (ver `memory/pending.md`).

Detalle completo de stack, reglas de negocio, convenciones y estado de módulos: en `memory/`.
