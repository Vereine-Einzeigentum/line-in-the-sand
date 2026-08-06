import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";

export default defineConfig({
  plugins: [svelte()],
  build: {
    outDir: "../priv/static/assets",
    emptyOutDir: false,
    rollupOptions: {
      input: "src/main.js",
      output: {
        entryFileNames: "js/app.js",
        chunkFileNames: "js/[name].js",
        assetFileNames: "css/app[extname]",
      },
    },
    sourcemap: true,
    minify: false,
  },
});
