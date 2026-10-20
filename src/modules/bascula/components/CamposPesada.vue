<script setup>
// Campos de una pesada — los mismos en la puerta y en "Editar vale"
// (2026-10-20, pedido de Federico: la edición tiene que funcionar como una
// puerta, con los mismos desplegables y el autocompletado por patente, sin
// una copia aparte). Template puro: el formulario y la lógica viven en
// useBascula.js (formularioVacio/formEditar, completarDesdePatente,
// netoDeForm). El pedido lo pone cada uso en el slot `pedido` (la puerta
// elige entre los abiertos; la edición reasigna).
//
// Las listas con sugerencias de patentes y choferes (`patentes-conocidas`,
// `choferes-conocidos`) las arma BasculaView.vue una sola vez.
defineProps({
  form: { type: Object, required: true },
  tipo: { type: String, required: true },
  neto: { type: String, required: true },
  materiales: { type: Array, default: () => [] },
  proveedores: { type: Array, default: () => [] },
  obras: { type: Array, default: () => [] },
  // Solo en la edición: el material de un egreso no se cambia (anular y
  // cargar de nuevo), y el de un ingreso avisa que mueve el stock.
  materialEditable: { type: Boolean, default: true },
  materialOriginal: { type: String, default: null },
  // Solo en la edición: el neto antes de corregir, para mostrar el cambio.
  netoAnterior: { type: Number, default: null },
})
defineEmits(['cambio-patente'])
</script>

<template>
  <div class="grid grid-cols-2 gap-3">
    <template v-if="tipo === 'ingreso_arido'">
      <label class="text-sm text-text-mid">
        Material
        <!-- 2026-09-09 (pedido de Federico): antes texto libre, ahora
             desplegable sobre el catálogo real de Maestros
             (plantas_materiales) — mismo criterio que ya se usó para
             Egreso de áridos el 2026-09-08 (ver comentario más abajo). -->
        <select
          v-model="form.material"
          class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
        >
          <option value="" disabled>Elegir material…</option>
          <option v-if="form.material && !materiales.some((m) => m.nombre === form.material)" :value="form.material">{{ form.material }}</option>
          <option v-for="m in materiales" :key="m.id" :value="m.nombre">{{ m.nombre }}</option>
        </select>
        <span v-if="materialOriginal != null && form.material !== materialOriginal" class="mt-1 block text-xs text-text-soft">
          Al guardar, el stock sale de {{ materialOriginal }} y pasa a {{ form.material }}.
        </span>
      </label>
      <label class="text-sm text-text-mid">
        Proveedor
        <select
          v-model="form.proveedor"
          class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
        >
          <option value="" disabled>Elegir proveedor…</option>
          <option v-for="p in proveedores" :key="p.id" :value="p.nombre">{{ p.nombre }}</option>
        </select>
      </label>
      <label class="text-sm text-text-mid">
        N° de remito (obligatorio)
        <input
          v-model="form.numero_remito"
          type="text"
          class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
        />
      </label>
      <label class="text-sm text-text-mid col-span-2">
        Cantidad según remito (tn) (obligatorio)
        <input
          v-model.number="form.cantidad_remito"
          type="number"
          step="0.01"
          class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none md:w-1/3"
        />
        <span class="ml-2 text-xs text-text-soft">
          Valor declarado por el proveedor — independiente del peso neto pesado. El stock se actualiza con
          esta cantidad, no con el peso (memory/business-rules.md).
        </span>
      </label>
    </template>

    <template v-if="tipo === 'egreso_arido'">
      <label class="text-sm text-text-mid">
        Material
        <!-- 2026-09-08 (pedido de Federico): antes texto libre, ahora
             desplegable sobre el catálogo real de Maestros
             (plantas_materiales) — mismo criterio que
             Proveedor/Destino acá al lado. -->
        <select
          v-model="form.material"
          :disabled="!materialEditable"
          class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none disabled:bg-panel disabled:text-text-soft"
        >
          <option value="" disabled>Elegir material…</option>
          <option v-if="form.material && !materiales.some((m) => m.nombre === form.material)" :value="form.material">{{ form.material }}</option>
          <option v-for="m in materiales" :key="m.id" :value="m.nombre">{{ m.nombre }}</option>
        </select>
      </label>
      <label class="text-sm text-text-mid col-span-2">
        Destino (obra)
        <select
          v-model="form.obra_id"
          class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
        >
          <option value="" disabled>Elegir obra…</option>
          <option v-for="o in obras" :key="o.id" :value="o.id">{{ o.nombre }}</option>
        </select>
      </label>
    </template>

    <slot name="pedido" />

    <label class="text-sm text-text-mid">
      Patente
      <input
        v-model="form.patente"
        list="patentes-conocidas"
        class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
        @change="$emit('cambio-patente')"
      />
    </label>
    <!-- Chofer como la patente (2026-10-20, pedido de Federico): lista con
         sugerencias del maestro de Choferes, se completa sola con el chofer
         habitual de la patente y acepta escribir uno nuevo. -->
    <label v-if="tipo === 'asfalto'" class="text-sm text-text-mid">
      Chofer
      <input
        v-model="form.chofer"
        list="choferes-conocidos"
        class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
      />
    </label>
    <label v-if="tipo === 'asfalto'" class="text-sm text-text-mid">
      Temperatura (°C)
      <input
        v-model.number="form.temperatura"
        type="number"
        step="1"
        class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
      />
    </label>

    <label class="text-sm text-text-mid">
      Peso bruto (tn)
      <input
        v-model.number="form.peso_bruto"
        type="number"
        step="0.01"
        class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
      />
    </label>
    <label class="text-sm text-text-mid">
      Tara (tn)
      <input
        v-model.number="form.tara"
        type="number"
        step="0.01"
        class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
      />
    </label>
    <label class="text-sm text-text-mid">
      Neto (calculado)
      <input
        :value="neto"
        type="text"
        disabled
        class="mt-1 w-full rounded-lg border border-border bg-panel px-3 py-2 text-sm text-text-soft"
      />
    </label>
    <p v-if="netoAnterior != null && Number(neto) !== Number(netoAnterior)" class="col-span-2 text-xs text-text-soft">
      Neto: {{ Number(netoAnterior).toFixed(2) }} → {{ neto }} tn<template v-if="tipo === 'asfalto'"> · se recalcula el acumulado de este vale y de los siguientes del pedido</template>.
    </p>
  </div>

  <label class="mt-3 block text-sm text-text-mid">
    Observaciones
    <textarea
      v-model="form.observaciones"
      rows="2"
      class="mt-1 w-full rounded-lg border border-border px-3 py-2 text-sm focus:border-vialtec focus:outline-none"
    ></textarea>
  </label>
</template>
