# Guía de estilo — identidad visual de Flota (equipos2.vialtec.app)

Relevamiento en vivo (navegación real + inspección de `getComputedStyle`/
`className` vía Claude in Chrome, sesión de Federico logueado como
Administrador) del sistema de Flota, para clonar su línea gráfica en
`vialtec-plantas-v2`. Valores tomados directo del DOM real (clases Tailwind
y colores computados), no estimados a ojo desde capturas — donde no se pudo
confirmar un valor exacto, queda marcado explícitamente como tal.

**Stack confirmado del lado de Flota:** Vue (clases `router-link-active` en
el sidebar) + Tailwind con un `tailwind.config.js` propio que agrega tokens
semánticos custom (`vialtec`, `text`, `text-mid`, `text-soft`, `border`,
`red`, `red-light`, `green`, `green-light`, `blue`, `blue-light`, `amber`) —
mismo stack base que `vialtec-plantas-v2` (Vue 3 + Vite + Tailwind), así que
el mapeo es directo, sin necesidad de traducir de otro framework.

**Nuestro `tailwind.config.js` hoy** tiene `theme.extend: {}` vacío — no hay
ningún token propio todavío, así que agregar estos no pisa nada existente.

---

## 1. Paleta de colores (HEX exactos, confirmados)

### Color primario (marca)
| Token Flota | HEX | Uso visto |
|---|---|---|
| `vialtec` | **#7B2F8E** | Botones primarios, link activo del sidebar (con /10 de opacidad de fondo), tabs activos, focus de inputs, avatar de usuario, logo |

### Texto y neutros semánticos (custom, no son el gris de Tailwind)
| Token Flota | HEX | Uso visto |
|---|---|---|
| `text` | **#101828** | Texto principal, títulos de página/modal |
| `text-mid` | **#344054** | Texto secundario (botones outline, hover de tabs) |
| `text-soft` | **#667085** | Labels de KPI, texto terciario, tabs inactivos |
| `border` | **#EAECF0** | Borde de inputs, cards, botones outline |

### Grises (Tailwind default, sin personalizar)
| Clase | HEX |
|---|---|
| `gray-50` | #F9FAFB |
| `gray-200` | #E5E7EB |
| `gray-300` | #D1D5DB |
| `gray-400` | #9CA3AF |
| `gray-500` | #6B7280 |
| `gray-600` | #4B5563 |
| `gray-700` | #374151 |
| `gray-900` | #111827 |

El sidebar y el layout general usan estos grises de stock de Tailwind, no
los tokens custom — solo el contenido (texto de tablas, labels) usa
`text`/`text-mid`/`text-soft`.

### Estados (success/warning/danger/info) — patrón "color" + "color-light"

| Estado | Token base | HEX base | Token claro | HEX claro | Confirmado |
|---|---|---|---|---|---|
| Success | `green` | **#027A48** | `green-light` | **#ECFDF3** | ✅ badge "Cerrado" |
| Danger | `red` | **#B42318** | `red-light` | **#FEF3F2** | ✅ badge "Vencido" |
| Warning | `amber` | **#B54708** | `amber-light` | *(no confirmado — solo vi el punto de estado, no un badge con fondo claro. Por el mismo patrón que green/red debería ser `#FFFAEB`, pero no lo verifiqué en pantalla — confirmarlo antes de darlo por bueno)* | Parcial |
| Info | `blue` | **#1D4ED8** | `blue-light` | **#EFF6FF** | ✅ badge "En compras" |

**Ojo con `blue`/`blue-light`**: a diferencia de `red`/`green` (que son
valores custom tipo Untitled UI, no el azul de Tailwind), `#1D4ED8` y
`#EFF6FF` son **exactamente** `blue-700` y `blue-50` del Tailwind default —
o sea que "info" probablemente esté mapeado directo a la paleta `blue` de
Tailwind sin token propio, mientras que `red`/`green`/`amber` sí son
override customizado. Los reproduzco igual como tokens propios
`danger`/`success`/`warning`/`info` para que nuestro código no dependa de
si es un alias o un valor custom.

Los puntos de estado (KPI de Vencimientos) confirman los 3 colores base:
🔴 vencidos = `bg-red`, 🟠 próximos = `bg-amber`, 🟢 al día = `bg-green`.

---

## 2. Tipografía

- **Fuente**: `Manrope` (Google Fonts, con `preconnect` a
  `fonts.googleapis.com`/`fonts.gstatic.com`), fallback `sans-serif`. Nuestro
  `index.html` hoy no carga ninguna fuente (usa el sans-serif del sistema) —
  hay que agregar el link.
- **Escala de tamaños usada** (todo en clases estándar de Tailwind, sin
  tamaños custom fuera de un par de casos puntuales):
  | Uso | Clase | px |
  |---|---|---|
  | Título de página / modal | `text-lg font-bold` | 18px / 700 |
  | Número de KPI | `text-2xl font-extrabold` | 24px / 800 |
  | Label de KPI (uppercase) | `text-[11px] font-semibold uppercase tracking-wide` | 11px / 600 |
  | Texto de tabla, inputs, botones estándar | `text-sm` | 14px |
  | Badges, botones compactos, encabezado de tabla | `text-xs` | 12px |
  | Encabezado de tabla (`th`) | `text-xs font-bold uppercase` (color `text-soft`) | 12px / 700 |

---

## 3. Layout — Sidebar

- **Ancho expandido**: `216px`. **Ancho colapsado**: `52px` (colapsa a solo
  íconos + un chip cuadrado "VT" en vez del logo completo, con transición
  `transition-all duration-200`). Nuestro `DesktopLayout.vue` hoy es fijo en
  `w-60` (240px) y no colapsa — considerar sumar el toggle.
- **Fondo**: `bg-gray-50`, borde derecho `border-r border-gray-200`.
- **Estructura**: logo arriba (imagen + línea punteada decorativa debajo, en
  el color primario) → secciones agrupadas con título uppercase pequeño
  (`PRINCIPAL`, `OPERACIONES`, `ADMINISTRACIÓN` — mismo patrón que ya usamos
  en `DesktopLayout.vue`) → footer con "Cerrar sesión".
- **Item activo**: `bg-vialtec/10 text-vialtec` (fondo violeta al 10% de
  opacidad + texto violeta), `rounded-lg px-2 py-2 text-sm font-semibold`.
  Confirmado además por `router-link-active`/`router-link-exact-active` de
  Vue Router — mismo mecanismo que ya usamos.
- **Item inactivo**: `text-gray-600 hover:bg-gray-200 hover:text-gray-900`,
  mismas dimensiones/tipografía que el activo.
- **Cada item tiene ícono** (outline, ~16-20px) antes del label — nuestro
  sidebar hoy no tiene íconos, solo texto.

---

## 4. Componentes UI

### Botones — dos tamaños, tres variantes

Base común: `inline-flex items-center justify-center font-semibold
transition-colors duration-150 disabled:cursor-not-allowed disabled:opacity-50 gap-1.5`

| Tamaño | Clases de tamaño | Dónde se usa |
|---|---|---|
| Compacto | `px-[10px] py-[5px] text-xs rounded-md` | Acciones inline de tabla ("Ver detalle", "Imprimir", "Eliminar pedido"), botones de la barra de filtros ("Excel") |
| Estándar | `px-4 py-2 text-sm rounded-lg` | Footer de modales, formularios |

| Variante | Clases | Uso |
|---|---|---|
| Primario | `bg-vialtec text-white hover:opacity-90` | "+ Nuevo equipo", "+ Nuevo Pedido" |
| Secundario / outline | `border border-border text-text-mid hover:bg-gray-50` | "Ver detalle", "Imprimir", "Cerrar" de modal, "Actualizar" (con `border-gray-300 text-gray-700` en vez de `border-border`, variante levemente distinta) |
| Destructivo | `bg-red text-white hover:opacity-90` | "Eliminar pedido" |

Nuestros botones hoy en `PedidosView.vue`/etc. están escritos inline sin un
componente `VButton` compartido — con esta guía conviene crear uno (2 tamaños
× 3 variantes) en `components/shared/`, igual patrón que `VBadge`/`VCard`.

### Badges de estado

`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold
bg-{color}-light text-{color}` — mapea 1:1 con nuestro `VBadge.vue` actual
(mismo concepto de variant), solo hay que ajustar la paleta:

| Nuestro `VBadge` hoy | Equivalente Flota |
|---|---|
| `success` → `bg-green-100 text-green-700` | `bg-green-light text-green` (#ECFDF3 / #027A48) |
| `warning` → `bg-yellow-100 text-yellow-700` | `bg-amber-light text-amber` (#FFFAEB* / #B54708) |
| `danger` → `bg-red-100 text-red-700` | `bg-red-light text-red` (#FEF3F2 / #B42318) |
| `info` → `bg-blue-100 text-blue-700` | `bg-blue-light text-blue` (#EFF6FF / #1D4ED8) |
| `default` → `bg-gray-100 text-gray-700` | sin equivalente visto — mantener |

*`amber-light` no confirmado, ver nota en §1.

### Tabs (subsecciones, ej. "Obra"/"Taller"/"Stock de Insumos")

`pb-2 text-sm font-semibold border-b-2` — activo:
`border-vialtec text-vialtec`; inactivo: `border-transparent text-text-soft
hover:text-text-mid` (o `border-transparent` liso según el otro caso visto).
No tenemos ningún componente de tabs hoy en v2.

### Pills / segmented control (ej. "Pedidos"/"Ítems descartados"/"Pedidos eliminados")

`rounded-full border px-3 py-1 text-sm` — activo: `border-vialtec bg-vialtec
text-white`; inactivo: `border-border text-text-mid`. Tampoco tenemos
equivalente hoy.

### Tarjetas de KPI

```
rounded-xl border border-border bg-white p-[18px] shadow-sm
```
- Label: `text-[11px] font-semibold uppercase tracking-wide text-text-soft`
- Número: `mt-2 text-2xl font-extrabold text-text`
- Punto de estado (opcional, arriba a la derecha): `h-2.5 w-2.5 rounded-full bg-{red|amber|green}`
- Descripción chica debajo del número: gris suave, no confirmé la clase
  exacta pero visualmente es `text-xs text-gray-500`.

Nuestro `VKpiCard.vue` actual — revisar y alinear a este spec (borde +
shadow-sm + radius xl, no lo que tengamos hoy).

### Tablas

- Contenedor: dentro de una card blanca con header colapsable (`⌃ Pedidos —
  Obra`, texto en `text-vialtec font-semibold`, con chevron).
- `thead`: fondo `bg-gray-50`.
- `th`: `text-xs font-bold uppercase` color `text-soft` (#667085), `px-4 py-3
  text-left`.
- `tbody tr`: `hover:bg-gray-50 text-text`, sin bordes internos marcados
  (`border-b` en 0 o muy sutil — el separador visual es más el hover que
  líneas).
- `td`: `px-4 py-3`.
- Primera columna (código/identificador, ej. "01-016", "PED-0189"): en color
  **`text-vialtec`** (violeta), como si fuera un link, aunque no
  necesariamente lo sea. Nuestro `VTable.vue` no distingue la primera
  columna — considerar un slot/prop para eso.

### Inputs

```
rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none
```
Sin box-shadow ni ring en foco — solo cambia el color del borde a
`vialtec`. Nuestros inputs hoy usan `rounded border-gray-300` sin estado de
foco definido explícitamente — alinear.

### Modales

- Backdrop: `fixed inset-0 z-40 flex items-center justify-center bg-black/40 p-4`
- Caja: `w-full max-h-[90vh] overflow-y-auto rounded-xl bg-white shadow-xl` +
  `max-w-3xl` (varía según el modal — este era el de detalle de pedido, con
  bastante contenido).
- Título: `text-lg font-bold text-text`, con botón X de cierre:
  `shrink-0 rounded-md p-1 text-gray-400 hover:bg-gray-200 hover:text-gray-600`.
- Footer: botón "Cerrar" con la variante secundaria estándar (`px-4 py-2
  text-sm rounded-lg ... border border-border text-text-mid hover:bg-gray-50`).

Nuestro `VModal.vue` actual — revisar radius (`xl` no `md`/`lg`), shadow
(`shadow-xl`, más pronunciada que lo que tengamos), y el backdrop
(`bg-black/40`, confirmar que coincide).

### Avatar de usuario

`flex h-8 w-8 items-center justify-center rounded-full bg-vialtec text-xs
font-bold text-white` con iniciales (ej. "F.M."). Aparece en la topbar de
cada vista. No tenemos ningún avatar hoy — `DesktopLayout.vue` solo muestra
nombre+rol en texto plano.

---

## 5. Mapeo a `tailwind.config.js` (propuesta, NO aplicada todavía)

Nuestro `theme.extend` está vacío hoy — esto no pisa nada:

```js
/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{vue,js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        vialtec: '#7B2F8E',
        text: {
          DEFAULT: '#101828',
          mid: '#344054',
          soft: '#667085',
        },
        border: '#EAECF0',
        success: { DEFAULT: '#027A48', light: '#ECFDF3' },
        danger: { DEFAULT: '#B42318', light: '#FEF3F2' },
        warning: { DEFAULT: '#B54708', light: '#FFFAEB' }, // light sin confirmar, ver §1
        info: { DEFAULT: '#1D4ED8', light: '#EFF6FF' },
      },
      fontFamily: {
        sans: ['Manrope', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
```

**Nombres elegidos**: uso `success/danger/warning/info` (semántico) en vez de
`green/red/amber/blue` (el nombre literal que usa Flota) — mismo valor, pero
más legible en nuestro código y consistente con cómo ya nombramos los
`variant` de `VBadge.vue`. Si preferís calcar el nombre exacto de Flota
(`green`/`red`/`amber`/`blue`) para que el mapeo sea 1:1 literal, decímelo y
lo cambio antes de aplicar — es una decisión de naming, no de valores.

**`vialtec` como nombre del token primario**: lo dejé igual que en el
sistema de Flota (útil si en algún momento se comparten componentes/tokens
entre ambos frontends). Alternativa: `primary`. A tu criterio.

**Falta agregar a `index.html`**:
```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&display=swap" rel="stylesheet">
```
(pesos 400/500/600/700/800 cubren todo lo visto: `font-semibold` botones/
badges, `font-bold` títulos, `font-extrabold` KPIs).

---

## 6. Cruce contra lo ya documentado en `memory/` (antes de programar)

Búsqueda explícita en los 9 archivos de `memory/` (grep por hex/paleta/
tipografía/tokens) antes de tocar código: **no hay ningún token de color ni
tipografía de Flota documentado en ningún lado antes de esta guía** — es la
primera fuente de verdad visual del proyecto. Lo que sí ya existía y hay que
conciliar, no crear de cero:

1. **Convención de nombres de componentes** (`conventions.md`): `VCard`,
   `VKpiCard`, `VBadge`, `VTable`, `VSection`, `VModal`, `VSemaforo` — ya
   establecida, el refactor de §4 la respeta (mismos nombres, mismas props,
   solo cambian las clases Tailwind internas).
2. **`VSemaforo.vue`** (código ya existe, sin usar en ningún lado todavía):
   props `estado: 'rojo'|'amarillo'|'verde'`, hoy con colores propios
   (`bg-red-500`/`bg-yellow-400`/`bg-green-500`, tono "500" sólido, distinto
   del tono que usa Flota). Es el mismo concepto que el semáforo de 3 estados
   que vimos en producción real del sistema viejo (`relevamiento-sistema-viejo.md`
   §6: 🟢 OK / 🟠 Ajustado / 🔴 Insuficiente). Al refactorizar, sus colores
   pasan a `bg-danger`/`bg-warning`/`bg-success` (tono base, no el "-light",
   porque acá es un punto sólido chico, no un badge con texto) — se recolorea,
   no se renombra ni se le cambian las props.
3. **Aclaración importante para no confundir los dos "morado"**: el sistema
   viejo de Plantas (`relevamiento-sistema-viejo.md` §7) tiene un banner
   "PLAN DE PRODUCCIÓN" morado oscuro con gradiente — **eso NO se clona**.
   Estamos clonando la identidad de **Flota** (fondo blanco/gris muy claro,
   el morado `vialtec` #7B2F8E se usa solo como acento puntual — botones,
   links, texto activo — nunca como banner de fondo grande). Si en algún
   momento se pide portar ese banner del sistema viejo, es una decisión de
   diseño aparte, no parte de este refactor.

No hubo que completar ningún dato faltante de la guía a partir de esta
búsqueda — los 3 puntos de arriba son reconciliación de lo ya construido
contra la guía nueva, no huecos en la guía misma.

## 7. Pendiente / no confirmado en esta pasada

- `amber-light` exacto (badge de estado "warning" con fondo claro — solo vi
  el punto de color, no un badge completo).
- Estilos de formularios más complejos (selects custom, no llegué a inspeccionar
  uno con el dropdown abierto — probablemente comparten el mismo look que los
  inputs de texto).
- Iconografía exacta del sidebar (qué set de íconos usan — parecen outline,
  posiblemente Heroicons por el estilo, pero no lo confirmé mirando el SVG).
- Breakpoints / comportamiento responsive/mobile — no se probó en viewport chico.
- Tema oscuro: no vi ningún toggle, parece ser solo tema claro.
