import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const host = process.env.TAURI_DEV_HOST;

export default defineConfig({
  plugins: [react(), {
    name: 'classset-webmcp-origin-trial',
    apply: 'build',
    transformIndexHtml() {
      const token = process.env.CLASSSET_WEBMCP_ORIGIN_TRIAL_TOKEN?.trim();
      if (!token || process.env.TAURI_ENV_PLATFORM) return [];
      return [{ tag: 'meta', attrs: { 'http-equiv': 'origin-trial', content: token }, injectTo: 'head-prepend' }];
    },
  }],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  clearScreen: false,
  server: {
    port: 1420,
    strictPort: true,
    host: host || '0.0.0.0',
    hmr: host
      ? {
          protocol: 'ws',
          host,
          port: 1421,
        }
      : {
          protocol: 'ws',
          host: 'localhost',
        },
    watch: {
      usePolling: true,
      interval: 300,
      ignored: [
        '**/node_modules/**',
        '**/.git/**',
        '**/src-tauri/**',
        '**/build/**',
        '**/dist/**',
        '**/.dart_tool/**',
        '**/macos/**',
        '**/linux/**',
        '**/windows/**',
        '**/lib/**',
        '**/website/**',
      ],
    },
  },
  envPrefix: ['VITE_', 'TAURI_ENV_*'],
  build: {
    target:
      process.env.TAURI_ENV_PLATFORM == 'windows' ? 'chrome105' : 'safari14',
    minify: !process.env.TAURI_ENV_DEBUG ? 'esbuild' : false,
    sourcemap: !!process.env.TAURI_ENV_DEBUG,
  },
});
