#!/usr/bin/env bash
# Invoked inside the LOCAL Linux build container. No server connection is made here.
set -Eeuo pipefail
ARCH="${1:?Missing architecture}"
case "$ARCH" in amd64|arm64) ;; *) exit 2 ;; esac
[[ "$(node -p 'process.platform')" == linux ]]
EXPECTED_NODE_ARCH=x64
[[ "$ARCH" != arm64 ]] || EXPECTED_NODE_ARCH=arm64
[[ "$(node -p 'process.arch')" == "$EXPECTED_NODE_ARCH" ]]
export NEXT_TELEMETRY_DISABLED=1
npm ci --no-audit --no-fund
npm test
python3 tests/html-publish.test.py
mkdir -p .release/payload/.next .release/payload/runtime .release/payload/scripts
cp -a .next/standalone .release/payload/.next/standalone
# Production HTML lives in its persistent directory, outside the Node application.
rm -rf .release/payload/.next/standalone/html-pages
find .release/payload/.next/standalone/node_modules/better-sqlite3/prebuilds \
  -type f ! -name "linux-$EXPECTED_NODE_ARCH.node" -delete
cp "$(command -v node)" .release/payload/runtime/node
cp scripts/deploy-vps-remote.sh scripts/publish-html-remote.py .release/payload/scripts/
cp -a html-pages .release/payload/html-pages
node -e 'const fs=require("fs"); fs.writeFileSync(".release/payload/manifest.json", JSON.stringify({format:1,platform:process.platform,arch:process.arch,node:process.versions.node,tested:true}))'
tar -czf .release/release.tar.gz -C .release/payload .
echo 'Local Linux compilation, production tests and runtime packaging completed.'
