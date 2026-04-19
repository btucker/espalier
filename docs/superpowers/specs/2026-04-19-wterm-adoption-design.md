# wterm Adoption — Web UI Design Specification

Replace xterm.js in Espalier's web access client with [wterm](https://github.com/vercel-labs/wterm), Vercel Labs' DOM-rendering, WASM-core terminal emulator (Apache-2.0). Introduce a minimal React + Vite + TypeScript build pipeline in a new `web-client/` workspace. The Swift server side is unchanged except for a small asset-table and MIME-map edit.

## Motivation

The Phase 2 Web Access feature shipped with xterm.js. xterm.js renders to a `<canvas>`, which fights the platform on text selection, browser find, and screen-reader accessibility. wterm renders to the DOM with native selection, clipboard, browser find, alternate-screen-buffer support, and CSS-custom-property themes. Its Zig→WASM core is ~12 KB.

Beyond the immediate UX wins, wterm has a first-class React package (`@wterm/react`) with a `useTerminal` hook. The Phase 2 spec names a future "Phase 3" client built on TanStack Router. Adopting wterm now — together with the React + Vite toolchain it implies — puts that foundation in place so Phase 3 sub-projects (server-side session API, sidebar mirror, split layout, mobile polish) can each ship as a cheap addition rather than a toolchain introduction.

This spec scopes **one sub-project** out of that larger Phase 3 work: the frontend swap itself. No new Swift surfaces. No new protocol bytes. No new auth posture. A focused refactor PR.

## Goal

After this PR lands:

- The browser pane is rendered by wterm. A phone long-press on terminal output produces a native iOS text-selection handle, not a canvas-rendered pseudo-selection.
- Espalier ships a React + Vite + TypeScript workspace at `web-client/`. Any future web-UI work composes React components instead of appending to a single `<script>` block.
- The WebSocket protocol is byte-for-byte unchanged: binary frames carry PTY bytes, text frames carry the `{"type":"resize",…}` envelope.
- Developers who touch only Swift are unaffected — the built JS bundle is committed to `Sources/EspalierKit/Web/Resources/`, and `swift build` alone works.
- Developers who touch the web client run `./scripts/build-web.sh` to refresh the committed bundle. CI enforces that the committed bundle matches a fresh build.

## Non-Goals

- No TanStack Router, no session list view, no sidebar mirror, no multi-pane split rendering. Those are separate Phase 3 sub-projects that reuse this spec's scaffolding.
- No new HTTP endpoints, no new WS envelope shapes, no allowlist extension to the WhoIs gate. The server's public contract is unchanged.
- No frontend tests. The existing server-side integration test `attachesAndEchoes` proves bytes round-trip; that's sufficient for a refactor with no new logic.
- No CDN imports; wterm's runtime is vendored. The whole point of Tailscale-only binding is that the Mac is reachable without public internet, and so is the client.

## Architecture

```
Repository layout
─────────────────

  web-client/                      ← NEW workspace
    package.json                     pnpm-managed
    pnpm-lock.yaml
    vite.config.ts                   fixed output filenames, no hashes
    tsconfig.json
    src/
      main.tsx                       React root
      App.tsx                        useTerminal + WS plumbing + resize
      styles.css                     page chrome + CSS-custom-property theme

  scripts/
    build-web.sh                   ← NEW
                                     pnpm install --frozen-lockfile
                                     pnpm build
                                     copy dist into Resources/

  Sources/EspalierKit/Web/Resources/
    index.html                       ← REPLACED (Vite-generated)
    app.js                           ← REPLACED (React + @wterm/react bundle)
    app.css                          ← REPLACED
    wterm.wasm                       ← NEW
    VERSION                          ← updated (wterm version + git SHA)
    LICENSE-wterm                    ← NEW (Apache-2.0 text)
    NOTICE-wterm                     ← NEW iff upstream ships a NOTICE file
    ── REMOVED ──
    xterm.min.js
    xterm.min.css
    xterm-addon-fit.min.js
```

The Swift server's public contract — `GET /`, `GET /<asset>`, `/ws?session=<name>` upgrade, owner-only `WhoIs` gate, Tailscale-IP + loopback binding — is unchanged. The only Swift code touched is:

- `Sources/EspalierKit/Web/WebStaticResources.swift` — asset-table entries and a new extension-to-MIME map that includes `application/wasm`.
- `Sources/EspalierKit/Web/WebServer.swift` — conditional addition of `Cross-Origin-Opener-Policy` + `Cross-Origin-Embedder-Policy` response headers **only if** wterm requires cross-origin isolation; verified at implementation time (see §Error Handling).

## Components

### New — `web-client/` workspace

Lives at repo root next to `Sources/`, `Tests/`, `Resources/`, `docs/`, `scripts/`. It's not a Swift package — it's a pnpm workspace whose build output is copied into the EspalierKit target's Resources.

- **`package.json`** — declares dependencies (`react`, `react-dom`, `@wterm/react`) and dev-dependencies (`vite`, `@vitejs/plugin-react`, `typescript`, `@types/react`, `@types/react-dom`). One script: `"build": "vite build"`. Uses `"type": "module"`.
- **`pnpm-lock.yaml`** — committed. `build-web.sh` uses `--frozen-lockfile` so CI builds exactly what the developer built.
- **`vite.config.ts`** — production-only config. Key options:
  - `base: './'` — relative asset paths so the built `index.html` works when served at any root.
  - `build.rollupOptions.output.entryFileNames: 'app.js'`, `chunkFileNames: 'chunk-[name].js'`, `assetFileNames: (info) => info.name ?? 'asset'` — no content hashes. The Espalier web server is ephemeral and bound to a user-visible port; cache-busting isn't needed and predictable filenames let `WebStaticResources.asset(for:)` stay a trivial static map.
  - `build.outDir: '../dist-tmp'` — outside the workspace, gitignored. `scripts/build-web.sh` then selectively copies files into the Swift Resources directory (so stray build artifacts don't leak into Resources).
  - `build.assetsInlineLimit: 0` — forces `.wasm` to emit as a separate file rather than inline as a data URL, so the browser can stream it via `WebAssembly.instantiateStreaming`.
- **`tsconfig.json`** — `strict: true`. `module: "ESNext"`, `target: "ES2020"`, `jsx: "react-jsx"`, `moduleResolution: "bundler"`.
- **`src/main.tsx`** — two lines: `createRoot(document.getElementById('root')!).render(<App/>)`. Reads no URL state; that's `App`'s job.
- **`src/App.tsx`** — the whole runtime. Pseudocode shape:
  ```tsx
  function App() {
    const session = new URLSearchParams(location.search).get('session');
    const [status, setStatus] = useState<'connecting' | 'connected' | 'disconnected' | string>('connecting');
    const { ref, write, onData, onResize } = useTerminal({ theme: ... });
    const wsRef = useRef<WebSocket | null>(null);

    useEffect(() => {
      if (!session) { setStatus('missing ?session='); return; }
      const ws = new WebSocket(`${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/ws?session=${encodeURIComponent(session)}`);
      ws.binaryType = 'arraybuffer';
      ws.onopen = () => { setStatus(session); };
      ws.onmessage = (ev) => {
        if (ev.data instanceof ArrayBuffer) write(new Uint8Array(ev.data));
        else handleControl(ev.data);
      };
      ws.onclose = () => setStatus('disconnected');
      ws.onerror = () => setStatus('error');
      wsRef.current = ws;
      return () => ws.close();
    }, [session]);

    onData((bytes) => { wsRef.current?.send(bytes); });
    onResize(({ cols, rows }) => {
      wsRef.current?.send(JSON.stringify({ type: 'resize', cols, rows }));
    });

    return (
      <>
        <div id="status">{status}</div>
        <div ref={ref} id="term" />
      </>
    );
  }
  ```
  The exact hook API (`write`/`onData`/`onResize` vs a different shape) is TBD at implementation — to be confirmed against `@wterm/react`'s published types. The semantic contract (byte-for-byte protocol compatibility with the current server) is fixed.
- **`src/styles.css`** — full-height container, dark background, status-overlay positioning. wterm theme is set on `:root` via CSS custom properties (`--wterm-foreground`, etc.) so Espalier can later theme it from settings without touching the JS.

### New — `scripts/build-web.sh`

Mirrors the shape of `scripts/bump-zmx.sh`. Idempotent bash script with `set -euo pipefail`. Responsibilities:

1. Check `pnpm --version` exists; if not, print a clear install hint and exit 1.
2. `cd web-client && pnpm install --frozen-lockfile && pnpm build`.
3. Copy from `web-client/dist-tmp/`:
   - `index.html` → `Sources/EspalierKit/Web/Resources/index.html`
   - `app.js` → `Sources/EspalierKit/Web/Resources/app.js`
   - `app.css` → `Sources/EspalierKit/Web/Resources/app.css`
   - `wterm.wasm` (or whatever filename `@wterm/react` emits) → `Sources/EspalierKit/Web/Resources/wterm.wasm`
4. Write `Resources/VERSION` with: wterm-react package version, wterm git SHA, build timestamp.
5. Print a diff summary so the developer knows what changed.

The script does NOT run on `swift build`. It's an explicit step — developer runs it when they change the frontend.

### Modified — `Sources/EspalierKit/Web/WebStaticResources.swift`

Replace the hardcoded URL-path switch with a small two-stage lookup:

```swift
public static func asset(for urlPath: String) throws -> Asset {
    let filename = try resolveFilename(urlPath)
    let (base, ext) = splitName(filename)
    guard let url = Bundle.module.url(forResource: base, withExtension: ext) else {
        throw Error.missingResource(filename)
    }
    let data = try Data(contentsOf: url)
    return Asset(contentType: contentType(forExtension: ext), data: data)
}

private static func resolveFilename(_ urlPath: String) throws -> String {
    switch urlPath {
    case "/", "/index.html": return "index.html"
    case "/app.js":           return "app.js"
    case "/app.css":          return "app.css"
    case "/wterm.wasm":       return "wterm.wasm"
    default: throw Error.missingResource(urlPath)
    }
}

private static func contentType(forExtension ext: String) -> String {
    switch ext.lowercased() {
    case "html": return "text/html; charset=utf-8"
    case "js":   return "application/javascript; charset=utf-8"
    case "css":  return "text/css; charset=utf-8"
    case "wasm": return "application/wasm"
    default:     return "application/octet-stream"
    }
}
```

The swap has one non-obvious requirement: **`.wasm` must be served with `Content-Type: application/wasm`**. `WebAssembly.instantiateStreaming()` rejects any other MIME type. Getting this wrong fails closed (browser throws) but produces a confusing error; the integration test below pins it.

### Modified — `Sources/EspalierKit/Web/WebServer.swift`

Potentially: add `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` on every HTTP response. Required **only** if wterm uses `SharedArrayBuffer` in its WASM core. To be verified at implementation time (see §Error Handling). If not required, this file is unchanged.

### Modified — `Package.swift`

No changes. The `resources: [.copy("Web/Resources")]` declaration already captures the directory's contents; new files appear automatically.

### Modified — `README.md`

Add a "Developing the web client" section:

> Espalier's web access client lives in `web-client/` (React + Vite + TypeScript). When you change it, run `./scripts/build-web.sh` to rebuild the bundle that ships with the app. CI verifies the committed bundle matches a fresh build.
>
> You need `node` (LTS) and `pnpm` installed locally for web-client work. If you only touch Swift, you need neither — the committed bundle is what `swift build` ships.

### Modified — CI config

Whatever runs on PRs today gets a new early step:

```
./scripts/build-web.sh
git diff --exit-code Sources/EspalierKit/Web/Resources/
```

If the committed Resources don't match a fresh build, CI fails. The error message is obvious ("developer forgot to run build-web.sh"). No drift between source and built artifact.

### Modified — `SPECS.md §15 Web Access`

- **WEB-3.1** — rewrite to "the application shall serve a single static page at `/` (and `/index.html`) that bootstraps the bundled web client." Drop "xterm.js".
- New **WEB-3.x** (after 3.1) — "When a client requests `/wterm.wasm` (or any `.wasm` resource), the application shall respond with `Content-Type: application/wasm`."
- **WEB-5.1** — rewrite to "the bundled client shall render a single terminal (wterm) that attaches to the session indicated by the `?session=` query parameter." Drop xterm.js mention.
- **WEB-5.2** — no behavioral change; reword to not name the emulator ("The client shall send terminal data events as binary WebSocket frames.").
- Add **WEB-3.y** only if COEP/COOP is required (see Error Handling): "The application shall respond to every HTTP request with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers."

### Removed

`Sources/EspalierKit/Web/Resources/xterm.min.js`, `xterm.min.css`, `xterm-addon-fit.min.js`.

### Unchanged

Everything else. `WebSession`, `PtyProcess`, `TailscaleLocalAPI`, `WebControlEnvelope`, `WebURLComposer`, `WebServerController`, `WebSettingsPane`, the entire zmx layer, the entire native-pane layer. The WebSocket protocol bytes are untouched.

## Data Flow

**Flow 1 — browser loads `/`**

1. `GET /` passes the `WhoIs` gate (unchanged).
2. Server returns the Vite-generated `index.html`. It contains `<link rel="stylesheet" href="./app.css">`, `<script type="module" src="./app.js">`, `<div id="root">`.
3. Browser requests `/app.css`, `/app.js`. Served from Resources.
4. `app.js` runs. React mounts `<App>`. `@wterm/react` initializes its WASM core by fetching `/wterm.wasm`.
5. Server serves `/wterm.wasm` with `Content-Type: application/wasm`. `WebAssembly.instantiateStreaming()` succeeds.
6. Terminal DOM renders. App reads `?session=` from `location.search` and opens `/ws?session=<encoded>`.

**Flow 2 — keystrokes from browser** — identical to Phase 2. `@wterm/react`'s `onData` callback emits UTF-8-encoded key bytes; `App.tsx` sends them as a binary WS frame.

**Flow 3 — output to browser** — identical to Phase 2. Server sends binary WS frame with PTY bytes; `App.tsx` calls the hook's `write(Uint8Array)` with the payload.

**Flow 4 — resize** — identical to Phase 2. `@wterm/react`'s `onResize` callback fires with `{ cols, rows }`; `App.tsx` sends `{"type":"resize","cols":N,"rows":M}` as a text frame. Server-side `ioctl(TIOCSWINSZ)` path is unchanged.

**Flow 5 — WS close / disconnect / app quit** — identical to Phase 2. Server-side behavior unchanged; client's React cleanup effect calls `ws.close()` on unmount.

The only new byte moving across the network compared to Phase 2 is `wterm.wasm` on first page load.

## Error Handling

The principle from Phase 2 carries forward: **Espalier remains fully usable with the web feature disabled or broken. The server's public contract is unchanged, so all Phase 2 failure modes are preserved.**

### New failure modes

- **`wterm.wasm` missing from bundle** (botched release build) — `WebStaticResources.asset(for: "/wterm.wasm")` throws `missingResource`. Server returns `404`. Browser logs a clear error; the app status line shows "error". Pinned by the `servesWasmWithCorrectMime` integration test: if the file were missing, the test would fail before any user saw it.
- **`.wasm` served with wrong content-type** — browser's `WebAssembly.instantiateStreaming()` rejects with `TypeError: Incorrect response MIME type`. Pinned by the same integration test, which asserts both status 200 AND content-type.
- **`build-web.sh` forgot to run before commit** — CI fails on `git diff --exit-code`. Developer re-runs the script and re-commits. No runtime impact; caught pre-merge.
- **`pnpm install --frozen-lockfile` fails in CI** (registry outage, lockfile drift) — CI fails at the build step. No impact on release builds, since the release artifact is already in Resources.
- **Developer runs `./scripts/build-web.sh` without node/pnpm installed** — script prints an install hint and exits 1. No partial-write hazard.

### Conditional: COEP/COOP headers

wterm's WASM core may or may not use `SharedArrayBuffer`. If it does, the browser requires **cross-origin isolation** via two response headers on **every** HTTP response:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`

Verification plan at implementation time:

1. Complete the bundle swap without adding headers.
2. Open the app in Safari. Open the browser console.
3. If the console shows a COEP/COOP error before the terminal renders, add the headers to `HTTPHandler.handle(…)` in `WebServer.swift`, update `SPECS.md` with **WEB-3.y**, rebuild.
4. If no error, headers are not added, and **WEB-3.y** stays out of SPECS.md.

This is not a placeholder — it's an explicit decision gate with a reproducible test. The answer is determined by running the code once.

### Phase 2 failure modes — all preserved

Tailscale-not-running, WhoIs-denies-peer, port-unavailable, zmx-attach-fails, attach-child-exits, session-ended: all unchanged because the server's public contract is unchanged.

## Testing

### Unit tests — `Tests/EspalierKitTests/Web/`

Existing `WebStaticResources` unit test (if one exists; if not, add one):

- Assert `asset(for: "/")` returns HTML.
- Assert `asset(for: "/app.js")` returns JavaScript.
- Assert `asset(for: "/app.css")` returns CSS.
- **New:** Assert `asset(for: "/wterm.wasm")` returns a non-empty payload with `Content-Type: application/wasm`, and that the first four bytes are the WASM magic `\x00\x61\x73\x6d`.
- Assert `asset(for: "/does-not-exist")` throws `missingResource`.

### Integration tests — `Tests/EspalierKitTests/Web/WebServerIntegrationTests.swift`

- **`startsAndServesIndex`** — update the HTML-content assertion from "contains xterm.js script tag" to "contains `<script type=\"module\" src=\"./app.js\">` and `<div id=\"root\">`".
- **`servesWasmWithCorrectMime`** — **NEW**. GET `/wterm.wasm`, assert response code 200, assert `Content-Type: application/wasm`, assert body is non-empty and begins with `\x00\x61\x73\x6d`.
- **`attachesAndEchoes`**, **`deniesNonOwner`**, **`resizesPty`**, **`closesChildOnWsDisconnect`** — unchanged. These exercise server behavior, not client behavior. They continue to prove bytes round-trip through the WS protocol.

### Frontend tests — intentionally none for this sub-project

The React component is a thin wrapper over `useTerminal` + a WebSocket. Its logic is end-to-end-tested by the server-side `attachesAndEchoes` integration test: a round-trip byte echo proves both that the client can render bytes it receives and emit keystrokes over the WS. Phase 3 sub-projects (routing, state management, multi-pane layout) will introduce logic that warrants component tests; that's not this spec.

### Manual smoke checklist — `docs/superpowers/plans/ZmxWebAccessSmokeChecklist.md`

Update from Phase 2's six steps to seven. Insert one new step after today's step 1:

> **Step 1.5 (new).** In Safari on the phone, long-press a word of terminal output. A **native** iOS text-selection handle should appear (not a canvas-rendered pseudo-selection). Copy the selected text; paste into another app; confirm the bytes match what was on screen. This validates the core UX reason for adopting wterm.

The other six steps are unchanged. Step 5 ("Tailscale unavailable") and step 6 ("browser tab closed while command runs") particularly matter to re-run — they prove the server-side posture survived the swap.

## Acceptance Criteria

This PR is done when all of the following hold:

1. `swift test` passes with the same skip set as before (no new skips). The new `servesWasmWithCorrectMime` test passes on every platform CI exercises.
2. `./scripts/build-web.sh && git diff --exit-code` produces no diff from a clean checkout.
3. The updated seven-step smoke checklist passes, including the new native-text-selection step.
4. `SPECS.md §15` reflects current reality: no "xterm.js" references; **WEB-3.x** (WASM MIME) added; **WEB-3.y** (COEP/COOP) added iff wterm required it at implementation time.
5. `README.md` documents node + pnpm as optional dev prerequisites; Homebrew install still requires zero JS tooling.
6. Apache-2.0 `LICENSE-wterm` is present in `Sources/EspalierKit/Web/Resources/` alongside the bundle. `NOTICE-wterm` is present iff upstream ships a NOTICE file.
7. The three files `xterm.min.js`, `xterm.min.css`, `xterm-addon-fit.min.js` are removed from Resources.

## Architectural Notes

### Why Vite over esbuild, webpack, Rollup, tsup

Vite gives us a zero-config React + TypeScript build with one `vite build` invocation. The output is exactly what we need (static HTML/JS/CSS/WASM), it handles the React JSX transform, and it's what `@wterm/react` examples use. esbuild is a lower-level tool; webpack is overkill for a single-page app this small; Rollup is what Vite uses under the hood. No strong runner-up; Vite is the default for React-in-2026.

### Why commit the built bundle rather than build on `swift build`

Espalier's release pipeline (Homebrew tap) distributes a prebuilt Mac app. End users never run `swift build`; they install a binary. Committing the JS bundle keeps the release tarball self-contained with zero new build prerequisites for end users. Developers who touch only Swift are also unaffected — `swift build` alone produces a working app.

The alternative (SwiftPM build-tool plugin that invokes pnpm at build time) would either require node+pnpm at every `swift build`, or would produce a release artifact whose reproducibility depends on the builder's node version. Neither is worth the "never need to remember `build-web.sh`" convenience.

### Why no content-hashed filenames

The Espalier web server is bound to a user-visible port and serves from a specific machine on demand. Browser caches don't meaningfully apply — the whole app reloads on tab open. Cache-busting via content hashes buys nothing here and costs the `WebStaticResources.asset(for:)` map its simplicity. Flat filenames are the simpler tool for this job.

### Why no frontend test framework

Adding Vitest or Jest to a workspace whose entire logic is "WebSocket ↔ useTerminal hook" is weight for nothing. The integration tests on the Swift side exercise the exact contract the client is on the other end of. If a future Phase 3 sub-project adds non-trivial client logic (state reducers, route guards, data-fetching), that's when frontend tests earn their keep.

### What this PR enables for Phase 3

Phase 3's remaining sub-projects reuse:

- **`web-client/` as a React workspace** — routes, views, state management libraries all plug in here.
- **The Vite + pnpm + TypeScript toolchain** — no further setup cost.
- **The `app.js`/`app.css` predictable filename convention** — Vite can emit more chunks without re-designing `WebStaticResources`.
- **The committed-dist + CI-verify pattern** — same rhythm for every future web-UI PR.

What Phase 3 adds on top: TanStack Router (or similar), a data layer for subscribing to server-pushed session/worktree/attention events, a sidebar component, a split-layout component, mobile media queries. None of those requires re-visiting this spec's decisions.
