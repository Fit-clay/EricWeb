import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  cacheMaxMemorySize: 0,
  outputFileTracingIncludes: {
    "/*": ["./node_modules/better-sqlite3/**/*"],
  },
};

export default nextConfig;
