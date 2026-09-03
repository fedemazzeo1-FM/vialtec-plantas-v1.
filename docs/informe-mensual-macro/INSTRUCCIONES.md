# Informe mensual — botón de mail (instalación única, ~2 minutos)

## Por qué hay que instalar algo una sola vez

Ningún programa (ni esta app, ni ninguna herramienta externa) puede crear un
archivo Excel con una macro ya "compilada" adentro sin que Excel de verdad la
guarde al menos una vez — es una limitación de cómo funciona el formato de
Excel, no de la app. La buena noticia: la instalación es **una sola vez, para
siempre** — después de este paso, el botón funciona con **cualquier informe
mensual** que la app genere de acá en adelante, mes tras mes, sin repetir
nada.

Se instala en el **"Libro de macros personal"** de Excel (`PERSONAL.XLSB`):
un archivo invisible que Excel abre solo en segundo plano cada vez que lo
abrís, y que tiene tus macros personales disponibles en cualquier archivo que
tengas abierto — exactamente lo que hace falta acá.

## Paso a paso

1. Abrí Excel (puede ser con cualquier archivo, o uno en blanco).
2. Menú **Vista → Macros → Grabar macro** (en Mac: **Herramientas → Macro →
   Grabar macro**).
   - Nombre: cualquiera (ej. "temporal").
   - **Guardar macro en: "Libro de macros personal"** ← este paso es el
     importante.
   - Aceptar, y al toque **Detener grabación** (Vista → Macros → Detener
     grabación) — no hace falta grabar nada, esto es solo para que Excel
     cree el archivo `PERSONAL.XLSB` si todavía no existía.
3. Abrí el editor de VBA: **Alt+F11** (Windows) o **Fn+Option+F11** (Mac).
4. En el panel de la izquierda (Project Explorer), buscá
   **VBAProject (PERSONAL.XLSB)** → click derecho → **Insertar → Módulo**.
5. Abrí el archivo `EnviarInformeMensual.bas` (esta misma carpeta) con un
   editor de texto, copiá **todo** el contenido, y pegalo dentro del módulo
   nuevo que acabás de crear en el editor de VBA.
6. **Completá el destinatario habitual** (opcional, pero recomendado): en la
   primera línea con código del módulo, buscá:
   ```vb
   Const DESTINATARIOS_HABITUALES As String = ""
   ```
   y poné ahí el/los mail de quienes reciben el informe todos los meses
   (separados por `;` si son varios), por ejemplo:
   ```vb
   Const DESTINATARIOS_HABITUALES As String = "gerencia@vialtec.com.ar"
   ```
   Si lo dejás vacío, el borrador se abre igual, solo que sin destinatario
   precargado — lo completás vos a mano antes de enviar.
7. Guardá (Ctrl+S / Cmd+S) — Excel va a preguntar si guardar `PERSONAL.XLSB`,
   decís que sí.
8. **Opcional pero recomendado** — agregar un botón real a la barra de
   acceso rápido (así no hay que ir a buscar la macro por menú cada vez):
   - Click derecho en la barra de acceso rápido (arriba de todo) →
     **Personalizar barra de herramientas de acceso rápido**.
   - En "Comandos disponibles en", elegí **Macros**.
   - Buscá `PERSONAL.XLSB!EnviarInformeMensual.EnviarInformeMensual`, click
     **Agregar**, elegí un ícono (ej. el de sobre/mail), Aceptar.
   - A partir de ahora vas a tener un botón fijo, siempre visible, en
     cualquier archivo que abras.

## Uso mensual (todos los meses, después de la instalación)

1. En la app VialTec Plantas → **Despachos → Resumen por obra**, elegí el
   mes y clickeá **"📧 Exportar informe mensual"** — se descarga el `.xlsx`
   con los datos reales de ese mes.
2. Abrí el archivo descargado.
3. Clickeá el botón que agregaste a la barra de acceso rápido (o **Vista →
   Macros → Ver macros → `EnviarInformeMensual` → Ejecutar**).
4. Se abre el mail ya armado — con el resumen del mes, el archivo adjunto, y
   el destinatario si lo configuraste en el paso 6 — revisalo y apretá
   **Enviar** vos mismo. La macro nunca envía nada sola.

## Si Excel bloquea la macro ("Se han deshabilitado las macros")

Es el comportamiento de seguridad normal de Excel con macros que no vienen
firmadas digitalmente. Como el código vive en tu `PERSONAL.XLSB` (un archivo
tuyo, no algo que descargás de internet cada vez), alcanza con habilitarlo
una vez: **Archivo → Opciones → Centro de confianza → Configuración del
Centro de confianza → Configuración de macros → "Deshabilitar todas las
macros con notificación"** (la opción recomendada — vas a ver un aviso cada
vez que se ejecuta una macro, y elegís habilitar).

## Nota sobre la plataforma (Windows/Outlook vs. Mac/Mail)

La macro detecta sola el sistema operativo:
- **Windows**: arma el borrador en **Outlook de escritorio** (necesita estar
  instalado — si usás otro cliente de mail en Windows, avisame para adaptar
  esa parte).
- **Mac**: arma el borrador en **Mail.app** (Correo de Apple) vía
  AppleScript — el cuerpo queda en texto plano prolijo en vez de HTML con
  colores (limitación real de Mail.app vía AppleScript, no de la macro).

Si en tu computadora usás **Gmail/Outlook web** en el navegador en vez de una
app de escritorio, avisame — ese caso no puede adjuntar el archivo
automáticamente desde VBA (es una limitación del propio webmail, no hay
forma de sortearla desde Excel) y hay que armar el flujo distinto: la macro
te arma el texto del mail para copiar/pegar, y adjuntás el Excel a mano.
