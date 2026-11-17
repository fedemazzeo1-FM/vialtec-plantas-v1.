<script setup>
// Pestaña "Vales manuales" de Despachos (migración 77, 17/11/2026): simulaciones con el formato del vale de
// balanza. No suman a producción ni a despachos y no tocan stock. La vista la abre con abrirNuevo() desde el
// botón "Generar vale manual" del encabezado; la lógica vive en useValesManuales.js.

import { onMounted, ref, toRef } from 'vue'
import VButton from '@/components/shared/VButton.vue'
import VCard from '@/components/shared/VCard.vue'
import VModal from '@/components/shared/VModal.vue'
import RemitoImprimible from '@/components/shared/RemitoImprimible.vue'
import ValeImprimible from '@/modules/bascula/components/ValeImprimible.vue'
import { useValesManuales } from '@/modules/despachos/composables/useValesManuales'
import { formatearCantidadHasta, formatearNumeroRemito } from '@/services/formato-numeros'

const props = defineProps({
  obras: { type: Array, default: () => [] },
  clientes: { type: Array, default: () => [] },
  formulas: { type: Array, default: () => [] },
  patentes: { type: Array, default: () => [] },
})

const {
  vales,
  cargando,
  error,
  cargar,
  destinoDe,
  mezclaDe,
  formulasAsfalto,
  formatearNumeroValeManual,
  modalNuevoAbierto,
  form,
  netoForm,
  guardando,
  errorForm,
  abrirNuevo,
  guardar,
  valeParaImprimir,
  valeImprimible,
  modalValeAbierto,
  modalRemitoAbierto,
  generandoRemito,
  verVale,
  remitoProps,
  verRemito,
  imprimir,
  descargandoPdf,
  descargarPdf,
  valeParaAnular,
  motivoAnulacion,
  anulando,
  errorAnular,
  abrirAnular,
  confirmarAnular,
} = useValesManuales({ formulas: toRef(props, 'formulas'), patentes: toRef(props, 'patentes') })

const refVale = ref(null)
const refRemito = ref(null)

const fechaHora = (iso) =>
  new Date(iso).toLocaleString('es-AR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })

const inputClase = 'mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none'

onMounted(cargar)
defineExpose({ abrirNuevo })
</script>

<template>
  <VCard>
    <p class="mb-3 text-xs text-text-soft">
      Simulaciones de retiros que no pasaron por la balanza. No suman a la producción ni a los despachos y no
      descuentan stock. Numeración propia (M-00001); se anulan con motivo, nunca se borran.
    </p>
    <div v-if="error" class="mb-3 rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">{{ error }}</div>
    <p v-if="cargando" class="text-sm text-text-soft">Cargando…</p>
    <div v-else-if="vales.length" class="overflow-x-auto">
      <table class="w-full text-left text-sm">
        <thead>
          <tr class="border-b border-border text-xs uppercase tracking-wide text-text-soft">
            <th class="py-1.5 pr-3">N°</th>
            <th class="py-1.5 pr-3">Fecha</th>
            <th class="py-1.5 pr-3">Destino</th>
            <th class="py-1.5 pr-3">Mezcla</th>
            <th class="py-1.5 pr-3 text-right">Neto</th>
            <th class="py-1.5 pr-3">Patente / chofer</th>
            <th class="py-1.5 pr-3">Remito</th>
            <th class="py-1.5 pr-3">Generó</th>
            <th class="py-1.5"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="v in vales" :key="v.id" class="border-b border-border/60 align-top" :class="v.anulado ? 'text-text-soft' : ''">
            <td class="whitespace-nowrap py-1.5 pr-3 font-semibold" :class="v.anulado ? 'line-through' : 'text-text'">
              {{ formatearNumeroValeManual(v.numero) }}
            </td>
            <td class="whitespace-nowrap py-1.5 pr-3">{{ fechaHora(v.fecha_pesada) }}</td>
            <td class="py-1.5 pr-3">
              {{ destinoDe(v) }}
              <span v-if="v.cliente_externo" class="text-xs text-text-soft">(cliente)</span>
            </td>
            <td class="py-1.5 pr-3">{{ mezclaDe(v) }}</td>
            <td class="whitespace-nowrap py-1.5 pr-3 text-right font-semibold">{{ formatearCantidadHasta(v.peso_neto) }} tn</td>
            <td class="py-1.5 pr-3 text-text-soft">{{ [v.patente, v.chofer].filter(Boolean).join(' · ') || '—' }}</td>
            <td class="whitespace-nowrap py-1.5 pr-3">{{ v.numero_remito != null ? formatearNumeroRemito(v.numero_remito) : '—' }}</td>
            <td class="py-1.5 pr-3 text-xs text-text-soft">{{ v.creado_por }}</td>
            <td class="py-1.5">
              <div v-if="v.anulado" class="max-w-[16rem] text-xs">
                <span class="font-semibold text-danger">Anulado</span>
                <span class="text-text-soft"> — {{ v.motivo_anulacion }} ({{ v.anulado_por }}, {{ fechaHora(v.anulado_en) }})</span>
              </div>
              <div v-else class="flex flex-wrap gap-1">
                <VButton variant="ghost" size="sm" @click="verVale(v)">Vale</VButton>
                <VButton variant="ghost" size="sm" :disabled="generandoRemito === v.id" @click="verRemito(v)">
                  {{ generandoRemito === v.id ? 'Generando…' : v.numero_remito != null ? 'Remito' : 'Generar remito' }}
                </VButton>
                <VButton variant="ghost" size="sm" @click="abrirAnular(v)">Anular</VButton>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p v-else class="text-sm text-text-soft">Todavía no se generó ningún vale manual.</p>
  </VCard>

  <!-- Alta -->
  <VModal :open="modalNuevoAbierto" title="Generar vale manual" @update:open="modalNuevoAbierto = $event">
    <form class="space-y-3" @submit.prevent="guardar">
      <div v-if="errorForm" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">{{ errorForm }}</div>
      <p class="text-xs text-text-soft">
        Simulación: no suma a la producción ni a los despachos y no descuenta stock. El N° (M-…) lo asigna el sistema.
      </p>

      <label class="block text-sm text-text-mid">
        Fecha y hora *
        <input v-model="form.fecha" type="datetime-local" :class="inputClase" />
      </label>

      <div class="text-sm text-text-mid">
        Destino *
        <div class="mt-1 flex gap-4">
          <label class="flex items-center gap-1.5"><input v-model="form.destinoTipo" type="radio" value="obra" /> Obra</label>
          <label class="flex items-center gap-1.5"><input v-model="form.destinoTipo" type="radio" value="cliente" /> Cliente externo</label>
        </div>
        <select v-if="form.destinoTipo === 'obra'" v-model="form.obraId" :class="inputClase">
          <option value="">Elegí la obra…</option>
          <option v-for="o in obras" :key="o.id" :value="o.id">{{ o.nombre }}</option>
        </select>
        <template v-else>
          <input v-model="form.cliente" list="clientes-vale-manual" placeholder="Elegí o escribí el cliente…" :class="inputClase" />
          <datalist id="clientes-vale-manual">
            <option v-for="c in clientes" :key="c.id" :value="c.nombre" />
          </datalist>
        </template>
      </div>

      <label class="block text-sm text-text-mid">
        Mezcla *
        <select v-model="form.formulaId" :class="inputClase">
          <option value="">Elegí la mezcla…</option>
          <option v-for="f in formulasAsfalto" :key="f.id" :value="f.id">{{ f.nombre }}</option>
        </select>
      </label>

      <div class="grid grid-cols-3 gap-3">
        <label class="text-sm text-text-mid">
          Bruto (tn) *
          <input v-model="form.pesoBruto" type="text" inputmode="decimal" placeholder="Ej.: 38,5" :class="inputClase" />
        </label>
        <label class="text-sm text-text-mid">
          Tara (tn) *
          <input v-model="form.tara" type="text" inputmode="decimal" placeholder="Ej.: 14,2" :class="inputClase" />
        </label>
        <div class="text-sm text-text-mid">
          Neto
          <p class="mt-1 rounded-lg border border-border bg-gray-50 px-3 py-2 text-sm font-semibold" :class="netoForm != null && netoForm <= 0 ? 'text-danger' : 'text-text'">
            {{ netoForm != null ? `${formatearCantidadHasta(netoForm, 3)} tn` : '—' }}
          </p>
        </div>
      </div>

      <div class="grid grid-cols-3 gap-3">
        <label class="text-sm text-text-mid">
          Patente
          <input v-model="form.patente" list="patentes-vale-manual" :class="inputClase" />
          <datalist id="patentes-vale-manual">
            <option v-for="p in patentes" :key="p.id" :value="p.patente" />
          </datalist>
        </label>
        <label class="text-sm text-text-mid">
          Chofer
          <input v-model="form.chofer" type="text" :class="inputClase" />
        </label>
        <label class="text-sm text-text-mid">
          Temp. (°C)
          <input v-model="form.temperatura" type="text" inputmode="decimal" :class="inputClase" />
        </label>
      </div>

      <label class="block text-sm text-text-mid">
        Observación
        <input v-model="form.observaciones" type="text" placeholder="Ej.: retiro sin pesar" :class="inputClase" />
      </label>

      <div class="flex justify-end gap-2 pt-2">
        <VButton type="button" variant="secondary" @click="modalNuevoAbierto = false">Cancelar</VButton>
        <VButton type="submit" :disabled="guardando">{{ guardando ? 'Generando…' : 'Generar e imprimir' }}</VButton>
      </div>
    </form>
  </VModal>

  <!-- Anular -->
  <VModal :open="!!valeParaAnular" title="Anular vale manual" @update:open="!$event && (valeParaAnular = null)">
    <form v-if="valeParaAnular" class="space-y-3" @submit.prevent="confirmarAnular">
      <p class="text-sm text-text-mid">
        Vale <strong>{{ formatearNumeroValeManual(valeParaAnular.numero) }}</strong> — {{ destinoDe(valeParaAnular) }} —
        {{ formatearCantidadHasta(valeParaAnular.peso_neto) }} tn. No se borra: queda anulado, con el motivo, en el
        listado y en la auditoría.<template v-if="valeParaAnular.numero_remito != null">
          Su remito {{ formatearNumeroRemito(valeParaAnular.numero_remito) }} queda usado.</template>
      </p>
      <div v-if="errorAnular" class="rounded-lg border border-danger/20 bg-danger-light px-3 py-2 text-sm text-danger">{{ errorAnular }}</div>
      <label class="block text-sm text-text-mid">
        Motivo *
        <input v-model="motivoAnulacion" type="text" :class="inputClase" />
      </label>
      <div class="flex justify-end gap-2 pt-2">
        <VButton type="button" variant="secondary" @click="valeParaAnular = null">Cancelar</VButton>
        <VButton type="submit" variant="danger" :disabled="anulando">{{ anulando ? 'Anulando…' : 'Anular vale' }}</VButton>
      </div>
    </form>
  </VModal>

  <!-- Vale imprimible (mismo componente que Báscula) -->
  <Teleport to="body">
    <VModal :open="modalValeAbierto" title="Vale manual" size="xl" @update:open="modalValeAbierto = $event">
      <div ref="refVale" class="imprimible">
        <ValeImprimible
          v-if="valeImprimible"
          :vale="valeImprimible"
          :obra-nombre="destinoDe(valeParaImprimir)"
          :mezcla-nombre="mezclaDe(valeParaImprimir)"
          :cliente-externo="!!valeParaImprimir.cliente_externo"
          :acumulado-tn="Number(valeParaImprimir.peso_neto)"
        />
      </div>
      <div class="mt-4 flex flex-wrap justify-end gap-2">
        <VButton variant="secondary" @click="modalValeAbierto = false">Cerrar</VButton>
        <VButton variant="secondary" :disabled="generandoRemito === valeParaImprimir?.id" @click="verRemito(valeParaImprimir)">
          {{ valeParaImprimir?.numero_remito != null ? 'Ver remito' : 'Generar remito' }}
        </VButton>
        <VButton variant="secondary" :disabled="descargandoPdf" @click="descargarPdf(refVale)">
          {{ descargandoPdf ? 'Generando…' : 'Descargar PDF' }}
        </VButton>
        <VButton @click="imprimir">Imprimir</VButton>
      </div>
    </VModal>
  </Teleport>

  <!-- Remito imprimible (A4 vertical, mismo componente que Báscula y Remitos manuales) -->
  <Teleport to="body">
    <VModal :open="modalRemitoAbierto" title="Remito del vale manual" size="xl" @update:open="modalRemitoAbierto = $event">
      <div ref="refRemito" class="imprimible modo-remito">
        <RemitoImprimible v-if="remitoProps" v-bind="remitoProps" />
      </div>
      <div class="mt-4 flex justify-end gap-2">
        <VButton variant="secondary" @click="modalRemitoAbierto = false">Cerrar</VButton>
        <VButton variant="secondary" :disabled="descargandoPdf" @click="descargarPdf(refRemito)">
          {{ descargandoPdf ? 'Generando…' : 'Descargar PDF' }}
        </VButton>
        <VButton @click="imprimir">Imprimir</VButton>
      </div>
    </VModal>
  </Teleport>
</template>
