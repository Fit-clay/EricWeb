import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "standalone",
  outputFileTracingIncludes: {
    "/*": ["./node_modules/better-sqlite3/**/*"],
  },
};

export default nextConfig;
