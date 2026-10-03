import {
  defineConfig,
} from 'vite'

import react
  from '@vitejs/plugin-react'

const githubPages =
  process.env
    .GITHUB_ACTIONS
  === 'true'

export default defineConfig({
  base:
    githubPages
      ? '/abraxas-publisher/'
      : '/',

  plugins: [
    react(),
  ],

  clearScreen:
    false,

  server: {
    port: 1420,
    strictPort: true,
    host:
      '127.0.0.1',
  },

  envPrefix: [
    'VITE_',
    'TAURI_',
  ],
})
