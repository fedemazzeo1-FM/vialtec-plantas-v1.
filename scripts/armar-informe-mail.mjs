// Arma supabase/functions/informe-produccion/plantas.bundle.js y logo.bundle.js (16/11/2026): los services del informe mensual de
// Despachos empaquetados para Deno (Edge Function). Correr después de tocar cualquier archivo que use el informe
// (informe-mensual.service, excel-informe-mensual, despachos.service, tipos-producto, comparativo-mes, …) y antes de
// desplegar la función:  node scripts/armar-informe-mail.mjs
//   · '@/config/supabase' → fuente/cliente.js (la función pasa su cliente con service_role).
//   · '@/…' → src/… (mismo alias que vite.config.js).
//   · *.png → módulo vacío (el logo lo pasa la función como bytes).
//   · exceljs y @supabase/supabase-js quedan afuera, como npm: de Deno (versiones fijas).
import { build } from 'esbuild'
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const raiz = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const carpeta = join(raiz, 'supabase/functions/informe-produccion')

const archivo = (base) =>
  [base, `${base}.js`, join(base, 'index.js')].find((c) => existsSync(c) && statSync(c).isFile())

const plantas = {
  name: 'plantas',
  setup(b) {
    b.onResolve({ filter: /^@\/config\/supabase(\.js)?$/ }, () => ({ path: join(carpeta, 'fuente/cliente.js') }))
    b.onResolve({ filter: /\.png$/ }, (a) => ({ path: a.path, namespace: 'vacio' }))
    b.onLoad({ filter: /.*/, namespace: 'vacio' }, () => ({ contents: 'export default ""', loader: 'js' }))
    b.onResolve({ filter: /^@\// }, (a) => {
      const encontrado = archivo(join(raiz, 'src', a.path.slice(2)))
      if (!encontrado) return { errors: [{ text: `No existe ${a.path}` }] }
      return { path: encontrado }
    })
    b.onResolve({ filter: /^exceljs$/ }, () => ({ path: 'npm:exceljs@4.4.0', external: true }))
    b.onResolve({ filter: /^@supabase\/supabase-js$/ }, () => ({ path: 'npm:@supabase/supabase-js@2', external: true }))
  },
}

await build({
  entryPoints: [join(carpeta, 'fuente/entrada.js')],
  outfile: join(carpeta, 'plantas.bundle.js'),
  bundle: true,
  format: 'esm',
  platform: 'neutral',
  target: 'es2022',
  banner: { js: '// GENERADO por scripts/armar-informe-mail.mjs — no editar a mano.\n// deno-lint-ignore-file' },
  plugins: [plantas],
  logLevel: 'info',
})

// Logo del Excel: el de la pantalla (src/assets/img/logo-vialtec.png) achicado a 306 px de ancho (se ve a 102×44 en
// la hoja; el original pesa 115 KB). Si cambia el logo: sips -Z 306 src/assets/img/logo-vialtec.png --out
// supabase/functions/informe-produccion/fuente/logo-excel.png
const logo = readFileSync(join(carpeta, 'fuente/logo-excel.png')).toString('base64')
writeFileSync(
  join(carpeta, 'logo.bundle.js'),
  `// GENERADO por scripts/armar-informe-mail.mjs — no editar a mano.\nexport const LOGO_EXCEL_BASE64 = '${logo}'\n`,
)
