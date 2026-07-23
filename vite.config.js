import { defineConfig } from "vite";
import { fileURLToPath, URL } from "node:url";

const root = fileURLToPath(new URL("./frontend", import.meta.url));

export default defineConfig({
  root,
  envDir: fileURLToPath(new URL("./", import.meta.url)),
  build: {
    outDir: "dist",
    emptyOutDir: true,
    rollupOptions: {
      input: {
        landing: fileURLToPath(new URL("./frontend/index.html", import.meta.url)),
        app: fileURLToPath(new URL("./frontend/app.html", import.meta.url))
      }
    }
  }
});

