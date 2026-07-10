import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// base '/' weil app.stoecklilager.com als eigene Domain via CNAME dient
// (kein github.io/<repo>-Unterpfad)
export default defineConfig({
  plugins: [vue()],
  base: '/',
  server: {
    port: 3000
  }
})
