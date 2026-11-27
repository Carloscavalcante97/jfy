import { resolve } from 'node:path'
import { defineConfig } from 'electron-vite'
import react from '@vitejs/plugin-react'

// a marca (fontes e símbolo da Souv) e a JFY Mono ficam no repo, junto do app do Mac: não duplicamos os arquivos
export default defineConfig({
  main: {},
  preload: {},
  renderer: {
    plugins: [react()],
    resolve: { alias: { '@marca': resolve('../app/Marca'), '@fonte': resolve('../fonte') } },
    server: { fs: { allow: [resolve('..')] } }
  }
})
