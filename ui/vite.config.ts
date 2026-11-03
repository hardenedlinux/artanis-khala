import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  base: '/khala/',
  plugins: [react()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    proxy: {
      '/api': 'http://127.0.0.1:3130',
      '/ws': { target: 'ws://127.0.0.1:3130', ws: true },
      '/view': 'http://127.0.0.1:3130',
      '/upload': 'http://127.0.0.1:3130',
      '/object_info': 'http://127.0.0.1:3130',
      '/prompt': 'http://127.0.0.1:3130',
      '/history': 'http://127.0.0.1:3130',
      '/queue': 'http://127.0.0.1:3130',
      '/interrupt': 'http://127.0.0.1:3130',
      '/khala/api': 'http://127.0.0.1:3130',
    },
  },
})
