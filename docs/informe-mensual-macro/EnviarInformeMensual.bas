Attribute VB_Name = "EnviarInformeMensual"
' ============================================================================
' EnviarInformeMensual — VialTec Plantas
' Arma un BORRADOR de mail (nunca lo envía solo) con el resumen del informe
' mensual de producción, y le adjunta el propio archivo Excel abierto.
'
' 100% DINÁMICO: no hay ningún mes, obra, cliente ni cantidad escrito a
' mano acá — todo se lee de las celdas de "Resumen mensual"/"Resumen anual"
' del libro que esté ABIERTO y ACTIVO al ejecutar la macro (ActiveWorkbook).
' El Excel lo genera la app VialTec Plantas (Despachos → Resumen por obra →
' "Exportar informe mensual") con los datos reales de cada mes — esta macro
' solo LEE lo que ya está en las celdas, no vuelve a consultar ninguna base.
'
' Las cifras clave (TOTAL GENERAL, Subtotal interno/externo, TOTAL ACUMULADO)
' se buscan por TEXTO en la hoja, no por número de fila fijo — la cantidad
' de obras/clientes cambia todos los meses, así que la fila de esos totales
' también cambia. Si mañana el Excel tiene una obra más, la macro la sigue
' encontrando sola.
'
' INSTALACIÓN (una sola vez): ver INSTRUCCIONES.md en esta misma carpeta.
' Recomendado instalarla en el "Libro de macros personal" (PERSONAL.XLSB) —
' así queda disponible para CUALQUIER informe que abras, sin tener que
' volver a instalarla cada mes con cada archivo nuevo que genera la app.
'
' Plataforma: funciona tanto en Excel para Windows (automatiza Outlook de
' escritorio vía COM) como en Excel para Mac (automatiza Mail.app vía
' AppleScript) — detecta el sistema operativo solo, no hace falta tocar
' nada. En Mac, el cuerpo queda en texto plano prolijo (AppleScript no
' soporta HTML rico en Mail de forma confiable); en Windows queda en HTML
' con los mismos colores de marca que la app.
' ============================================================================

Option Explicit

' Completar UNA VEZ con el/los destinatarios habituales del informe (separados
' por ";" si son varios) — se deja vacío a propósito, no es un dato que la
' app pueda "adivinar": lo llenás vos según a quién le mandás el informe cada
' mes. Si lo dejás vacío, el borrador se abre igual, sin destinatario, y lo
' completás a mano antes de enviar.
Const DESTINATARIOS_HABITUALES As String = ""

Sub EnviarInformeMensual()
    Dim wb As Workbook
    Set wb = ActiveWorkbook

    If wb Is Nothing Then
        MsgBox "Abrí primero el archivo del informe mensual (el que exportaste desde Despachos → Resumen por obra en la app) y volvé a ejecutar la macro.", vbExclamation
        Exit Sub
    End If

    Dim wsMensual As Worksheet, wsAnual As Worksheet
    On Error Resume Next
    Set wsMensual = wb.Worksheets("Resumen mensual")
    Set wsAnual = wb.Worksheets("Resumen anual")
    On Error GoTo 0

    If wsMensual Is Nothing Or wsAnual Is Nothing Then
        MsgBox "Este archivo no tiene las hojas 'Resumen mensual' y 'Resumen anual' esperadas — ¿es un informe exportado desde la app VialTec Plantas?", vbExclamation
        Exit Sub
    End If

    ' ------------------------------------------------------------------
    ' 1) Leer los datos del mes — todo dinámico, buscado por texto.
    ' ------------------------------------------------------------------
    Dim mesLabel As String
    mesLabel = Replace(wsMensual.Range("A2").Value, "Informe mensual de producción — ", "")

    Dim filaTotalGeneral As Long, filaSubInterno As Long, filaSubExterno As Long
    filaTotalGeneral = BuscarFilaPorTexto(wsMensual, "TOTAL GENERAL")
    filaSubInterno = BuscarFilaPorTexto(wsMensual, "Subtotal interno")
    filaSubExterno = BuscarFilaPorTexto(wsMensual, "Subtotal externo")

    If filaTotalGeneral = 0 Then
        MsgBox "No encontré la fila 'TOTAL GENERAL' en 'Resumen mensual' — revisá que el archivo no esté editado a mano de forma que rompa la estructura.", vbExclamation
        Exit Sub
    End If

    Dim despachosTotal As String, hormigonTotal As String, asfaltoTotal As String
    despachosTotal = wsMensual.Cells(filaTotalGeneral, 3).Value
    hormigonTotal = wsMensual.Cells(filaTotalGeneral, 4).Value
    asfaltoTotal = wsMensual.Cells(filaTotalGeneral, 5).Value

    Dim hormigonInterno As String, asfaltoInterno As String
    Dim hormigonExterno As String, asfaltoExterno As String
    If filaSubInterno > 0 Then
        hormigonInterno = wsMensual.Cells(filaSubInterno, 4).Value
        asfaltoInterno = wsMensual.Cells(filaSubInterno, 5).Value
    End If
    If filaSubExterno > 0 Then
        hormigonExterno = wsMensual.Cells(filaSubExterno, 4).Value
        asfaltoExterno = wsMensual.Cells(filaSubExterno, 5).Value
    End If

    ' Acumulado anual: última fila con datos de "Resumen anual" (fila
    ' "TOTAL ACUMULADO", siempre la última — no hace falta buscarla por
    ' texto, pero se valida el texto igual por prolijidad/seguridad).
    Dim ultimaFilaAnual As Long
    ultimaFilaAnual = wsAnual.Cells(wsAnual.Rows.Count, 1).End(xlUp).Row
    Dim tituloAnual As String, hormigonAcumulado As String, asfaltoAcumulado As String
    tituloAnual = wsAnual.Range("A1").Value
    hormigonAcumulado = wsAnual.Cells(ultimaFilaAnual, 2).Value
    asfaltoAcumulado = wsAnual.Cells(ultimaFilaAnual, 3).Value

    ' ------------------------------------------------------------------
    ' 2) Armar el asunto y el cuerpo (rama Windows/Outlook vs Mac/Mail).
    ' ------------------------------------------------------------------
    Dim asunto As String
    asunto = "Informe mensual de producción — " & mesLabel & " — VialTec"

    Dim rutaAdjunto As String
    rutaAdjunto = wb.FullName
    If wb.Path = "" Then
        MsgBox "Guardá el archivo antes de generar el mail (todavía no tiene una ubicación en disco, así que no se puede adjuntar).", vbExclamation
        Exit Sub
    End If

#If Mac Then
    EnviarConAppleMail asunto, CuerpoTextoPlano(mesLabel, despachosTotal, hormigonTotal, asfaltoTotal, _
        hormigonInterno, asfaltoInterno, hormigonExterno, asfaltoExterno, _
        tituloAnual, hormigonAcumulado, asfaltoAcumulado), rutaAdjunto
#Else
    EnviarConOutlook asunto, CuerpoHtml(mesLabel, despachosTotal, hormigonTotal, asfaltoTotal, _
        hormigonInterno, asfaltoInterno, hormigonExterno, asfaltoExterno, _
        tituloAnual, hormigonAcumulado, asfaltoAcumulado), rutaAdjunto
#End If
End Sub

' ----------------------------------------------------------------------
' Busca la primera fila donde `texto` aparece (como substring) en
' cualquier celda de las columnas A o B — así no importa el número de
' fila real (depende de cuántas obras/clientes tenga el mes).
' ----------------------------------------------------------------------
Private Function BuscarFilaPorTexto(ws As Worksheet, texto As String) As Long
    Dim ultimaFila As Long, i As Long
    ultimaFila = ws.Cells(ws.Rows.Count, 2).End(xlUp).Row
    For i = 1 To ultimaFila
        If InStr(1, ws.Cells(i, 1).Value, texto, vbTextCompare) > 0 _
        Or InStr(1, ws.Cells(i, 2).Value, texto, vbTextCompare) > 0 Then
            BuscarFilaPorTexto = i
            Exit Function
        End If
    Next i
    BuscarFilaPorTexto = 0
End Function

' ----------------------------------------------------------------------
' Windows — Outlook de escritorio vía COM. .Display deja el mail abierto
' como borrador (el usuario revisa y aprieta Enviar él mismo — nunca se
' manda solo). Si preferís que quede guardado en Borradores sin abrirse,
' cambiá mail.Display por mail.Save.
' ----------------------------------------------------------------------
Private Sub EnviarConOutlook(asunto As String, cuerpoHtml As String, rutaAdjunto As String)
    Dim outlookApp As Object, mail As Object
    On Error Resume Next
    Set outlookApp = GetObject(, "Outlook.Application")
    If outlookApp Is Nothing Then Set outlookApp = CreateObject("Outlook.Application")
    On Error GoTo 0

    If outlookApp Is Nothing Then
        MsgBox "No pude abrir Outlook. ¿Está instalado en esta PC? Si usás otro cliente de mail (Gmail web, etc.), avisale a soporte para adaptar la macro a tu caso.", vbCritical
        Exit Sub
    End If

    Set mail = outlookApp.CreateItem(0) ' 0 = olMailItem
    With mail
        .To = DESTINATARIOS_HABITUALES
        .Subject = asunto
        .HTMLBody = cuerpoHtml
        .Attachments.Add rutaAdjunto
        .Display ' Deja el borrador abierto para revisar antes de enviar
    End With
End Sub

' ----------------------------------------------------------------------
' Mac — Mail.app vía AppleScript (MacScript). `visible:true` deja la
' ventana de redacción abierta como borrador, no se envía sola. El cuerpo
' va en texto plano: el diccionario AppleScript de Mail no soporta setear
' HTML rico de forma confiable entre versiones de macOS.
' ----------------------------------------------------------------------
Private Sub EnviarConAppleMail(asunto As String, cuerpoTexto As String, rutaAdjunto As String)
    Dim rutaPosix As String
    rutaPosix = MacScript("return POSIX path of """ & ConvertirRutaMac(rutaAdjunto) & """")

    Dim script As String
    script = "tell application ""Mail""" & vbNewLine & _
        "  set nuevoMail to make new outgoing message with properties {subject:" & Cita(asunto) & _
        ", content:" & Cita(cuerpoTexto) & ", visible:true}" & vbNewLine & _
        "  tell nuevoMail" & vbNewLine & _
        "    make new attachment with properties {file name:(POSIX file " & Cita(rutaPosix) & ")} at after the last paragraph" & vbNewLine & _
        "  end tell" & vbNewLine & _
        "  activate" & vbNewLine & _
        "end tell"

    MacScript script
End Sub

Private Function Cita(s As String) As String
    Cita = """" & Replace(s, """", "\""") & """"
End Function

Private Function ConvertirRutaMac(rutaExcel As String) As String
    ' Excel para Mac ya entrega ActiveWorkbook.FullName en formato POSIX
    ' (/Users/...) en versiones modernas — se deja la función como punto
    ' único de ajuste si alguna vez hiciera falta convertir desde HFS (:).
    ConvertirRutaMac = rutaExcel
End Function

' ----------------------------------------------------------------------
' Cuerpo HTML (Windows/Outlook) — mismo diseño que la referencia que
' compartió Federico: encabezado con marca, resumen de despachos,
' hormigón/asfalto interno vs. externo, acumulado anual, cierre formal.
' ----------------------------------------------------------------------
Private Function CuerpoHtml(mesLabel As String, despachosTotal As String, hormigonTotal As String, asfaltoTotal As String, _
    hormigonInterno As String, asfaltoInterno As String, hormigonExterno As String, asfaltoExterno As String, _
    tituloAnual As String, hormigonAcumulado As String, asfaltoAcumulado As String) As String

    Dim h As String
    h = "<html><body style=""font-family:Segoe UI,Arial,sans-serif;color:#374151;font-size:14px;line-height:1.5;"">"
    h = h & "<div style=""max-width:640px;margin:0 auto;"">"
    h = h & "<div style=""background:#7B2F8E;padding:20px 24px;border-radius:8px 8px 0 0;"">"
    h = h & "<h1 style=""color:#ffffff;margin:0;font-size:20px;"">VIAL-TEC S.A. — Obras Viales</h1>"
    h = h & "<p style=""color:#E9D5FF;margin:4px 0 0;font-size:13px;"">Informe mensual de producción — " & mesLabel & "</p>"
    h = h & "</div>"
    h = h & "<div style=""border:1px solid #E5E7EB;border-top:none;padding:24px;border-radius:0 0 8px 8px;"">"
    h = h & "<p>Estimados,</p>"
    h = h & "<p>Adjuntamos el informe mensual de producción correspondiente a <strong>" & mesLabel & "</strong>, con el detalle de despachos por obra, vales y remitos de báscula.</p>"

    h = h & "<h3 style=""color:#7B2F8E;border-bottom:2px solid #DDD6FE;padding-bottom:6px;"">Resumen del mes</h3>"
    h = h & "<table style=""width:100%;border-collapse:collapse;margin-bottom:16px;"">"
    h = h & FilaResumenHtml("Despachos totales", despachosTotal, "")
    h = h & FilaResumenHtml("Hormigón despachado", hormigonTotal, "")
    h = h & FilaResumenHtml("Asfalto despachado", asfaltoTotal, "")
    h = h & "</table>"

    h = h & "<h3 style=""color:#7B2F8E;border-bottom:2px solid #DDD6FE;padding-bottom:6px;"">Interno vs. ventas externas</h3>"
    h = h & "<table style=""width:100%;border-collapse:collapse;margin-bottom:16px;"">"
    h = h & "<tr><td></td><td style=""font-weight:bold;color:#7B2F8E;padding:4px 8px;"">Hormigón</td><td style=""font-weight:bold;color:#7B2F8E;padding:4px 8px;"">Asfalto</td></tr>"
    h = h & "<tr><td style=""padding:4px 8px;"">Obras propias</td><td style=""padding:4px 8px;"">" & hormigonInterno & "</td><td style=""padding:4px 8px;"">" & asfaltoInterno & "</td></tr>"
    h = h & "<tr><td style=""padding:4px 8px;"">Ventas externas</td><td style=""padding:4px 8px;"">" & hormigonExterno & "</td><td style=""padding:4px 8px;"">" & asfaltoExterno & "</td></tr>"
    h = h & "</table>"

    h = h & "<h3 style=""color:#7B2F8E;border-bottom:2px solid #DDD6FE;padding-bottom:6px;"">" & tituloAnual & "</h3>"
    h = h & "<table style=""width:100%;border-collapse:collapse;margin-bottom:16px;"">"
    h = h & "<tr style=""background:#00B050;color:#ffffff;""><td style=""padding:8px;font-weight:bold;"">Total acumulado</td>"
    h = h & "<td style=""padding:8px;font-weight:bold;"">" & hormigonAcumulado & "</td>"
    h = h & "<td style=""padding:8px;font-weight:bold;"">" & asfaltoAcumulado & "</td></tr>"
    h = h & "</table>"

    h = h & "<p>El detalle completo por obra (vales, remitos y entregas) está disponible en el archivo adjunto.</p>"
    h = h & "<p style=""margin-top:24px;"">Saludos cordiales,<br><strong>VialTec Plantas</strong></p>"
    h = h & "</div></div></body></html>"

    CuerpoHtml = h
End Function

Private Function FilaResumenHtml(etiqueta As String, valor As String, extra As String) As String
    FilaResumenHtml = "<tr><td style=""padding:6px 8px;color:#6B7280;"">" & etiqueta & "</td>" & _
        "<td style=""padding:6px 8px;font-weight:bold;font-size:16px;"">" & valor & "</td></tr>"
End Function

' ----------------------------------------------------------------------
' Cuerpo en texto plano (Mac/Mail) — mismo contenido, sin HTML.
' ----------------------------------------------------------------------
Private Function CuerpoTextoPlano(mesLabel As String, despachosTotal As String, hormigonTotal As String, asfaltoTotal As String, _
    hormigonInterno As String, asfaltoInterno As String, hormigonExterno As String, asfaltoExterno As String, _
    tituloAnual As String, hormigonAcumulado As String, asfaltoAcumulado As String) As String

    Dim t As String
    t = "VIAL-TEC S.A. — Obras Viales" & vbNewLine
    t = t & "Informe mensual de producción — " & mesLabel & vbNewLine
    t = t & String(50, "-") & vbNewLine & vbNewLine
    t = t & "Estimados," & vbNewLine & vbNewLine
    t = t & "Adjuntamos el informe mensual de producción correspondiente a " & mesLabel & _
        ", con el detalle de despachos por obra, vales y remitos de báscula." & vbNewLine & vbNewLine
    t = t & "RESUMEN DEL MES" & vbNewLine
    t = t & "  Despachos totales:      " & despachosTotal & vbNewLine
    t = t & "  Hormigón despachado:    " & hormigonTotal & vbNewLine
    t = t & "  Asfalto despachado:     " & asfaltoTotal & vbNewLine & vbNewLine
    t = t & "INTERNO VS. VENTAS EXTERNAS" & vbNewLine
    t = t & "  Obras propias:    " & hormigonInterno & " hormigón · " & asfaltoInterno & " asfalto" & vbNewLine
    t = t & "  Ventas externas:  " & hormigonExterno & " hormigón · " & asfaltoExterno & " asfalto" & vbNewLine & vbNewLine
    t = t & UCase(tituloAnual) & vbNewLine
    t = t & "  Total acumulado:  " & hormigonAcumulado & " · " & asfaltoAcumulado & vbNewLine & vbNewLine
    t = t & "El detalle completo por obra (vales, remitos y entregas) está disponible en el archivo adjunto." & vbNewLine & vbNewLine
    t = t & "Saludos cordiales," & vbNewLine & "VialTec Plantas"

    CuerpoTextoPlano = t
End Function
