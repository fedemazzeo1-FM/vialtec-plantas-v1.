// GENERADO por scripts/armar-informe-mail.mjs — no editar a mano.
// deno-lint-ignore-file

// supabase/functions/informe-produccion/fuente/cliente.js
var supabase = null;
function usarCliente(cliente) {
  supabase = cliente;
}

// src/services/fetch-paginado.js
var TAMANO_PAGINA = 1e3;
var TAMANO_PAGINA_UI_DEFAULT = 50;
async function fetchPaginado(construirQuery) {
  let desde = 0;
  let resultado = [];
  while (true) {
    const hasta = desde + TAMANO_PAGINA - 1;
    const { data, error } = await construirQuery().range(desde, hasta);
    if (error) throw error;
    resultado = resultado.concat(data ?? []);
    if (!data || data.length < TAMANO_PAGINA) break;
    desde += TAMANO_PAGINA;
  }
  return resultado;
}
async function fetchPagina(construirQuery, { pagina = 1, tamanoPagina = TAMANO_PAGINA_UI_DEFAULT } = {}) {
  const desde = (pagina - 1) * tamanoPagina;
  const hasta = desde + tamanoPagina - 1;
  const { data, error, count } = await construirQuery().range(desde, hasta);
  if (error) throw error;
  return { filas: data ?? [], total: count ?? 0, pagina, tamanoPagina };
}

// src/services/formato-numeros.js
function formatearCantidad(valor, decimales = 1) {
  const n = Number(valor);
  return (Number.isFinite(n) ? n : 0).toLocaleString("es-AR", {
    minimumFractionDigits: decimales,
    maximumFractionDigits: decimales
  });
}

// src/config/tipos-producto.js
var CIRCUITO = {
  // Se pesa en Báscula, un vale por camión.
  BASCULA: "bascula",
  // No se pesa: sale con N° de remito por carga.
  MIXER: "mixer"
};
var TIPOS_PRODUCTO = {
  asfalto: {
    id: "asfalto",
    nombre: "Asfalto",
    circuito: CIRCUITO.BASCULA,
    unidad: "tn",
    unidadLabel: "tn",
    total: "asfaltoTn",
    siempreVisible: true,
    ordenListado: 2,
    color: "#2a78d6",
    clases: { barra: "bg-[#2a78d6]", texto: "text-[#2a78d6]", punto: "bg-[#2a78d6]" }
  },
  hormigon: {
    id: "hormigon",
    nombre: "Hormig\xF3n",
    circuito: CIRCUITO.MIXER,
    unidad: "m3",
    unidadLabel: "m\xB3",
    total: "hormigonM3",
    siempreVisible: true,
    ordenListado: 1,
    color: "#eb6834",
    clases: { barra: "bg-[#eb6834]", texto: "text-[#eb6834]", punto: "bg-[#eb6834]" },
    avisoProduccion: "Hormig\xF3n confirmado para producci\xF3n"
  },
  mezcla_cemento: {
    id: "mezcla_cemento",
    nombre: "Mezcla cemento",
    circuito: CIRCUITO.MIXER,
    unidad: "tn",
    unidadLabel: "tn",
    total: "mezclaCementoTn",
    siempreVisible: false,
    ordenListado: 3,
    color: "#64748b",
    clases: { barra: "bg-[#64748b]", texto: "text-[#64748b]", punto: "bg-[#64748b]" },
    avisoProduccion: "Mezcla cemento confirmada para producci\xF3n"
  }
};
var LISTA_TIPOS_PRODUCTO = Object.values(TIPOS_PRODUCTO);
var TIPOS_PRODUCTO_EN_ORDEN_DE_LISTADO = [...LISTA_TIPOS_PRODUCTO].sort((a, b) => a.ordenListado - b.ordenListado);
var TIPO_PRODUCTO_INICIAL = LISTA_TIPOS_PRODUCTO[0].id;
function tipoProducto(tipo) {
  return TIPOS_PRODUCTO[tipo] ?? TIPOS_PRODUCTO[TIPO_PRODUCTO_INICIAL];
}
var nombreTipoProducto = (tipo) => tipoProducto(tipo).nombre;
var unidadLabelTipoProducto = (tipo) => tipoProducto(tipo).unidadLabel;
var esCircuitoBascula = (tipo) => tipoProducto(tipo).circuito === CIRCUITO.BASCULA;
var esCircuitoMixer = (tipo) => tipoProducto(tipo).circuito === CIRCUITO.MIXER;
function totalesVacios() {
  return Object.fromEntries(LISTA_TIPOS_PRODUCTO.map((t) => [t.total, 0]));
}
function sumarEnTotal(totales, tipo, cantidad) {
  totales[tipoProducto(tipo).total] += Number(cantidad) || 0;
  return totales;
}
function sumarTotales(...lista) {
  const resultado = totalesVacios();
  for (const totales of lista) {
    for (const clave of Object.keys(resultado)) resultado[clave] += Number(totales?.[clave]) || 0;
  }
  return resultado;
}
function magnitudTotales(totales) {
  return LISTA_TIPOS_PRODUCTO.reduce((acc, t) => acc + (Number(totales?.[t.total]) || 0), 0);
}

// src/modules/maestros/services/formulas.service.js
var TABLA = "plantas_formulas";
async function fetchFormulas({ soloActivas = false } = {}) {
  let query = supabase.from(TABLA).select("*").order("nombre", { ascending: true });
  if (soloActivas) query = query.eq("activo", true);
  const { data, error } = await query;
  if (error) throw error;
  return data;
}
function calcularConsumoKg(insumo, cantidadProducida) {
  const cantidad = Number(insumo.cantidad) || 0;
  switch (insumo.unidad) {
    case "%":
      return cantidad / 100 * 1e3 * cantidadProducida;
    case "tn":
      return cantidad * 1e3 * cantidadProducida;
    case "kg":
    case "L":
      return cantidad * cantidadProducida;
    default:
      throw new Error(`calcularConsumoKg: unidad de insumo desconocida "${insumo.unidad}"`);
  }
}
function calcularConsumoTotalKg(formula, cantidadProducida) {
  return (formula.insumos || []).map((insumo) => ({
    material: insumo.material,
    kg: calcularConsumoKg(insumo, cantidadProducida)
  }));
}

// src/modules/dashboard/services/dashboard.service.js
var PRODUCCION_PRE_MAYO_2026 = {
  "2026-01": { asfaltoTn: 3813.76, hormigonM3: 1371.5 },
  "2026-02": { asfaltoTn: 2973.06, hormigonM3: 1325.3 },
  "2026-03": { asfaltoTn: 2701.88, hormigonM3: 544.8 },
  "2026-04": { asfaltoTn: 2428.01, hormigonM3: 380.1 }
};

// src/services/despachos.service.js
var TABLA_PEDIDOS = "plantas_pedidos";
function queryDespachosFiltrados(filtros = {}, selectOpts) {
  let query = supabase.from(TABLA_PEDIDOS).select("*", selectOpts).eq("estado", "despachado").order("fecha_programada", { ascending: false }).order("id", { ascending: false });
  if (filtros.tipo) query = query.eq("tipo", filtros.tipo);
  if (filtros.obraId) query = query.eq("obra_id", filtros.obraId);
  if (filtros.formulaId) query = query.eq("formula_id", filtros.formulaId);
  if (filtros.clienteExterno) query = query.eq("cliente_externo", filtros.clienteExterno);
  if (filtros.desde) query = query.gte("fecha_programada", filtros.desde);
  if (filtros.hasta) query = query.lte("fecha_programada", filtros.hasta);
  return query;
}
async function fetchDespachos(filtros = {}, { pagina = 1, tamanoPagina = 20 } = {}) {
  return fetchPagina(() => queryDespachosFiltrados(filtros, { count: "exact" }), { pagina, tamanoPagina });
}
function rangoDelMes(mes) {
  const [anio, mesNum] = mes.split("-").map(Number);
  const inicio = new Date(anio, mesNum - 1, 1);
  const fin = new Date(anio, mesNum, 0);
  const aISO2 = (d) => d.toISOString().slice(0, 10);
  return { desde: aISO2(inicio), hasta: aISO2(fin) };
}
async function fetchTotalesMes(mes) {
  const { desde, hasta } = rangoDelMes(mes);
  return fetchTotalesRango(desde, hasta);
}
async function fetchTotalesRango(desde, hasta) {
  const filas = await fetchPaginado(
    () => supabase.from(TABLA_PEDIDOS).select("tipo, cantidad_despachada").eq("estado", "despachado").gte("fecha_programada", desde).lte("fecha_programada", hasta)
  );
  const totales = totalesVacios();
  for (const p of filas) sumarEnTotal(totales, p.tipo, p.cantidad_despachada);
  return totales;
}
async function fetchCantidadesDespachadasDelMes(mes) {
  const { desde, hasta } = rangoDelMes(mes);
  return fetchPaginado(
    () => supabase.from(TABLA_PEDIDOS).select("formula_id, cantidad_despachada").eq("estado", "despachado").gte("fecha_programada", desde).lte("fecha_programada", hasta)
  );
}
async function fetchResumenPorObra(mes) {
  const { desde, hasta } = rangoDelMes(mes);
  const filas = await fetchPaginado(
    () => supabase.from(TABLA_PEDIDOS).select("obra_id, tipo, cantidad_despachada, tipo_pedido, cliente_externo").eq("estado", "despachado").gte("fecha_programada", desde).lte("fecha_programada", hasta)
  );
  const porObra = /* @__PURE__ */ new Map();
  for (const p of filas) {
    const clave = p.obra_id ?? `venta:${p.cliente_externo || "sin nombre"}`;
    if (!porObra.has(clave)) {
      porObra.set(clave, {
        obraId: p.obra_id,
        clienteExterno: p.obra_id ? null : p.cliente_externo || "Venta externa",
        ...totalesVacios(),
        cantidadDespachos: 0
      });
    }
    const acc = porObra.get(clave);
    sumarEnTotal(acc, p.tipo, p.cantidad_despachada);
    acc.cantidadDespachos += 1;
  }
  return Array.from(porObra.values()).sort((a, b) => magnitudTotales(b) - magnitudTotales(a));
}
async function fetchValesDeVariosPedidos(pedidoIds) {
  if (!pedidoIds.length) return [];
  const { data, error } = await supabase.from("plantas_vales").select("numero_vale, pedido_id, patente, chofer, peso_neto, unidad, fecha_pesada").in("pedido_id", pedidoIds).eq("tipo_vale", "asfalto").eq("anulado", false);
  if (error) throw error;
  return data ?? [];
}
async function fetchCargasHormigonDeVariosPedidos(pedidoIds) {
  if (!pedidoIds.length) return [];
  const { data, error } = await supabase.from("plantas_cargas_hormigon").select("pedido_id, numero_remito, volumen_m3, patente_mixer, chofer, fecha_carga").in("pedido_id", pedidoIds);
  if (error) throw error;
  return data ?? [];
}

// src/services/flota.service.js
async function fetchObras({ soloActivas = true } = {}) {
  if (soloActivas) {
    const { data: data2, error: error2 } = await supabase.from("plantas_v_obras_visibles").select("id, nombre, codigo").order("nombre", { ascending: true });
    if (error2) throw error2;
    return data2;
  }
  const { data, error } = await supabase.from("flota_obras").select("id, nombre, codigo, activo").order("nombre", { ascending: true });
  if (error) throw error;
  return data;
}

// src/modules/maestros/services/maestros.service.js
function crudEntidad(tabla, columnaOrden = "nombre", filtroFijo = null) {
  return {
    async fetch({ soloActivos = false } = {}) {
      let query = supabase.from(tabla).select("*").order(columnaOrden, { ascending: true });
      if (soloActivos) query = query.eq("activo", true);
      if (filtroFijo) {
        for (const [columna, valor] of Object.entries(filtroFijo)) query = query.eq(columna, valor);
      }
      const { data, error } = await query;
      if (error) throw error;
      return data;
    },
    async crear(registro) {
      const { data, error } = await supabase.from(tabla).insert({ ...registro, ...filtroFijo }).select().single();
      if (error) throw error;
      return data;
    },
    async actualizar(id, cambios) {
      const { data, error } = await supabase.from(tabla).update(cambios).eq("id", id).select().single();
      if (error) throw error;
      return data;
    },
    async setActivo(id, activo) {
      return this.actualizar(id, { activo });
    },
    // Borrado real (2026-09-09, pedido explícito de Federico solo para
    // Camiones propios/externos — "que sea eliminar en serio", hay mucha
    // rotación de camiones, sobre todo externos). A diferencia del resto de
    // Maestros (que usan setActivo, nunca DELETE), esta tabla no tiene
    // ninguna FK real desde el resto del sistema — plantas_vales.patente,
    // plantas_cargas_asfalto.patente y plantas_cargas_hormigon.patente_mixer
    // son texto libre, no referencian plantas_patentes.id — así que borrar
    // una patente del catálogo no rompe ni afecta ningún vale/carga
    // histórico ya guardado. RLS ya lo permite (plantas_tiene_permiso
    // ('maestros', 'eliminar'), migración 26) — MaestrosView.vue es quien
    // decide en qué tabs mostrar el botón.
    // Con motivo obligatorio (migración 62): la RPC corre con los permisos
    // del usuario (mismas policies de RLS) y deja el motivo en la auditoría.
    async eliminar(id, motivo) {
      const { error } = await supabase.rpc("plantas_eliminar_maestro", { p_tabla: tabla, p_id: id, p_motivo: motivo });
      if (error) throw error;
    }
  };
}
var encargadosService = crudEntidad("plantas_encargados");
var proveedoresService = crudEntidad("plantas_proveedores");
var patentesService = crudEntidad("plantas_patentes", "patente");
var patentesPropiasService = crudEntidad("plantas_patentes", "patente", { es_externa: false });
var patentesExternasService = crudEntidad("plantas_patentes", "patente", { es_externa: true });
var choferesService = crudEntidad("plantas_choferes");
var materialesService = crudEntidad("plantas_materiales");
var clientesService = crudEntidad("plantas_clientes");

// src/config/app.config.js
var appConfig = {
  nombre: "VialTec Plantas",
  // Los vales de báscula del sistema anterior siguen una secuencia nativa que
  // empieza en 9579 (ver memory/business-rules.md). Este valor documenta el
  // punto de partida para la migración del historial, no un contador en vivo.
  vales: {
    numeroInicial: 9579
  },
  // Materiales que nunca se descuentan del stock (ver memory/business-rules.md).
  stock: {
    materialesSinDescuento: ["Agua", "Purgue"]
  },
  // La semana operativa va de lunes a domingo.
  semana: {
    inicio: "lunes"
  }
};

// src/modules/analytics/services/analytics.service.js
function aTn(valor, unidad) {
  const n = Number(valor) || 0;
  return unidad === "kg" ? n / 1e3 : n;
}
function normalizarRango({ desde, hasta } = {}) {
  const hoy = /* @__PURE__ */ new Date();
  const inicioMesActual = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
  return {
    desde: desde ? /* @__PURE__ */ new Date(`${desde}T00:00:00`) : inicioMesActual,
    hasta: hasta ? /* @__PURE__ */ new Date(`${hasta}T23:59:59`) : hoy
  };
}
function claveProveedor(nombre) {
  const limpio = (nombre || "").trim().replace(/\s+/g, " ").toUpperCase();
  return limpio || "Sin especificar";
}
async function fetchAnaliticaProveedoresDetalle(rangoFechas = {}) {
  const { desde, hasta } = normalizarRango(rangoFechas);
  const filas = await fetchPaginado(
    () => supabase.from("plantas_ingresos").select("proveedor, material, cantidad, unidad").eq("anulado", false).gte("fecha_ingreso", desde.toISOString()).lte("fecha_ingreso", hasta.toISOString())
  );
  const porProveedor = /* @__PURE__ */ new Map();
  for (const fila of filas) {
    const proveedor = claveProveedor(fila.proveedor);
    if (!porProveedor.has(proveedor)) porProveedor.set(proveedor, /* @__PURE__ */ new Map());
    const porInsumo = porProveedor.get(proveedor);
    const material = fila.material || "Sin especificar";
    if (!porInsumo.has(material)) porInsumo.set(material, { viajes: 0, toneladas: 0 });
    const acc = porInsumo.get(material);
    acc.viajes += 1;
    acc.toneladas += aTn(fila.cantidad, fila.unidad);
  }
  return Array.from(porProveedor.entries()).map(([proveedor, porInsumo]) => {
    const insumos = Array.from(porInsumo.entries()).map(([material, { viajes, toneladas }]) => ({ material, viajes, toneladas })).sort((a, b) => b.toneladas - a.toneladas);
    return {
      proveedor,
      viajes: insumos.reduce((acc, i) => acc + i.viajes, 0),
      totalTn: insumos.reduce((acc, i) => acc + i.toneladas, 0),
      insumos
    };
  }).sort((a, b) => b.totalTn - a.totalTn);
}

// src/modules/dashboard/services/comparativo-mes.js
var NOMBRES_MES = [
  "enero",
  "febrero",
  "marzo",
  "abril",
  "mayo",
  "junio",
  "julio",
  "agosto",
  "septiembre",
  "octubre",
  "noviembre",
  "diciembre"
];
var aISO = (anio, mes0, dia) => `${anio}-${String(mes0 + 1).padStart(2, "0")}-${String(dia).padStart(2, "0")}`;
var diasDelMes = (anio, mes0) => new Date(anio, mes0 + 1, 0).getDate();
function periodosComparativo(hoy = /* @__PURE__ */ new Date()) {
  const ayer = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate() - 1);
  const mesCerrado = hoy.getDate() === 1;
  const anio = ayer.getFullYear();
  const mes0 = ayer.getMonth();
  const diaHasta = ayer.getDate();
  const previo = new Date(anio, mes0 - 1, 1);
  const anioPrevio = previo.getFullYear();
  const mes0Previo = previo.getMonth();
  const diaHastaPrevio = Math.min(diaHasta, diasDelMes(anioPrevio, mes0Previo));
  return {
    mesCerrado,
    actual: { anio, mes0, diaHasta, desde: aISO(anio, mes0, 1), hasta: aISO(anio, mes0, diaHasta) },
    anterior: {
      anio: anioPrevio,
      mes0: mes0Previo,
      diaHasta: diaHastaPrevio,
      desde: aISO(anioPrevio, mes0Previo, 1),
      hasta: aISO(anioPrevio, mes0Previo, diaHastaPrevio)
    }
  };
}
function periodosMesCerrado(mes) {
  const [anio, mesNum] = mes.split("-").map(Number);
  return periodosComparativo(new Date(anio, mesNum, 1));
}
function mesAnteriorDe(mes) {
  const [anio, mesNum] = mes.split("-").map(Number);
  const previo = new Date(anio, mesNum - 2, 1);
  return `${previo.getFullYear()}-${String(previo.getMonth() + 1).padStart(2, "0")}`;
}
function tramo({ anio, mes0, diaHasta }, conAnio) {
  const mes = `${NOMBRES_MES[mes0]}${conAnio ? ` de ${anio}` : ""}`;
  return diaHasta === 1 ? `1 de ${mes}` : `1 al ${diaHasta} de ${mes}`;
}
var formatear = (n) => n.toLocaleString("es-AR", { maximumFractionDigits: 1 });
function formatearPorcentaje(pct) {
  const abs = Math.abs(pct);
  const decimales = abs > 0 && abs < 1 ? 1 : 0;
  return `${abs.toLocaleString("es-AR", { maximumFractionDigits: decimales, minimumFractionDigits: decimales })}%`;
}
function anteriorEsMesCompleto({ anterior }) {
  return anterior.diaHasta === diasDelMes(anterior.anio, anterior.mes0);
}
function filasComparativo(periodos, totalesActual, totalesAnterior, totalesMesAnteriorCompleto = null) {
  const mesActual = NOMBRES_MES[periodos.actual.mes0];
  const mesAnterior = NOMBRES_MES[periodos.anterior.mes0];
  const mesCompleto = anteriorEsMesCompleto(periodos);
  const conAnio = periodos.actual.anio !== periodos.anterior.anio;
  const tramoAnterior = mesCompleto ? `en ${mesAnterior}` : periodos.anterior.diaHasta === 1 ? `el ${tramo(periodos.anterior, conAnio)}` : `del ${tramo(periodos.anterior, conAnio)}`;
  return LISTA_TIPOS_PRODUCTO.map((tipo) => {
    const actual = Number(totalesActual?.[tipo.total]) || 0;
    const anterior = Number(totalesAnterior?.[tipo.total]) || 0;
    if (actual === 0 && anterior === 0) return null;
    const cantidad = (n) => `${formatear(n)} ${tipo.unidadLabel}`;
    const producto = tipo.nombre.toLowerCase();
    const diferencia = actual - anterior;
    const sinAnterior = anterior === 0;
    const pct = sinAnterior ? null : diferencia / anterior * 100;
    const tendencia = diferencia > 0 ? "sube" : diferencia < 0 ? "baja" : "igual";
    const inicio = periodos.mesCerrado ? `En ${mesActual} se despacharon ${cantidad(actual)} de ${producto}` : `En lo que va de ${mesActual} llevamos ${cantidad(actual)} de ${producto}`;
    const referencia = periodos.mesCerrado ? `en ${mesAnterior}` : `a esta altura de ${mesAnterior}`;
    let frase;
    if (actual === 0) {
      frase = periodos.mesCerrado ? `En ${mesActual} no hubo despachos de ${producto}; ${referencia} fueron ${cantidad(anterior)}.` : `En lo que va de ${mesActual} no hay despachos de ${producto}; ${referencia} llev\xE1bamos ${cantidad(anterior)}.`;
    } else if (sinAnterior) {
      const totalMes = Number(totalesMesAnteriorCompleto?.[tipo.total]) || 0;
      const cierre = !mesCompleto && totalMes > 0 ? ` (${mesAnterior} cerr\xF3 con ${cantidad(totalMes)})` : "";
      frase = `${inicio}; ${tramoAnterior} no hubo producci\xF3n${cierre}.`;
    } else if (tendencia === "igual") {
      frase = `${inicio}, lo mismo que ${referencia}.`;
    } else {
      frase = `${inicio}, ${formatearPorcentaje(pct)} ${tendencia === "sube" ? "m\xE1s" : "menos"} que ${referencia} (${cantidad(anterior)}).`;
    }
    const signo = diferencia > 0 ? "+" : diferencia < 0 ? "\u2212" : "";
    let comparacion;
    if (sinAnterior) comparacion = `sin producci\xF3n en ${mesAnterior}`;
    else if (tendencia === "igual") comparacion = `igual que ${mesAnterior}`;
    else comparacion = `${formatearPorcentaje(pct)} ${tendencia === "sube" ? "m\xE1s" : "menos"} que ${mesAnterior} (${signo}${cantidad(Math.abs(diferencia))})`;
    return {
      tipo,
      actual,
      anterior,
      tendencia,
      frase,
      mesAnterior,
      actualTexto: cantidad(actual),
      anteriorTexto: cantidad(anterior),
      resumen: `${tipo.nombre}: ${cantidad(actual)}, ${comparacion}`,
      badge: sinAnterior ? `sin producci\xF3n ${tramoAnterior}` : `${tendencia === "sube" ? "\u25B2" : tendencia === "baja" ? "\u25BC" : "="} ${formatearPorcentaje(pct)} \xB7 ${signo}${cantidad(Math.abs(diferencia))}`
    };
  }).filter(Boolean);
}

// src/modules/despachos/services/informe-mensual.service.js
async function fetchDespachosPorObraDelMes(mes) {
  const resumen = await fetchResumenPorObra(mes);
  const internos = resumen.filter((r) => r.obraId != null).sort((a, b) => magnitudTotales(b) - magnitudTotales(a));
  const externos = resumen.filter((r) => r.obraId == null).sort((a, b) => magnitudTotales(b) - magnitudTotales(a));
  const subtotal = (lista) => ({
    despachos: lista.reduce((acc, r) => acc + r.cantidadDespachos, 0),
    ...sumarTotales(...lista)
  });
  const subtotalInterno = subtotal(internos);
  const subtotalExterno = subtotal(externos);
  return {
    internos,
    externos,
    subtotalInterno,
    subtotalExterno,
    totalGeneral: {
      despachos: subtotalInterno.despachos + subtotalExterno.despachos,
      ...sumarTotales(subtotalInterno, subtotalExterno)
    }
  };
}
async function fetchConsumoInsumosDelMes(mes) {
  const [pedidos, formulas, materiales] = await Promise.all([
    fetchCantidadesDespachadasDelMes(mes),
    fetchFormulas({ soloActivas: false }),
    materialesService.fetch()
  ]);
  const formulasPorId = Object.fromEntries(formulas.map((f) => [f.id, f]));
  const clave = (nombre) => (nombre || "").trim().toLowerCase();
  const nombreCatalogo = Object.fromEntries(materiales.map((m) => [clave(m.nombre), m.nombre]));
  const sinDescuento = appConfig.stock.materialesSinDescuento.map(clave);
  const porMaterial = /* @__PURE__ */ new Map();
  for (const p of pedidos) {
    const formula = formulasPorId[p.formula_id];
    const cantidad = Number(p.cantidad_despachada) || 0;
    if (!formula || cantidad <= 0) continue;
    for (const { material, kg } of calcularConsumoTotalKg(formula, cantidad)) {
      if (sinDescuento.includes(clave(material))) continue;
      const enCatalogo = nombreCatalogo[clave(material)];
      const nombre = enCatalogo || (material || "").trim() || "Sin especificar";
      const previo = porMaterial.get(nombre) ?? { kg: 0, fueraDeCatalogo: !enCatalogo };
      previo.kg += kg;
      porMaterial.set(nombre, previo);
    }
  }
  const filas = Array.from(porMaterial.entries()).map(([material, { kg, fueraDeCatalogo }]) => ({ material, toneladas: kg / 1e3, fueraDeCatalogo })).sort((a, b) => b.toneladas - a.toneladas);
  return { filas, totalTn: filas.reduce((acc, f) => acc + f.toneladas, 0) };
}
var NOMBRES_MES2 = [
  "Enero",
  "Febrero",
  "Marzo",
  "Abril",
  "Mayo",
  "Junio",
  "Julio",
  "Agosto",
  "Septiembre",
  "Octubre",
  "Noviembre",
  "Diciembre"
];
function nombreMesLargo(mes) {
  const [anio, mesNum] = mes.split("-").map(Number);
  return `${NOMBRES_MES2[mesNum - 1]} ${anio}`;
}
function conHistorico(mes, totales) {
  return sumarTotales(totales, PRODUCCION_PRE_MAYO_2026[mes]);
}
async function fetchComparativoMesAnterior(mes, totalesMes) {
  const mesPrevio = mesAnteriorDe(mes);
  const anterior = conHistorico(mesPrevio, await fetchTotalesMes(mesPrevio));
  return filasComparativo(periodosMesCerrado(mes), totalesMes, anterior);
}
async function fetchResumenAnual(mesHasta) {
  const [anio, mesNum] = mesHasta.split("-").map(Number);
  const meses = Array.from({ length: mesNum }, (_, i) => `${anio}-${String(i + 1).padStart(2, "0")}`);
  const totales = await Promise.all(meses.map((m) => fetchTotalesMes(m)));
  const filas = meses.map((m, i) => ({ mes: nombreMesLargo(m), ...conHistorico(m, totales[i]) }));
  const totalAcumulado = sumarTotales(...filas);
  return { filas, totalAcumulado, anio };
}
async function fetchDetallePesadasDelMes(pedidos, pedidosPorId) {
  const idsAsfalto = pedidos.filter((p) => esCircuitoBascula(p.tipo)).map((p) => p.id);
  const idsHormigon = pedidos.filter((p) => esCircuitoMixer(p.tipo)).map((p) => p.id);
  const [vales, cargasHormigon] = await Promise.all([
    fetchValesDeVariosPedidos(idsAsfalto),
    fetchCargasHormigonDeVariosPedidos(idsHormigon)
  ]);
  const filasAsfalto = vales.map((v) => ({
    fecha: v.fecha_pesada,
    tipo: nombreTipoProducto(pedidosPorId[v.pedido_id]?.tipo),
    // N° Remito es 1 solo por PEDIDO (compartido por todas sus pesadas,
    // migración 39) — se resuelve acá contra el pedido dueño de cada vale,
    // no contra el vale (que no tiene remito propio).
    nroRemito: pedidosPorId[v.pedido_id]?.nro_remito_global || "",
    nroVale: v.numero_vale != null ? String(v.numero_vale) : "",
    patente: v.patente || "",
    chofer: v.chofer || "",
    cantidad: v.unidad === "kg" ? Number(v.peso_neto) / 1e3 : Number(v.peso_neto),
    unidad: "tn"
  }));
  const filasHormigon = cargasHormigon.map((c) => ({
    fecha: c.fecha_carga,
    tipo: nombreTipoProducto(pedidosPorId[c.pedido_id]?.tipo),
    nroRemito: c.numero_remito || "",
    // por carga, no por pedido — "el remito ya es por carga" en hormigón
    nroVale: "",
    // hormigón no tiene concepto de vale (no se pesa en báscula)
    patente: c.patente_mixer || "",
    chofer: c.chofer || "",
    cantidad: Number(c.volumen_m3) || 0,
    unidad: unidadLabelTipoProducto(pedidosPorId[c.pedido_id]?.tipo)
  }));
  return [...filasAsfalto, ...filasHormigon].sort((a, b) => a.fecha < b.fecha ? -1 : 1);
}
async function fetchDetalleDestinoDelMes(destino, mes, formulasPorId) {
  const { desde, hasta } = rangoDelMes(mes);
  const { filas } = await fetchDespachos(
    { obraId: destino.obraId || void 0, desde, hasta },
    { pagina: 1, tamanoPagina: 1e3 }
    // tope generoso: un solo destino en un mes no supera esto (memory/architecture.md, no es un listado sin acotar)
  );
  const propias = destino.obraId ? filas : filas.filter((f) => (f.cliente_externo || "Venta externa") === destino.clienteExterno);
  const resumen = propias.map((p) => ({
    id: p.id,
    fecha: p.fecha_programada,
    mezcla: formulasPorId[p.formula_id]?.nombre ?? "\u2014",
    tipo: nombreTipoProducto(p.tipo),
    unidad: unidadLabelTipoProducto(p.tipo),
    estado: p.estado,
    pedido: Number(p.cantidad_solicitada),
    real: Number(p.cantidad_despachada) || 0,
    nroRemito: p.nro_remito_global || "",
    nroVale: p.nro_vale_global || "",
    encargado: p.encargado || "",
    notas: p.motivo || ""
  })).sort((a, b) => a.fecha < b.fecha ? -1 : 1);
  const pedidosPorId = Object.fromEntries(propias.map((p) => [p.id, p]));
  const pesadas = await fetchDetallePesadasDelMes(propias, pedidosPorId);
  return { resumen, pesadas };
}
async function fetchDatosInformeMensual(mes) {
  const { desde, hasta } = rangoDelMes(mes);
  const [obras, formulas, despachosPorObra, consumoInsumos, resumenAnual, analiticaProveedores] = await Promise.all([
    fetchObras({ soloActivas: false }),
    fetchFormulas({ soloActivas: false }),
    fetchDespachosPorObraDelMes(mes),
    fetchConsumoInsumosDelMes(mes),
    fetchResumenAnual(mes),
    fetchAnaliticaProveedoresDetalle({ desde, hasta })
  ]);
  const obrasPorId = Object.fromEntries(obras.map((o) => [o.id, o]));
  const formulasPorId = Object.fromEntries(formulas.map((f) => [f.id, f]));
  despachosPorObra.internos = despachosPorObra.internos.map((r) => ({
    ...r,
    nombre: obrasPorId[r.obraId]?.nombre ?? `Obra #${r.obraId}`
  }));
  despachosPorObra.externos = despachosPorObra.externos.map((r) => ({
    ...r,
    nombre: r.clienteExterno
  }));
  const [detalleInternos, detalleExternos] = await Promise.all([
    Promise.all(despachosPorObra.internos.map((d) => fetchDetalleDestinoDelMes(d, mes, formulasPorId))),
    Promise.all(despachosPorObra.externos.map((d) => fetchDetalleDestinoDelMes(d, mes, formulasPorId)))
  ]);
  return {
    mes,
    mesLabel: nombreMesLargo(mes),
    despachosPorObra,
    consumoInsumos,
    resumenAnual,
    analiticaProveedores,
    // detalleInternos[i]/detalleExternos[i] = { resumen, pesadas } (ver
    // fetchDetalleDestinoDelMes) — se desparraman acá para que
    // excel-informe-mensual.js reciba las 2 tablas de cada hoja ya
    // resueltas, sin tener que conocer la forma interna del fetch.
    hojasInternas: despachosPorObra.internos.map((d, i) => ({
      ...d,
      detalle: detalleInternos[i].resumen,
      pesadas: detalleInternos[i].pesadas
    })),
    hojaVentasExternas: {
      destinos: despachosPorObra.externos.map((d, i) => ({
        ...d,
        detalle: detalleExternos[i].resumen,
        pesadas: detalleExternos[i].pesadas
      })),
      resumen: despachosPorObra.externos
    }
  };
}

// src/services/excel-corporativo.js
var VIOLETA = "FF7C3AED";
var VIOLETA_CLARO = "FFDDD6FE";
var VIOLETA_OSCURO = "FF5D2CB2";
var GRIS_TEXTO = "FF374151";
var GRIS_SUAVE = "FF9CA3AF";
var BLANCO = "FFFFFFFF";
function aplicarFill(cell, argb) {
  cell.fill = { type: "pattern", pattern: "solid", fgColor: { argb } };
}
var BORDE_FINO = { style: "thin", color: { argb: "FFE5E7EB" } };
var BORDE_CELDA = { top: BORDE_FINO, bottom: BORDE_FINO, left: BORDE_FINO, right: BORDE_FINO };
function estiloHeaderTabla(cell) {
  aplicarFill(cell, VIOLETA);
  cell.font = { bold: true, color: { argb: BLANCO }, size: 11 };
  cell.alignment = { horizontal: "center", vertical: "middle", wrapText: true };
  cell.border = BORDE_CELDA;
}
function estiloSubtotal(cell) {
  aplicarFill(cell, VIOLETA_CLARO);
  cell.font = { bold: true, color: { argb: VIOLETA }, size: 10 };
  cell.border = BORDE_CELDA;
  cell.alignment = { vertical: "middle" };
}
function estiloTotalGeneral(cell, size = 10) {
  aplicarFill(cell, VIOLETA_OSCURO);
  cell.font = { bold: true, color: { argb: BLANCO }, size };
  cell.border = BORDE_CELDA;
  cell.alignment = { vertical: "middle" };
}
function estiloBandaExterna(cell) {
  aplicarFill(cell, VIOLETA);
  cell.font = { bold: true, color: { argb: BLANCO }, size: 11 };
  cell.border = BORDE_CELDA;
  cell.alignment = { vertical: "middle" };
}
function estiloCuerpo(cell, esPar = false) {
  cell.font = { color: { argb: GRIS_TEXTO }, size: 10 };
  cell.border = BORDE_CELDA;
  cell.alignment = { vertical: "middle" };
  if (esPar) aplicarFill(cell, "FFF9FAFB");
}
function calcularAnchosAutoFit(filas, { minimo = 8, maximo = 45 } = {}) {
  const nCols = filas.reduce((max, f) => Math.max(max, f.length), 0);
  const anchos = new Array(nCols).fill(minimo);
  for (const fila of filas) {
    fila.forEach((valor, i) => {
      if (valor == null || valor === "") return;
      const texto = String(valor);
      const largoMayor = Math.max(...texto.split("\n").map((l) => l.length));
      anchos[i] = Math.min(maximo, Math.max(anchos[i], largoMayor + 2));
    });
  }
  return anchos;
}
function agregarPieInstitucional(worksheet, filaContenido, columnasAnchoTotal) {
  const fila = filaContenido + 2;
  const ultimaCol = String.fromCharCode(64 + columnasAnchoTotal);
  worksheet.mergeCells(`A${fila}:${ultimaCol}${fila}`);
  const cell = worksheet.getCell(`A${fila}`);
  cell.value = "VialTec Plantas \u2014 Sistema de gesti\xF3n de plantas de producci\xF3n";
  cell.font = { italic: true, size: 8, color: { argb: GRIS_SUAVE } };
  cell.alignment = { horizontal: "center" };
}

// src/modules/despachos/services/excel-informe-mensual.js
var AMARILLO_TAB = "FFFFEB3B";
var ZONA_AR = "America/Argentina/Buenos_Aires";
var TN = (v) => v ? `${formatearCantidad(v, 2)} tn` : "\u2014";
var M3 = (v) => v ? `${formatearCantidad(v, 1)} m\xB3` : "\u2014";
function tiposConColumnaExtra(totales) {
  return LISTA_TIPOS_PRODUCTO.filter((t) => !t.siempreVisible && (Number(totales?.[t.total]) || 0) > 0);
}
var headersExtra = (tipos) => tipos.map((t) => `${t.nombre} (${t.unidadLabel})`);
var celdasExtra = (tipos, totales) => tipos.map((t) => totales?.[t.total] ? `${formatearCantidad(totales[t.total], 2)} ${t.unidadLabel}` : "\u2014");
function anchoColumnasExtra(ws, tipos, desde) {
  tipos.forEach((_, i) => {
    ws.getColumn(desde + i).width = 22;
  });
}
var GRIS_TEXTO_HEX = "#374151";
var GRIS_SUAVE_HEX = "#9CA3AF";
var FECHA = (iso) => {
  if (!iso) return "";
  const [anio, mes, dia] = iso.split("-");
  return `${dia}/${mes}/${anio}`;
};
var FECHA_HORA = (iso) => iso ? new Date(iso).toLocaleString("es-AR", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "";
function agregarLogo(workbook, worksheet, logoBuffer) {
  const imageId = workbook.addImage({ buffer: logoBuffer, extension: "png" });
  worksheet.addImage(imageId, { tl: { col: 0, row: 0 }, ext: { width: 102, height: 44 } });
}
function armarHojaResumenMensual(workbook, datos) {
  const ws = workbook.addWorksheet("Resumen mensual");
  ws.columns = [{ width: 5 }, { width: 42 }, { width: 13 }, { width: 20 }, { width: 18 }];
  ws.properties.defaultRowHeight = 18;
  ws.getRow(1).height = 50;
  ws.mergeCells("A2:E2");
  ws.getCell("A2").value = `Informe mensual de producci\xF3n \u2014 ${datos.mesLabel}`;
  ws.getCell("A2").font = { bold: true, size: 14, color: { argb: GRIS_TEXTO } };
  ws.getRow(2).height = 24;
  ws.mergeCells("A3:E3");
  ws.getCell("A3").value = `Fecha de exportaci\xF3n: ${(/* @__PURE__ */ new Date()).toLocaleString("es-AR", { timeZone: ZONA_AR })}`;
  ws.getCell("A3").font = { italic: true, size: 9, color: { argb: GRIS_SUAVE } };
  let fila = 4;
  ws.mergeCells(`A${fila}:E${fila}`);
  ws.getCell(`A${fila}`).value = "  Despachos por obra";
  ["A", "B", "C", "D", "E"].forEach((c) => estiloSubtotal(ws.getCell(`${c}${fila}`)));
  fila++;
  const extra = tiposConColumnaExtra(datos.despachosPorObra.totalGeneral);
  anchoColumnasExtra(ws, extra, 6);
  const headerRow = ws.getRow(fila);
  headerRow.values = ["N\xB0", "Obra", "Despachos", "Hormig\xF3n (m\xB3)", "Asfalto (tn)", ...headersExtra(extra)];
  headerRow.eachCell((cell) => estiloHeaderTabla(cell));
  fila++;
  datos.despachosPorObra.internos.forEach((r, i) => {
    const row = ws.getRow(fila);
    row.values = [i + 1, r.nombre, r.cantidadDespachos, M3(r.hormigonM3), TN(r.asfaltoTn), ...celdasExtra(extra, r)];
    row.eachCell((cell) => estiloCuerpo(cell));
    fila++;
  });
  const subInt = ws.getRow(fila);
  subInt.values = [
    null,
    "Subtotal interno",
    datos.despachosPorObra.subtotalInterno.despachos,
    M3(datos.despachosPorObra.subtotalInterno.hormigonM3),
    TN(datos.despachosPorObra.subtotalInterno.asfaltoTn),
    ...celdasExtra(extra, datos.despachosPorObra.subtotalInterno)
  ];
  subInt.eachCell((cell) => estiloSubtotal(cell));
  fila++;
  const bandaExt = ws.getRow(fila);
  bandaExt.values = ["  Ventas externas", null, null, "Hormig\xF3n (m\xB3)", "Asfalto (tn)", ...headersExtra(extra)];
  bandaExt.eachCell((cell) => estiloBandaExterna(cell));
  fila++;
  const nInternos = datos.despachosPorObra.internos.length;
  datos.despachosPorObra.externos.forEach((r, i) => {
    const row = ws.getRow(fila);
    row.values = [nInternos + i + 1, r.nombre, r.cantidadDespachos, M3(r.hormigonM3), TN(r.asfaltoTn), ...celdasExtra(extra, r)];
    row.eachCell((cell) => estiloCuerpo(cell));
    fila++;
  });
  const subExt = ws.getRow(fila);
  subExt.values = [
    null,
    "Subtotal externo",
    datos.despachosPorObra.subtotalExterno.despachos,
    M3(datos.despachosPorObra.subtotalExterno.hormigonM3),
    TN(datos.despachosPorObra.subtotalExterno.asfaltoTn),
    ...celdasExtra(extra, datos.despachosPorObra.subtotalExterno)
  ];
  subExt.eachCell((cell) => estiloSubtotal(cell));
  fila++;
  const total = ws.getRow(fila);
  total.values = [
    null,
    "TOTAL GENERAL",
    datos.despachosPorObra.totalGeneral.despachos,
    M3(datos.despachosPorObra.totalGeneral.hormigonM3),
    TN(datos.despachosPorObra.totalGeneral.asfaltoTn),
    ...celdasExtra(extra, datos.despachosPorObra.totalGeneral)
  ];
  total.eachCell((cell) => estiloTotalGeneral(cell, 12));
  fila += 2;
  ws.mergeCells(`A${fila}:E${fila}`);
  ws.getCell(`A${fila}`).value = "  Consumo de insumos";
  ["A", "B", "C", "D", "E"].forEach((c) => estiloSubtotal(ws.getCell(`${c}${fila}`)));
  fila++;
  const headerInsumos = ws.getRow(fila);
  headerInsumos.getCell(1).value = "N\xB0";
  headerInsumos.getCell(2).value = "Insumo";
  headerInsumos.getCell(3).value = "Consumo (tn)";
  [1, 2, 3].forEach((c) => estiloHeaderTabla(headerInsumos.getCell(c)));
  fila++;
  datos.consumoInsumos.filas.forEach((f, i) => {
    const row = ws.getRow(fila);
    row.getCell(1).value = i + 1;
    row.getCell(2).value = f.fueraDeCatalogo ? `${f.material} (fuera del cat\xE1logo: revisar la f\xF3rmula)` : f.material;
    row.getCell(3).value = TN(f.toneladas);
    [1, 2, 3].forEach((c) => estiloCuerpo(row.getCell(c)));
    fila++;
  });
  const totalInsumos = ws.getRow(fila);
  totalInsumos.getCell(2).value = "TOTAL";
  totalInsumos.getCell(3).value = TN(datos.consumoInsumos.totalTn);
  [1, 2, 3].forEach((c) => estiloSubtotal(totalInsumos.getCell(c)));
  agregarPieInstitucional(ws, fila, 5);
  return ws;
}
function generarImagenGraficoAnual(filas) {
  const ESCALA = 2;
  const ANCHO = 900;
  const ALTO = 380;
  const MARGEN = { top: 55, right: 30, bottom: 55, left: 70 };
  const anchoGrafico = ANCHO - MARGEN.left - MARGEN.right;
  const altoGrafico = ALTO - MARGEN.top - MARGEN.bottom;
  const canvas = document.createElement("canvas");
  canvas.width = ANCHO * ESCALA;
  canvas.height = ALTO * ESCALA;
  const ctx = canvas.getContext("2d");
  ctx.scale(ESCALA, ESCALA);
  ctx.fillStyle = "#FFFFFF";
  ctx.fillRect(0, 0, ANCHO, ALTO);
  ctx.fillStyle = GRIS_TEXTO_HEX;
  ctx.font = "bold 15px Arial, sans-serif";
  ctx.fillText("Producci\xF3n mensual", MARGEN.left, 24);
  const COLOR_HORMIGON = "#DDD6FE";
  const COLOR_ASFALTO = "#7C3AED";
  const leyenda = [
    { color: COLOR_HORMIGON, texto: "Hormig\xF3n (m\xB3)" },
    { color: COLOR_ASFALTO, texto: "Asfalto (tn)" }
  ];
  let xLeyenda = ANCHO - MARGEN.right - 220;
  leyenda.forEach((l) => {
    ctx.fillStyle = l.color;
    ctx.fillRect(xLeyenda, 12, 12, 12);
    ctx.fillStyle = GRIS_TEXTO_HEX;
    ctx.font = "11px Arial, sans-serif";
    ctx.fillText(l.texto, xLeyenda + 16, 22);
    xLeyenda += 110;
  });
  const maxValor = Math.max(1, ...filas.map((f) => Math.max(f.hormigonM3, f.asfaltoTn))) * 1.15;
  const escalaY = altoGrafico / maxValor;
  const baseY = MARGEN.top + altoGrafico;
  const pasos = 4;
  ctx.strokeStyle = "#E5E7EB";
  ctx.fillStyle = GRIS_SUAVE_HEX;
  ctx.font = "10px Arial, sans-serif";
  ctx.textAlign = "right";
  for (let i = 0; i <= pasos; i++) {
    const valor = maxValor * i / pasos;
    const y = baseY - valor * escalaY;
    ctx.beginPath();
    ctx.moveTo(MARGEN.left, y);
    ctx.lineTo(MARGEN.left + anchoGrafico, y);
    ctx.stroke();
    ctx.fillText(Math.round(valor).toLocaleString("es-AR"), MARGEN.left - 8, y + 3);
  }
  const anchoGrupo = anchoGrafico / filas.length;
  const anchoBarra = Math.min(22, anchoGrupo * 0.32);
  ctx.textAlign = "center";
  filas.forEach((f, i) => {
    const xGrupo = MARGEN.left + i * anchoGrupo + anchoGrupo / 2;
    const altoHormigon = f.hormigonM3 * escalaY;
    const altoAsfalto = f.asfaltoTn * escalaY;
    ctx.fillStyle = COLOR_HORMIGON;
    ctx.fillRect(xGrupo - anchoBarra - 3, baseY - altoHormigon, anchoBarra, altoHormigon);
    ctx.fillStyle = COLOR_ASFALTO;
    ctx.fillRect(xGrupo + 3, baseY - altoAsfalto, anchoBarra, altoAsfalto);
    ctx.fillStyle = GRIS_TEXTO_HEX;
    ctx.font = "11px Arial, sans-serif";
    ctx.fillText(f.mes.slice(0, 3), xGrupo, baseY + 18);
  });
  ctx.strokeStyle = GRIS_TEXTO_HEX;
  ctx.beginPath();
  ctx.moveTo(MARGEN.left, baseY);
  ctx.lineTo(MARGEN.left + anchoGrafico, baseY);
  ctx.stroke();
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (!blob) {
        reject(new Error("No se pudo generar la imagen del gr\xE1fico."));
        return;
      }
      blob.arrayBuffer().then(resolve, reject);
    }, "image/png");
  });
}
async function armarHojaResumenAnual(workbook, datos, graficoAnual = generarImagenGraficoAnual) {
  const ws = workbook.addWorksheet("Resumen anual");
  ws.columns = [{ width: 20 }, { width: 18 }, { width: 18 }];
  ws.properties.defaultRowHeight = 18;
  ws.mergeCells("A1:C1");
  ws.getCell("A1").value = `Informe Anual Enero\u2013${datos.mesLabel}`;
  ws.getCell("A1").font = { bold: true, size: 12, color: { argb: GRIS_TEXTO } };
  const extra = tiposConColumnaExtra(datos.resumenAnual.totalAcumulado);
  anchoColumnasExtra(ws, extra, 4);
  const header = ws.getRow(2);
  header.values = ["Mes", "Hormig\xF3n (m\xB3)", "Asfalto (tn)", ...headersExtra(extra)];
  header.eachCell((cell) => estiloHeaderTabla(cell));
  let fila = 3;
  [...datos.resumenAnual.filas].reverse().forEach((f) => {
    const row = ws.getRow(fila);
    row.values = [f.mes, M3(f.hormigonM3), TN(f.asfaltoTn), ...celdasExtra(extra, f)];
    row.getCell(1).font = { color: { argb: GRIS_SUAVE }, size: 10 };
    row.getCell(2).font = { color: { argb: GRIS_TEXTO }, size: 10 };
    row.getCell(3).font = { color: { argb: GRIS_TEXTO }, size: 10 };
    extra.forEach((_, i) => {
      row.getCell(4 + i).font = { color: { argb: GRIS_TEXTO }, size: 10 };
    });
    fila++;
  });
  const total = ws.getRow(fila);
  total.values = [
    "TOTAL ACUMULADO",
    M3(datos.resumenAnual.totalAcumulado.hormigonM3),
    TN(datos.resumenAnual.totalAcumulado.asfaltoTn),
    ...celdasExtra(extra, datos.resumenAnual.totalAcumulado)
  ];
  total.eachCell((cell) => estiloHeaderTabla(cell));
  try {
    const imagenGrafico = await graficoAnual(datos.resumenAnual.filas);
    const imageId = workbook.addImage({ buffer: imagenGrafico, extension: "png" });
    ws.addImage(imageId, { tl: { col: 0, row: fila + 1 }, ext: { width: 630, height: 266 } });
  } catch (e) {
  }
  return ws;
}
function armarHojaProveedores(workbook, datos) {
  const ws = workbook.addWorksheet("Anal\xEDtica de Proveedores");
  ws.columns = [{ width: 30 }, { width: 24 }, { width: 10 }, { width: 14 }];
  ws.properties.defaultRowHeight = 18;
  ws.mergeCells("A1:D1");
  ws.getCell("A1").value = `Anal\xEDtica de proveedores \u2014 ${datos.mesLabel}`;
  ws.getCell("A1").font = { bold: true, size: 13, color: { argb: GRIS_TEXTO } };
  const header = ws.getRow(2);
  header.values = ["Proveedor", "Insumo", "Viajes", "Toneladas"];
  header.eachCell((cell) => estiloHeaderTabla(cell));
  let fila = 3;
  let totalViajes = 0;
  let totalTn = 0;
  datos.analiticaProveedores.forEach((p) => {
    p.insumos.forEach((i) => {
      const row = ws.getRow(fila);
      row.values = [p.proveedor, i.material, i.viajes, Number(i.toneladas.toFixed(2))];
      row.eachCell((cell) => estiloCuerpo(cell));
      row.getCell(4).numFmt = "#,##0.00";
      totalViajes += i.viajes;
      totalTn += i.toneladas;
      fila++;
    });
  });
  if (!datos.analiticaProveedores.length) {
    ws.mergeCells(`A${fila}:D${fila}`);
    ws.getCell(`A${fila}`).value = "Sin ingresos de proveedores registrados en el mes.";
    ws.getCell(`A${fila}`).font = { italic: true, size: 10, color: { argb: GRIS_SUAVE } };
    fila++;
  } else {
    const total = ws.getRow(fila);
    total.values = ["TOTAL", "", totalViajes, Number(totalTn.toFixed(2))];
    total.eachCell((cell) => estiloSubtotal(cell));
    total.getCell(4).numFmt = "#,##0.00";
    fila++;
  }
  agregarPieInstitucional(ws, fila - 1, 4);
  return ws;
}
function armarHojaDestino(workbook, nombre, mesLabel, filasResumen, filasPesadas) {
  const nombreHoja = nombre.replace(/[:\\/?*[\]]/g, " ").slice(0, 31);
  const ws = workbook.addWorksheet(nombreHoja);
  const N_COLS = 11;
  const letras = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K"];
  ws.properties.defaultRowHeight = 18;
  const header1 = ["N\xB0", "Cliente", "Fecha", "Mezcla", "Tipo", "Solicitado", "Real", "Unidad", "Estado", "N\xB0 Remito", "N\xB0 Vale"];
  const header2 = ["N\xB0", "Fecha/Hora", "Tipo", "N\xB0 Vale", "N\xB0 Remito", "Patente", "Chofer", "Cantidad", "Unidad"];
  const filas1 = filasResumen.map((d, i) => ({
    valores: [
      i + 1,
      nombre,
      d.fecha ? new Date(d.fecha) : null,
      d.mezcla,
      d.tipo,
      Number(d.pedido) || 0,
      Number(d.real) || 0,
      d.unidad,
      d.estado ?? "",
      d.nroRemito || "",
      d.nroVale || ""
    ],
    texto: [
      i + 1,
      nombre,
      FECHA(d.fecha),
      d.mezcla,
      d.tipo,
      formatearCantidad(d.pedido, 2),
      formatearCantidad(d.real, 2),
      d.unidad,
      d.estado ?? "",
      d.nroRemito || "",
      d.nroVale || ""
    ]
  }));
  const tipos = [...new Set(filasResumen.map((d) => d.tipo))];
  const totales1 = tipos.map((tipo) => {
    const delTipo = filasResumen.filter((d) => d.tipo === tipo);
    const totalReal = Number(delTipo.reduce((acc, d) => acc + d.real, 0).toFixed(2));
    const valores = [
      tipos.length > 1 ? `TOTAL ${tipo.toUpperCase()}` : "TOTAL",
      null,
      null,
      null,
      `${delTipo.length} desp.`,
      null,
      totalReal,
      delTipo[0]?.unidad ?? "",
      null,
      null,
      null
    ];
    return { valores, texto: valores.map((v) => v == null ? "" : String(v)) };
  });
  const filas2 = filasPesadas.map((p, i) => ({
    valores: [i + 1, p.fecha ? new Date(p.fecha) : null, p.tipo, p.nroVale || "", p.nroRemito || "", p.patente, p.chofer, Number(p.cantidad) || 0, p.unidad],
    texto: [i + 1, FECHA_HORA(p.fecha), p.tipo, p.nroVale || "", p.nroRemito || "", p.patente, p.chofer, formatearCantidad(p.cantidad, 2), p.unidad]
  }));
  const tiposPesadas = [...new Set(filasPesadas.map((p) => p.tipo))];
  const totales2 = tiposPesadas.map((tipo) => {
    const delTipo = filasPesadas.filter((p) => p.tipo === tipo);
    const totalCantidad = Number(delTipo.reduce((acc, p) => acc + p.cantidad, 0).toFixed(2));
    const valores = [
      tiposPesadas.length > 1 ? `TOTAL ${tipo.toUpperCase()}` : "TOTAL",
      null,
      `${delTipo.length} pesada${delTipo.length === 1 ? "" : "s"}`,
      null,
      null,
      null,
      null,
      totalCantidad,
      delTipo[0]?.unidad ?? ""
    ];
    return { valores, texto: valores.map((v) => v == null ? "" : String(v)) };
  });
  const anchos = calcularAnchosAutoFit([
    header1,
    ...filas1.map((f) => f.texto),
    ...totales1.map((f) => f.texto),
    header2,
    ...filas2.map((f) => f.texto),
    ...totales2.map((f) => f.texto)
  ]);
  ws.columns = anchos.map((width) => ({ width }));
  ws.mergeCells(`A1:${letras[N_COLS - 1]}1`);
  ws.getCell("A1").value = nombre;
  ws.getCell("A1").font = { bold: true, size: 13, color: { argb: GRIS_TEXTO } };
  ws.getRow(1).height = 24;
  ws.mergeCells(`A2:${letras[N_COLS - 1]}2`);
  ws.getCell("A2").value = `Despachos \u2014 ${mesLabel}`;
  ws.getCell("A2").font = { italic: true, size: 10, color: { argb: GRIS_SUAVE } };
  let fila = 3;
  ws.mergeCells(`A${fila}:${letras[N_COLS - 1]}${fila}`);
  ws.getCell(`A${fila}`).value = "  Resumen por pedido";
  letras.forEach((c) => estiloSubtotal(ws.getCell(`${c}${fila}`)));
  ws.getRow(fila).height = 20;
  fila++;
  ws.getRow(fila).values = header1;
  ws.getRow(fila).height = 22;
  ws.getRow(fila).eachCell((cell) => estiloHeaderTabla(cell));
  fila++;
  filas1.forEach(({ valores }) => {
    const row = ws.getRow(fila);
    row.values = valores;
    row.height = 18;
    row.eachCell((cell) => estiloCuerpo(cell));
    row.getCell(2).alignment = { vertical: "middle", wrapText: true };
    row.getCell(4).alignment = { vertical: "middle", wrapText: true };
    row.getCell(3).numFmt = "dd/mm/yyyy";
    row.getCell(6).numFmt = "#,##0.00";
    row.getCell(7).numFmt = "#,##0.00";
    row.getCell(10).numFmt = "@";
    row.getCell(11).numFmt = "@";
    fila++;
  });
  if (!filas1.length) {
    ws.mergeCells(`A${fila}:${letras[N_COLS - 1]}${fila}`);
    ws.getCell(`A${fila}`).value = "Sin despachos en el mes.";
    ws.getCell(`A${fila}`).font = { italic: true, size: 10, color: { argb: GRIS_SUAVE } };
    fila++;
  }
  totales1.forEach(({ valores }) => {
    const row = ws.getRow(fila);
    row.values = valores;
    row.height = 20;
    letras.forEach((c) => estiloSubtotal(row.getCell(c)));
    row.getCell(7).numFmt = "#,##0.00";
    fila++;
  });
  fila += 1;
  ws.mergeCells(`A${fila}:${letras[N_COLS - 1]}${fila}`);
  ws.getCell(`A${fila}`).value = "  Detalle de pesadas";
  letras.forEach((c) => estiloSubtotal(ws.getCell(`${c}${fila}`)));
  ws.getRow(fila).height = 20;
  fila++;
  ws.getRow(fila).values = header2;
  ws.getRow(fila).height = 22;
  ws.getRow(fila).eachCell((cell) => estiloHeaderTabla(cell));
  fila++;
  filas2.forEach(({ valores }) => {
    const row = ws.getRow(fila);
    row.values = valores;
    row.height = 18;
    row.eachCell((cell) => estiloCuerpo(cell));
    row.getCell(2).numFmt = "dd/mm/yyyy hh:mm";
    row.getCell(4).numFmt = "@";
    row.getCell(5).numFmt = "@";
    row.getCell(8).numFmt = "#,##0.00";
    fila++;
  });
  if (!filas2.length) {
    ws.mergeCells(`A${fila}:${letras[N_COLS - 1]}${fila}`);
    ws.getCell(`A${fila}`).value = "Sin pesadas/cargas individuales registradas en el mes.";
    ws.getCell(`A${fila}`).font = { italic: true, size: 10, color: { argb: GRIS_SUAVE } };
    fila++;
  } else {
    totales2.forEach(({ valores }) => {
      const row = ws.getRow(fila);
      row.values = valores;
      row.height = 20;
      letras.forEach((c) => estiloSubtotal(row.getCell(c)));
      row.getCell(8).numFmt = "#,##0.00";
      fila++;
    });
  }
  return ws;
}
async function construirWorkbookInformeMensual(datos, logoBuffer, { graficoAnual } = {}) {
  const { default: ExcelJS } = await import("npm:exceljs@4.4.0");
  const workbook = new ExcelJS.Workbook();
  workbook.creator = "VialTec Plantas";
  workbook.created = /* @__PURE__ */ new Date();
  const hojaResumen = armarHojaResumenMensual(workbook, datos);
  agregarLogo(workbook, hojaResumen, logoBuffer);
  await armarHojaResumenAnual(workbook, datos, graficoAnual);
  armarHojaProveedores(workbook, datos);
  for (const destino of datos.hojasInternas) {
    const filas = destino.detalle.map((d) => ({ ...d, mezcla: d.mezcla ?? "\u2014" }));
    armarHojaDestino(workbook, destino.nombre, datos.mesLabel, filas, destino.pesadas);
  }
  if (datos.hojaVentasExternas.destinos.length) {
    const wsVentas = workbook.addWorksheet("Ventas Externas");
    wsVentas.properties.tabColor = { argb: AMARILLO_TAB };
    wsVentas.properties.defaultRowHeight = 18;
    wsVentas.columns = [{ width: 5 }, { width: 40 }, { width: 12 }, { width: 20 }, { width: 18 }];
    wsVentas.mergeCells("A1:E1");
    wsVentas.getCell("A1").value = `Ventas Externas \u2014 ${datos.mesLabel}`;
    wsVentas.getCell("A1").font = { bold: true, size: 13, color: { argb: GRIS_TEXTO } };
    wsVentas.mergeCells("A2:E2");
    const nClientes = datos.hojaVentasExternas.destinos.length;
    const nDespachos = datos.despachosPorObra.subtotalExterno.despachos;
    wsVentas.getCell("A2").value = `${nDespachos} despacho${nDespachos === 1 ? "" : "s"} \u2014 ${nClientes} cliente${nClientes === 1 ? "" : "s"}`;
    wsVentas.getCell("A2").font = { italic: true, size: 10, color: { argb: GRIS_SUAVE } };
    const extra = tiposConColumnaExtra(datos.despachosPorObra.subtotalExterno);
    anchoColumnasExtra(wsVentas, extra, 6);
    const header = wsVentas.getRow(3);
    header.values = ["N\xB0", "Cliente", "Despachos", "Hormig\xF3n (m\xB3)", "Asfalto (tn)", ...headersExtra(extra)];
    header.eachCell((cell) => estiloHeaderTabla(cell));
    let fila = 4;
    datos.despachosPorObra.externos.forEach((r, i) => {
      const row = wsVentas.getRow(fila);
      row.values = [i + 1, r.nombre, r.cantidadDespachos, M3(r.hormigonM3), TN(r.asfaltoTn), ...celdasExtra(extra, r)];
      row.eachCell((cell) => estiloCuerpo(cell));
      fila++;
    });
    const total = wsVentas.getRow(fila);
    total.values = [
      null,
      "TOTAL",
      datos.despachosPorObra.subtotalExterno.despachos,
      M3(datos.despachosPorObra.subtotalExterno.hormigonM3),
      TN(datos.despachosPorObra.subtotalExterno.asfaltoTn),
      ...celdasExtra(extra, datos.despachosPorObra.subtotalExterno)
    ];
    total.eachCell((cell) => estiloSubtotal(cell));
    for (const destino of datos.hojaVentasExternas.destinos) {
      const filas = destino.detalle.map((d) => ({ ...d, mezcla: d.mezcla ?? "\u2014" }));
      armarHojaDestino(workbook, destino.nombre, datos.mesLabel, filas, destino.pesadas);
    }
  }
  return workbook;
}
export {
  LISTA_TIPOS_PRODUCTO,
  construirWorkbookInformeMensual,
  fetchComparativoMesAnterior,
  fetchDatosInformeMensual,
  fetchDespachosPorObraDelMes,
  fetchResumenAnual,
  mesAnteriorDe,
  nombreMesLargo,
  sumarTotales,
  usarCliente
};
