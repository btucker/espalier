# Espalier

A macOS worktree-aware terminal multiplexer built on libghostty. Organizes
persistent terminal sessions by git worktree, with a sidebar UI, per-pane
`zmx` session persistence, and a CLI for attention signals from running
processes.

## Install

### Homebrew (recommended)

```sh
brew tap btucker/espalier
brew install --cask espalier
```

This installs `Espalier.app` to `/Applications` and symlinks the `espalier`
CLI onto your `PATH`.

**First launch:** Espalier is currently ad-hoc signed (not notarized), so
macOS will block it with a Gatekeeper warning. To approve it:

1. Try to open Espalier from `/Applications` (it will fail).
2. Open System Settings → Privacy & Security.
3. Scroll to the "Security" section and click "Open Anyway" next to the
   Espalier message.
4. Confirm in the dialog that appears.

On macOS 14 Sonoma you can alternatively right-click Espalier in Applications
and choose "Open".

### Build from source

Requires macOS 14+ and a Swift 5.10 toolchain (Xcode 15.3+ or equivalent).

```sh
git clone https://github.com/btucker/espalier.git
cd espalier
scripts/bundle.sh          # produces .build/Espalier.app
open .build/Espalier.app
```

Pass `ESPALIER_VERSION=x.y.z` to stamp a specific version into the bundle;
otherwise it defaults to `0.0.0-dev`.

## Uninstall

```sh
brew uninstall --cask --zap espalier
```

`--zap` also removes `~/Library/Application Support/Espalier`, the
preferences plist, and the cache directory.

## Documentation

- `SPECS.md` — authoritative requirements (EARS-style)
- `docs/release/README.md` — release process and Homebrew tap setup
- `docs/superpowers/specs/` — design documents per feature
- `docs/superpowers/plans/` — implementation plans per feature
