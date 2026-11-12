import { defineConfig } from "vitest/config";

export default defineConfig({
  test: { include: ["starhope/**/*.test.ts"], environment: "node" },
});
