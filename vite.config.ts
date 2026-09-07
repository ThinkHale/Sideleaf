import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
export default defineConfig({
  plugins: [
    react(),
    {
      name: 'version-offline-shell',
      async closeBundle() {
        const html = await readFile('dist/web/index.html', 'utf8');
        const worker = await readFile('public/sw.js', 'utf8');
        const version = createHash('sha256').update(html).digest('hex').slice(0, 12);
        await writeFile('dist/web/sw.js', worker.replace('BUILD_VERSION', version));
      },
    },
  ],
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
    proxy: { '/api': 'http://127.0.0.1:3001' },
  },
  build: { outDir: 'dist/web' },
});
