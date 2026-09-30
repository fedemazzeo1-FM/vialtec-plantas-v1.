/** @type {import('tailwindcss').Config} */
// Paleta y tipografía clonadas de la identidad visual de Flota
// (equipos2.vialtec.app) — ver memory/guia-estilo-flota.md para el detalle
// y las fuentes exactas de cada valor.
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
        // Contraste reforzado (2026-09-30, pedido de Federico: en monitores
        // comunes/de bajo contraste las cards se perdían contra el fondo).
        // Antes #EAECF0 (borde de Flota) — ahora slate-300, bien visible.
        border: '#CBD5E1',
        // Fondo general de la página (detrás de las cards blancas) y de los
        // paneles/encabezados de tabla dentro de una card.
        fondo: '#E9EDF2',
        panel: '#F1F5F9',
        success: { DEFAULT: '#027A48', light: '#ECFDF3' },
        danger: { DEFAULT: '#B42318', light: '#FEF3F2' },
        warning: { DEFAULT: '#B54708', light: '#FFFAEB' },
        info: { DEFAULT: '#1D4ED8', light: '#EFF6FF' },
      },
      // shadow-sm (usada por todas las cards) un punto más marcada que la de
      // Tailwind por default — mismo criterio de contraste de arriba.
      boxShadow: {
        sm: '0 1px 3px 0 rgb(15 23 42 / 0.12), 0 1px 2px -1px rgb(15 23 42 / 0.10)',
      },
      fontFamily: {
        sans: ['Manrope', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
