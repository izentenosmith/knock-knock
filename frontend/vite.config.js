import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  // `npm run dev` knocks through the compose frontend.
  server: { proxy: { '/api': 'http://localhost:8080' } },
})
