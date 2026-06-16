import { defineConfig } from 'vite';

export default defineConfig({
  resolve: {
    conditions: ['browser']
  },
  server: {
    port: 3000
  },
  build: {
    outDir: 'dist'
  }
});
