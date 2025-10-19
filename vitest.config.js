import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "clarinet", // Use clarinet environment
    singleThread: true,
    testTimeout: 30000,
  },
});