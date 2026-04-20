import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  // Absolute (not relative). Relative `./` breaks deep-route pages like
  // `/session/<name>`: the browser resolves `./app.js` to
  // `/session/app.js`, which isn't in the asset allowlist and falls
  // through the SPA handler to index.html — served with Content-Type
  // text/html. The browser then tries to execute that HTML as JS and
  // the session page renders blank.
  base: '/',
  build: {
    outDir: '../dist-tmp',
    emptyOutDir: true,
    assetsInlineLimit: 0,
    rollupOptions: {
      output: {
        entryFileNames: 'app.js',
        chunkFileNames: 'chunk-[name].js',
        assetFileNames: (info) => {
          const name = info.name ?? 'asset';
          if (name.endsWith('.css')) return 'app.css';
          return name;
        },
      },
    },
  },
});
