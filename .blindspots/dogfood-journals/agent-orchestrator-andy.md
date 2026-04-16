# Agent-Orchestrator Andy — Dogfood Journal

## Cycle 1 — 2026-04-16

### Explored
- Tried to take screenshots of the Espalier macOS app via `mcp__computer-use__*`. Access was denied with reason `not_installed` — Espalier is a raw SPM executable, not a proper `.app` bundle, so the system doesn't recognize it as an installed application. Filed mentally; tested the CLI instead.
- Tested `.build/arm64-apple-macosx/debug/espalier --help` — hung, produced no output, linked against AppKit/SwiftUI/Metal (not appropriate for a CLI).

### Broke
- **Build system bug:** `swift build` produces two executable products named `Espalier` and `espalier`. On macOS's default case-insensitive APFS, these collide at the same filesystem path. The second link step overwrites the first, so both `espalier` and `Espalier` end up as the same file (same inode, same hash, 10.2MB each). Running `espalier notify` actually launches the SwiftUI app, which explains the hang.
- Evidence: `md5 -r` and `stat -f "%i"` on both binaries returned identical values.

### Fixed
- Renamed the SPM product from `espalier` → `espalier-cli` in `Package.swift`. The target name (`EspalierCLI`) is unchanged. ATTN-1.1 is preserved because it only specifies what the binary is called **when installed into the app bundle** (`Espalier.app/Contents/MacOS/espalier`); app bundling renames the binary during install.
- Updated SPECS.md ATTN-1.1 to document this build-system constraint.

### Verified
- `swift build`: two distinct binaries, `Espalier` 10.2MB and `espalier-cli` 2.9MB, different inodes, different hashes.
- `espalier-cli --help`: prints help in <100ms.
- `espalier-cli notify "hello"` from `/tmp`: errors with "Not inside a tracked worktree", exits 1, in 11ms (previously hung indefinitely).
- `swift test --test-product EspalierPackageTests`: 36/36 tests still pass.

## Cycle 2 — 2026-04-16

### Explored
- Verified the CLI linkage concern from Cycle 1: post-rename, `otool -L .build/.../espalier-cli` shows zero GUI frameworks. Old observation was from the clobbered binary. No action needed.
- Worked on producing a proper `.app` bundle so `computer-use` would recognize Espalier as installed.

### Broke
- **Bundle location bug:** my initial `scripts/bundle.sh` copied the app binary to `Contents/MacOS/Espalier` AND the CLI to `Contents/MacOS/espalier`. On case-insensitive APFS the CLI overwrote the app — after bundling, the "app" binary was actually the 2.9MB CLI. Same case-collision bug as cycle 1, reproduced inside the bundle.
- Evidence: `ls -la .build/Espalier.app/Contents/MacOS/` showed only one file `Espalier` at 2.9MB (should be 10.2MB).

### Fixed
- Changed `scripts/bundle.sh` to put the CLI at `Contents/Helpers/espalier` instead of `Contents/MacOS/espalier`. Only the main app binary goes in `MacOS/` (matches macOS bundle convention — helpers conventionally go elsewhere).
- Updated SPECS.md ATTN-1.1 to specify `Contents/Helpers/espalier` with a written explanation of why.
- Updated `EspalierApp.swift:installCLI()` which had a hardcoded `Contents/MacOS/espalier` path → now points at `Contents/Helpers/espalier`.
- Wrote `scripts/bundle.sh` from scratch — builds via `swift build`, copies binaries into a proper `.app` bundle at `.build/Espalier.app/`, writes a valid Info.plist (passes `plutil -lint`).

### Verified
- `./scripts/bundle.sh` produces a bundle with correct sizes: `Contents/MacOS/Espalier` = 10.2MB (app), `Contents/Helpers/espalier` = 2.9MB (CLI). No collision.
- `open .build/Espalier.app` launches the app process.
- `.build/Espalier.app/Contents/Helpers/espalier notify "test"` from the worktree: 15ms, correct error "Espalier is not running", exit 1.
- `plutil -lint` on the Info.plist: OK.
- `swift test --test-product EspalierPackageTests`: 36/36 pass.

### Still blocked
- `mcp__computer-use__request_access` still returns `not_installed` even after:
  - registering the bundle via `lsregister -f`
  - copying the bundle to `~/Applications/`
  - registering that copy
- Hypothesis: the MCP tool's "installed" check likely requires a code-signed app or placement in `/Applications/` (system-owned path, requires admin). This is an environmental/signing concern, not a code fix.

### Try next cycle
- End-to-end socket test: launch the bundled app, then run `espalier notify` from a real git worktree (e.g., this one), verify the attention badge appears in the sidebar.
- The `Install CLI Tool...` menu — does `installCLI()` actually work when invoked? It writes to `/usr/local/bin/espalier` which needs admin. Test error path.
- Test what happens if `~/Library/Application Support/Espalier/espalier.sock` exists as a stale file (leftover from a crashed app).
- Persistence: launch app, add a repo, kill -9, relaunch. Does state.json get written at all given we never got far enough to trigger `onChange(of: appState)`?
