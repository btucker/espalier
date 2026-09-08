# Ghostty paging experiment results

These results cover the terminal core and isolated AppKit and UIKit surfaces.
See [the reproduction instructions](README.md) to run the experiment. Neither
Graftty app has paging enabled.

## What the probe verifies

For 1,000, 10,000, and 100,000 uniquely numbered short lines, the probe:

- Restores through READY and checks that unread history remains.
- Resumes an unfinished SGR sequence, then sends 100 live rows before fetching
  any history. The snapshot read offset must remain unchanged.
- Imports one history page and checks that the viewport still follows live output.
- Scrolls to the oldest loaded row, selects its text, and sends another 100 live rows.
- Imports the remaining pages and refreshes Ghostty's render-state cache.
- Checks that selection and visible content still name the same row.
- Checks every original and live row exactly once, in order, with no extra content.
- Loads primary-screen history while the alternate screen is active, then
  checks the primary content after returning.

The C probe also records the legacy decoder's discard behavior. After an
80-to-40-column resize, every pending page returns success with zero applied
rows. Loaded rows remain, and the terminal can still process output. The native
bridge now uses a separate checked entry point, described below. Neither test
implements the checkpoint recovery required by TERM-12.6.

The fixture disables both scrollback retention limits so that all test rows fit.
These settings are for the test only, not proposed client memory budgets.

## Observed results

On September 5, 2026, the patched ReleaseSafe core produced these results:

| Original rows | Full snapshot bytes | Bytes through READY | History pages |
| --- | ---: | ---: | ---: |
| 1,000 | 14,126 | 6,383 | 1 |
| 10,000 | 131,636 | 8,138 | 16 |
| 100,000 | 1,306,838 | 2,639 | 169 |

READY includes the backing page that intersects the active screen, so its
resident history overlap varies. These byte counts come from one simple fixture,
not a bound for arbitrary terminal contents. The 100,000-line run verified all
100,200 original and live rows after import.

The full Debug `zig build test-lib-vt --summary failures` suite also passed
on the pinned source with only `preserve-top-anchor.patch` applied. The focused
regression failed before the fix and passed afterward.

The probe prints elapsed times for full snapshot encoding and READY decoding.
It does not measure network latency or app opening time. It encodes the full
snapshot first, so it does not demonstrate bounded initial host work.

## The patch preserves content at the top

Ghostty represents a viewport at the oldest row with a special `top` marker.
That marker follows the first page in the list. Prepending a page therefore
moves the reader to different content, even though ordinary pinned reading
positions and selections already survive prepends.

`preserve-top-anchor.patch` changes `PageAllocation.prepend` to convert `top`
into a tracked content pin before inserting the page. It does so after all
fallible validation. Rejected pages leave the viewport unchanged. A viewport
following the active screen keeps following live output.

The patch includes a regression test for repeated prepends and the cached
scrollbar offset. It applies to Ghostty revision
`8af6897c0afc63037a8a3efee4162a380e3a4572` only. No dependency pin has changed.

## Native-surface experiment

On September 6, 2026, Xcode Metal Toolchain 17F109 was installed. The newer
renderer then built for macOS and the arm64 iOS Simulator. The UIKit test ran on
an iPhone 17 Pro simulator with iOS 26.5.

`surface-probe.m` uses the same test body on both platforms. It creates real
host-managed Ghostty surfaces backed by an `NSView` or `UIView`, calls their draw
API, and checks their text through the surface C API. Six scenarios passed:

- Restore READY, apply live output, select loaded content, and scroll to its
  oldest row. Import all 169 older pages, then verify the same selection and
  visible row. Verify every original row once, in order, followed by live output.
- Switch to the alternate screen while primary history loads. Return to the
  primary screen and verify all 100,000 original rows and live output.
- Resize from 80 to 40 columns while history is pending. Require recovery
  before consuming a page, keep loaded content, and accept more output.
- Resize from 80 to 40 columns and back to 80 before the next page request.
  Require recovery even though the current width matches the snapshot again.
- Import one page, select loaded content, and scroll to its oldest row before
  resizing. Preserve selection, the visible row, and all remaining page records.
- Change only the terminal height, then import and verify all 100,000 rows.
  After completion, change the width and verify that history stays complete.

Each scenario also rejects a truncated READY and a second snapshot installation,
checks repeated page status calls, and destroys its surface and app. The test waits
for the actual terminal grid and scroll position, because surface resize and
scroll actions can be queued to the I/O thread.

These checks exercise drawing and surface readback. They do not compare rendered
pixels, simulate selection gestures, rotate a physical device, test memory
pressure, or verify Graftty's Swift wrapper lifecycle.

## Resize invalidation stops before a pending page

The original decoder compares the current width with the width at READY. The
added regression reproduced acceptance of old pages after resizing away from
the original width and back. `resize-history-guard.patch` adds a terminal-local
reflow generation so that the original decoder discards those pages too. The
generation changes before a width resize can mutate rows, including a resize
that later fails during allocation. It is not serialized in the snapshot.

The same patch adds `Decoder.nextAtOriginalWidth`. A changed width or reflow
generation returns `HistoryRequiresRecovery` before consuming a PAGE or changing
the loaded terminal. The bridge exposes this condition as status 2, distinct
from a consumed page, completion, and decoder failure. Repeated calls leave the
pending PAGE unchanged. The caller can still explicitly discard and validate
the old records through the original decoder.

The checked decoder may first consume HISTORY metadata. Each manifest is a
10-byte record header and a 6-byte payload. This lets an empty history finish
normally after resize. The tests check that metadata is consumed only once and
that no incompatible PAGE bytes are consumed. Height-only changes and repeated
requests for the same grid do not invalidate history.

The focused regressions cover widening, narrowing, a width round trip, partial
import, empty history, and completion before FINISH is read. The round-trip and
empty-history tests failed before their fixes and passed afterward. The native
resize assertion also failed against the previous bridge after its first two
non-resize scenarios passed.

On September 6, 2026, the full Debug `zig build test-lib-vt --summary failures`
suite passed with all four experimental patches applied. The ReleaseSafe C probe
also passed at 1,000, 10,000, and 100,000 rows. A fresh source tree with the saved
patches matched the tested source, excluding generated build and package files.

This guard does not recover older history. A production caller still needs a
compatible checkpoint or a reflow-aware importer. It must keep recovery pending
distinct from a fully loaded history and preserve the reader's current content.

## Experimental bridge limits

The shipped renderer uses Ghostty `35e1a0160c4f6797e1bb1ef8e7a2b8c6b114ab58`,
which has no snapshot implementation. Its host-managed I/O patches do not apply
unchanged to zmx's newer Ghostty revision.

`renderer-experiment.patch` ports the host-managed backend, installs the Darwin
static archive, and adds private `graftty_probe_surface_*` test entry points.
They are absent from the public header and are not a proposed production ABI.

The test bridge has these restrictions:

- One installation into a fresh host-managed surface, on the main thread, at
  the snapshot's grid size. Existing search and inspector sessions are rejected.
- A complete trusted snapshot fixture is copied into memory, capped at 8 MiB.
  READY decoding occurs before taking the renderer lock. Each later page is
  decoded from resident bytes under that lock. No network reader is involved.
- The restored terminal replaces the fresh terminal at its existing address.
  A new surface stream handler restores the parser continuation, and terminal
  dirty flags force the renderer to refresh its cached rows.
- Page status distinguishes resize recovery from successful consumption and
  completion. Other discard causes still report a consumed page with zero rows.
  The experiment does not recover that history.
- The fixture's unlimited history budgets and colors are imported. Production
  retention limits, user-theme policy, and untrusted-input hardening remain open.

`ios-renderer-experiment.patch` restores the removed iOS build configuration and
ports Graftty's CoreText and Metal platform patches to the newer revision.
Both native tests use the same snapshot bridge and codec. These artifacts are
not packaged into the shipped XCFramework, and the Swift wrappers still use
their existing dependency revision.

Production integration still requires a supported dependency build, Swift
wrapper integration, retained-surface replacement and cancellation, resize
recovery, demand-driven host export, and the shared attachment protocol. A
smaller READY prefix alone does not remove full snapshot encoding or transport
costs. TERM-12 remains pending.
