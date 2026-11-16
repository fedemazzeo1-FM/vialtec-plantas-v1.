// Entrada del paquete que usa la Edge Function informe-produccion (16/11/2026). NO se despliega este archivo: se
// empaqueta con `node scripts/armar-informe-mail.mjs` en ../plantas.bundle.js (ese sí se despliega y se commitea).
// Reúsa el MISMO código que el botón "Descargar informe mensual" de Despachos: mismos datos (informe-mensual.service)
// y mismo Excel (excel-informe-mensual). Así el mail y la pantalla nunca dan números distintos.
export { usarCliente } from './cliente.js'
export {
  fetchDatosInformeMensual,
  fetchComparativoMesAnterior,
  fetchResumenAnual,
  fetchDespachosPorObraDelMes,
  nombreMesLargo,
} from '@/modules/despachos/services/informe-mensual.service'
export { construirWorkbookInformeMensual } from '@/modules/despachos/services/excel-informe-mensual'
export { LISTA_TIPOS_PRODUCTO, sumarTotales } from '@/config/tipos-producto'
export { mesAnteriorDe } from '@/modules/dashboard/services/comparativo-mes'
