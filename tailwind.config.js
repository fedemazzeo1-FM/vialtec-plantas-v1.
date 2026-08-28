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
        border: '#EAECF0',
        success: { DEFAULT: '#027A48', light: '#ECFDF3' },
        danger: { DEFAULT: '#B42318', light: '#FEF3F2' },
        warning: { DEFAULT: '#B54708', light: '#FFFAEB' },
        info: { DEFAULT: '#1D4ED8', light: '#EFF6FF' },
      },
      fontFamily: {
        sans: ['Manrope', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
