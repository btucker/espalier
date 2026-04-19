#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB="$ROOT/web-client"
RES="$ROOT/Sources/EspalierKit/Web/Resources"

if ! command -v pnpm >/dev/null 2>&1; then
  echo "ERROR: pnpm not found. Install with: brew install pnpm" >&2
  exit 1
fi

echo "→ pnpm install (frozen lockfile)"
(cd "$WEB" && pnpm install --frozen-lockfile)

echo "→ pnpm build"
(cd "$WEB" && pnpm build)

echo "→ copying build artifacts to $RES"
cp "$ROOT/dist-tmp/index.html" "$RES/index.html"
cp "$ROOT/dist-tmp/app.js"     "$RES/app.js"
cp "$ROOT/dist-tmp/app.css"    "$RES/app.css"

WTERM_VER=$(cd "$WEB" && node -p "require('./node_modules/@wterm/react/package.json').version" 2>/dev/null || echo "unknown")
printf "wterm-react: %s\n" "$WTERM_VER" > "$RES/VERSION"

echo "→ done. Artifacts in $RES:"
ls -la "$RES"
