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
        // Contraste (2026-09-30, pedido de Federico: en monitores comunes las
        // cards se perdían contra el fondo). Primero se probó slate-300 +
        // fondo gris marcado y quedó demasiado pesado — "encontrar un
        // intermedio, más cerca del anterior". Valores finales: apenas un
        // paso más que el original de Flota (#EAECF0 / fondo blanco).
        border: '#E1E5EB',
        // Fondo general de la página (detrás de las cards blancas) y de los
        // paneles/encabezados de tabla dentro de una card.
        fondo: '#F5F7FA',
        panel: '#F7F8FA',
        success: { DEFAULT: '#027A48', light: '#ECFDF3' },
        danger: { DEFAULT: '#B42318', light: '#FEF3F2' },
        warning: { DEFAULT: '#B54708', light: '#FFFAEB' },
        info: { DEFAULT: '#1D4ED8', light: '#EFF6FF' },
      },
      // shadow-sm (usada por todas las cards): apenas más visible que la de
      // Tailwind por default (0 1px 2px / 5%).
      boxShadow: {
        sm: '0 1px 2px 0 rgb(16 24 40 / 0.06), 0 1px 3px 0 rgb(16 24 40 / 0.04)',
      },
      fontFamily: {
        sans: ['Manrope', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
