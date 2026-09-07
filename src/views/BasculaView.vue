<script setup>
// Vista de Báscula: puertas de pesaje en paralelo (cards apiladas,
// colapsables e independientes — no un tab-bar de "una activa a la vez"),
// historial de vales y doble impresión (vale / remito con acumulado
// dinámico) en filas de asfalto. Toda la lógica de negocio vive en
// useBascula() — este componente es template puro (memory/conventions.md).

import VCard from '@/components/shared/VCard.vue'
import VTable from '@/components/shared/VTable.vue'
import VModal from '@/components/shared/VModal.vue'
import VBadge from '@/components/shared/VBadge.vue'
import VSection from '@/components/shared/VSection.vue'
import VButton from '@/components/shared/VButton.vue'
import ValeImprimible from '@/modules/bascula/components/ValeImprimible.vue'
import {
  useBascula,
  ETIQUETA_TIPO_VALE,
  VARIANTE_TIPO_VALE,
  OPCIONES_TIPO_PUERTA,
  COLOR_PUERTA,
  COLOR_FILA_VALE,
  TIPO_CORTO_VALE,
  ENTRADA_SALIDA_VALE,
} from '@/modules/bascula/composables/useBascula'
import { formatearNumeroVale } from '@/modules/bascula/services/bascula.service'

const {
  error,
  obras,
  patentes,
  proveedores,
  pedidosParaPesada,
  nombreDestinoPedido,
  proximoNumeroVale,
  puertasAbiertas,
  slots,
  crearSlot,
  cambiarTipoSlot,
  toggleColapso,
  cerrarSlot,
  netoSlot,
  alCambiarPatente,
  guardarPesada,
  filasHistorial,
  totalHistorial,
  paginaHistorial,
  cargandoHistorial,
  filtros,
  aplicarFiltrosHistorial,
  limpiarFiltrosHistorial,
  aplicarFiltroSemanaActual,
  cambiarPaginaHistorial,
  TAMANO_PAGINA_HISTORIAL,
  exportandoHistorial,
  exportarHistorialExcel,
  modalImpresionAbierto,
  modoImpresion,
  valeParaImprimir,
  obraNombreParaImprimir,
  mezclaNombreParaImprimir,
  acumuladoParaImprimir,
  pedidoParaImprimir,
  rangoValesParaImprimir,
  abrirImpresionVale,
  abrirImpresionRemito,
  imprimir,
  iniciar,
} = useBascula()

// Réplica exacta del cuadro "Movimientos del día" del legado (2026-09-02,
// memory/relevamiento-sistema-viejo.md §2, verificado de nuevo en vivo hoy
// contra produccion.vialtec.app): HORA, TIPO, MATERIAL/OBRA, PATENTE,
// REMITO, RESPONSABLE, VALE, BRUTO, TARA, NETO, ACUM., S/REMITO, DIF., E/S.
// Ancho total intencional (14 columnas + acciones) — en desktop scrollea
// horizontal como en el legado y se ven las 14 igual que siempre.
//
// Mobile (roadmap 2026-09-07, "menos sobrecarga de datos secundarios"):
// con 14 columnas, la card de VTable.vue quedaba mostrando 14 renglones de
// golpe por vale — mucho para una consulta rápida parado en la báscula.
// `secundaria: true` (VTable.vue) deja Hora/Tipo/Material-Obra/Patente/N°
// Vale/Neto siempre visibles (lo que un balancero necesita de un vistazo) y
// el resto (Remito/Responsable/Bruto/Tara/Acum./S-Remito/Dif./E-S) atrás de
// un "Ver más" por card — mismo dato, un toque para verlo completo. Ningún
// cambio en desktop (esa columna se sigue viendo siempre en la tabla).
const columnasHistorial = [
  { key: 'horaLabel', label: 'Hora' },
  { key: 'tipo_vale', label: 'Tipo' },
  { key: 'materialObraLabel', label: 'Material/Obra' },
  { key: 'patente', label: 'Patente' },
  { key: 'remitoLabel', label: 'Remito', secundaria: true },
  { key: 'responsableLabel', label: 'Responsable', secundaria: true },
  { key: 'numero_vale', label: 'N° Vale', format: (v) => formatearNumeroVale(v) },
  { key: 'peso_bruto', label: 'Bruto', format: (v) => Number(v).toFixed(2), secundaria: true },
  { key: 'tara', label: 'Tara', format: (v) => Number(v).toFixed(2), secundaria: true },
  { key: 'pesoNetoLabel', label: 'Neto' },
  { key: 'acumuladoLabel', label: 'Acum.', secundaria: true },
  { key: 'sRemitoLabel', label: 'S/Remito', secundaria: true },
  { key: 'diferenciaLabel', label: 'Dif.', secundaria: true },
  { key: 'entradaSalida', label: 'E/S', secundaria: true },
  { key: 'acciones', label: '' },
]

iniciar()
</script>

<template>
  <div>
    <VSection title="Báscula — Despachos simultáneos">
      <p class="-mt-2 mb-3 text-sm text-text-soft">
        {{ puertasAbiertas }} {{ puertasAbiertas === 1 ? 'puerta abierta' : 'puertas abiertas' }} · Próximo N°
        <span class="font-semibold text-vialtec">{{ formatearNumeroVale(proximoNumeroVale) }}</span>
      </p>

      <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">
        {{ error }}
      </div>

      <div class="mb-4 flex justify-end">
        <VButton size="sm" @click="crearSlot()">+ Abrir puerta</VButton>
      </div>

      <!-- Puertas abiertas: cards en grilla de al menos 2 columnas (como el
           legado — no ocupan el ancho completo), cada una con su propio
           tipo/colapso/cierre y un color de identificación según el tipo
           (violeta=asfalto, verde=ingreso, naranja=egreso). -->
      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <VCard v-for="slot in slots" :key="slot.id" class="border-l-4" :class="COLOR_PUERTA[slot.tipo].borde">
          <div class="mb-3 flex items-center justify-between">
            <select
              :value="slot.tipo"
              class="rounded-lg border border-border px-3 py-2 text-sm font-semibold focus:border-vialtec focus:outline-none"
              :class="COLOR_PUERTA[slot.tipo].texto"
              @change="cambiarTipoSlot(slot, $event.target.value)"
            >
              <option v-for="op in OPCIONES_TIPO_PUERTA" :key="op.value" :value="op.value">{{ op.label }}</option>
            </select>
            <div class="flex items-center gap-1">
              <button
                type="button"
                class="rounded-md p-1 text-text-soft hover:bg-gray-100 hover:text-text-mid"
                :title="slot.colapsado ? 'Expandir' : 'Colapsar'"
                @click="toggleColapso(slot)"
              >
                {{ slot.colapsado ? '▼' : '▲' }}
              </button>
              <button
                type="button"
                class="rounded-md p-1 text-text-soft hover:bg-danger-light hover:text-danger"
                title="Cerrar puerta"
                @click="cerrarSlot(slot.id)"
              >
                ✕
              </button>
            </div>
          </div>

          <template v-if="!slot.colapsado">
            <div class="grid grid-cols-2 gap-3">
            <template v-if="slot.tipo === 'ingreso_arido'">
              <label class="text-sm text-text-mid">
                Material
                <input
                  v-model="slot.form.material"
                  type="text"
                  class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
                />
              </label>
              <label class="text-sm text-text-mid">
                Proveedor
                <select
                  v-model="slot.form.proveedor"
                  class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
                >
                  <option value="" disabled>Elegir proveedor…</option>
                  <option v-for="p in proveedores" :key="p.id" :value="p.nombre">{{ p.nombre }}</option>
                </select>
              </label>
              <label class="text-sm text-text-mid">
                N° de remito (obligatorio)
                <input
                  v-model="slot.form.numero_remito"
                  type="text"
                  class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
                />
              </label>
              <label class="text-sm text-text-mid col-span-2">
                Cantidad según remito (tn)
                <input
                  v-model.number="slot.form.cantidad_remito"
                  type="number"
                  step="0.01"
                  class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none md:w-1/3"
                />
                <span class="ml-2 text-xs text-text-soft">
                  El stock se actualiza con esta cantidad, no con el peso neto pesado (memory/business-rules.md).
                </span>
              </label>
            </template>

            <template v-if="slot.tipo === 'egreso_arido'">
              <label class="text-sm text-text-mid">
                Material
                <input
                  v-model="slot.form.material"
                  type="text"
                  class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
                />
              </label>
              <label class="text-sm text-text-mid col-span-2">
                Destino (obra)
                <select
                  v-model="slot.form.obra_id"
                  class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
                >
                  <option value="" disabled>Elegir obra…</option>
                  <option v-for="o in obras" :key="o.id" :value="o.id">{{ o.nombre }}</option>
                </select>
              </label>
            </template>

            <label v-if="slot.tipo === 'asfalto'" class="text-sm text-text-mid col-span-2">
              Pedido / Obra
              <select
                v-model="slot.form.pedido_id"
                class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              >
                <option value="" disabled>Elegir pedido…</option>
                <option v-for="p in pedidosParaPesada" :key="p.id" :value="p.id">
                  {{ nombreDestinoPedido(p) }} — {{ p.cantidad_solicitada }} tn
                  ({{ p.estado }})
                </option>
              </select>
              <p v-if="!pedidosParaPesada.length" class="mt-1 text-xs text-text-soft">
                No hay pedidos de asfalto confirmados o despachados.
              </p>
            </label>

            <label class="text-sm text-text-mid">
              Patente
              <input
                v-model="slot.form.patente"
                list="patentes-conocidas"
                class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
                @change="alCambiarPatente(slot)"
              />
            </label>
            <label v-if="slot.tipo === 'asfalto'" class="text-sm text-text-mid">
              Chofer
              <input
                v-model="slot.form.chofer"
                type="text"
                class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              />
            </label>
            <label v-if="slot.tipo === 'asfalto'" class="text-sm text-text-mid">
              Temperatura (°C)
              <input
                v-model.number="slot.form.temperatura"
                type="number"
                step="1"
                class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              />
            </label>

            <label class="text-sm text-text-mid">
              Peso bruto (tn)
              <input
                v-model.number="slot.form.peso_bruto"
                type="number"
                step="0.01"
                class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              />
            </label>
            <label class="text-sm text-text-mid">
              Tara (tn)
              <input
                v-model.number="slot.form.tara"
                type="number"
                step="0.01"
                class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              />
            </label>
            <label class="text-sm text-text-mid">
              Neto (calculado)
              <input
                :value="netoSlot(slot)"
                type="text"
                disabled
                class="mt-1 w-full rounded-lg border border-border bg-gray-50 px-3 py-2 text-sm text-text-soft"
              />
            </label>
          </div>

          <label class="mt-3 block text-sm text-text-mid">
            Observaciones
            <textarea
              v-model="slot.form.observaciones"
              rows="2"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
            ></textarea>
          </label>

            <div class="mt-4 flex justify-end">
              <VButton :disabled="slot.guardando" @click="guardarPesada(slot)">
                {{ slot.guardando ? 'Guardando…' : 'Confirmar pesada' }}
              </VButton>
            </div>
          </template>
        </VCard>
      </div>

      <datalist id="patentes-conocidas">
        <option v-for="p in patentes" :key="p.id" :value="p.patente" />
      </datalist>

      <p v-if="!slots.length" class="my-6 text-sm text-text-soft">No hay ninguna puerta abierta. Abrí una arriba.</p>

      <!-- Filtros de historial -->
      <VCard class="mb-4">
        <div class="grid grid-cols-2 gap-3 md:grid-cols-5">
          <!-- Filtro en vivo (2026-09-04, pedido explícito de Federico: sin
               botón "Filtrar", se aplica solo a medida que se elige cada
               campo) — @change en vez de v-model a secas: dispara
               aplicarFiltrosHistorial() apenas cambia el valor. -->
          <label class="text-sm text-text-mid">
            Tipo
            <select
              v-model="filtros.tipoVale"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              @change="aplicarFiltrosHistorial"
            >
              <option value="">Todos</option>
              <option value="asfalto">Asfalto</option>
              <option value="hormigon">Hormigón</option>
              <option value="ingreso_arido">Ingreso árido</option>
              <option value="egreso_arido">Egreso árido</option>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Obra
            <select
              v-model="filtros.obraId"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              @change="aplicarFiltrosHistorial"
            >
              <option value="">Todas</option>
              <option v-for="o in obras" :key="o.id" :value="o.id">{{ o.nombre }}</option>
            </select>
          </label>
          <label class="text-sm text-text-mid">
            Patente
            <input
              v-model="filtros.patente"
              type="text"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              @change="aplicarFiltrosHistorial"
            />
          </label>
          <label class="text-sm text-text-mid">
            Desde
            <input
              v-model="filtros.desde"
              type="date"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              @change="aplicarFiltrosHistorial"
            />
          </label>
          <label class="text-sm text-text-mid">
            Hasta
            <input
              v-model="filtros.hasta"
              type="date"
              class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
              @change="aplicarFiltrosHistorial"
            />
          </label>
        </div>
        <!-- Default: semana en curso (2026-09-07) — Desde/Hasta siguen
             editables/limpiables libremente arriba, esto solo ofrece volver
             al recorte por defecto sin tener que tipear las fechas a mano. -->
        <p class="mt-2 text-xs text-text-soft">
          Por defecto se muestra la semana en curso — cambiá Desde/Hasta o usá "Limpiar" para ver otro rango.
        </p>
        <div class="mt-3 flex gap-2">
          <VButton variant="ghost" size="sm" @click="aplicarFiltroSemanaActual">Semana actual</VButton>
          <VButton variant="ghost" size="sm" @click="limpiarFiltrosHistorial">Limpiar</VButton>
          <VButton variant="secondary" size="sm" class="ml-auto" :disabled="exportandoHistorial" @click="exportarHistorialExcel">
            {{ exportandoHistorial ? 'Exportando…' : '⬇ Excel' }}
          </VButton>
        </div>
      </VCard>

      <!-- Historial -->
      <VCard>
        <p v-if="cargandoHistorial" class="text-sm text-text-soft">Cargando…</p>
        <VTable
          v-else
          :columns="columnasHistorial"
          :rows="filasHistorial"
          :page="paginaHistorial"
          :page-size="TAMANO_PAGINA_HISTORIAL"
          :total="totalHistorial"
          :row-class="(row) => COLOR_FILA_VALE[row.tipo_vale]"
          @update:page="cambiarPaginaHistorial"
        >
          <template #cell-tipo_vale="{ row }">
            <div class="flex flex-wrap items-center gap-1">
              <VBadge :variant="VARIANTE_TIPO_VALE[row.tipo_vale]" :title="ETIQUETA_TIPO_VALE[row.tipo_vale]">
                {{ row.tipoCorto }}
              </VBadge>
              <!-- 2026-09-04 (memory/pending.md): fila que todavía solo vive
                   en el sistema legado (VISTA_BASCULA_VIVA), sin fila real en
                   plantas_vales detrás todavía — de solo lectura acá. -->
              <VBadge v-if="row.pendiente_migracion" variant="default" title="Todavía solo está en el sistema anterior, no migrado a este sistema">
                Legado
              </VBadge>
            </div>
          </template>
          <template #cell-acciones="{ row }">
            <!-- 2026-09-04 (pedido de Federico): "Vale" también para egreso de
                 áridos (Salida de áridos) — antes solo asfalto tenía botón de
                 impresión. Sigue sin "Remito": ese formato es específico del
                 flujo de pedido/obra de asfalto (acumulado por pedido, rango
                 de vales correlativos), egreso de áridos no tiene pedido
                 asociado. Ingreso de áridos sigue sin impresión (no pedido). -->
            <div
              v-if="!row.pendiente_migracion && (row.tipo_vale === 'asfalto' || row.tipo_vale === 'egreso_arido')"
              class="flex gap-1.5"
            >
              <VButton variant="secondary" size="sm" @click="abrirImpresionVale(row)">Vale</VButton>
              <VButton v-if="row.tipo_vale === 'asfalto'" variant="secondary" size="sm" @click="abrirImpresionRemito(row)">Remito</VButton>
            </div>
            <span v-else class="text-xs text-gray-300">—</span>
          </template>
        </VTable>
        <p v-if="!cargandoHistorial && !filasHistorial.length" class="py-4 text-center text-sm text-text-soft">
          No hay vales que coincidan con el filtro.
        </p>
      </VCard>
    </VSection>

    <!-- Modal de impresión — Teleport a <body> (2026-09-04, bug real: el
         diálogo de impresión mostraba páginas de más porque este modal
         vivía dentro de #app, ver comentario en src/assets/main.css). -->
    <Teleport to="body">
      <VModal
        :open="modalImpresionAbierto"
        :title="modoImpresion === 'remito' ? 'Remito de entrega' : 'Vale de pesaje'"
        size="xl"
        @update:open="modalImpresionAbierto = $event"
      >
        <div class="imprimible" :class="{ 'modo-remito': modoImpresion === 'remito' }">
          <ValeImprimible
            v-if="valeParaImprimir"
            :vale="valeParaImprimir"
            :obra-nombre="obraNombreParaImprimir"
            :mezcla-nombre="mezclaNombreParaImprimir"
            :modo="modoImpresion"
            :acumulado-tn="acumuladoParaImprimir"
            :pedido="pedidoParaImprimir"
            :rango-vales="rangoValesParaImprimir"
            :patentes="patentes"
          />
        </div>
        <div class="mt-4 flex justify-end gap-2">
          <VButton variant="secondary" @click="modalImpresionAbierto = false">Cerrar</VButton>
          <VButton @click="imprimir">Imprimir</VButton>
        </div>
      </VModal>
    </Teleport>
  </div>
</template>
