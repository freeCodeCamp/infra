import { defineConfig } from 'vite';
import { resolve } from 'path';
import dts from 'vite-plugin-dts';

export default defineConfig({
  plugins: [
    dts({
      include: ['src/**/*.ts'],
      exclude: ['src/**/*.test.ts', 'tests/**/*.ts']
    })
  ],
  build: {
    ssr: true,
    lib: {
      entry: resolve(__dirname, 'src/index.ts'),
      formats: ['es'],
      fileName: 'index'
    },
    outDir: 'dist',
    sourcemap: true,
    rollupOptions: {
      external: [
        'fs',
        'path',
        'url',
        '@grafana/grafana-foundation-sdk/dashboard',
        '@grafana/grafana-foundation-sdk/stat',
        '@grafana/grafana-foundation-sdk/timeseries',
        '@grafana/grafana-foundation-sdk/bargauge',
        '@grafana/grafana-foundation-sdk/logs',
        '@grafana/grafana-foundation-sdk/loki',
        '@grafana/grafana-foundation-sdk/common',
        'js-yaml'
      ]
    }
  },
  test: {
    globals: true,
    environment: 'node'
  }
});
