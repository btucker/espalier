#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <patched-ghostty-source> [zig-0.16.0-executable]" >&2
    exit 2
fi

probe_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ghostty_source=$(cd "$1" && pwd)
zig_bin=$(command -v "${2:-zig}")
zig_bin=$(cd "$(dirname "$zig_bin")" && pwd)/$(basename "$zig_bin")
if [[ $("$zig_bin" version) != 0.16.0 ]]; then
    echo "This experiment requires Zig 0.16.0." >&2
    exit 2
fi
if [[ ! -f "$ghostty_source/include/ghostty/vt/snapshot.h" ]]; then
    echo "Snapshot C API missing. Use the Ghostty revision in README.md." >&2
    exit 2
fi

probe_build=$(mktemp -d "${TMPDIR:-/tmp}/graftty-paging-probe.XXXXXX")
echo "Experiment artifacts: $probe_build"
build_args=(
    --cache-dir "$probe_build/zig-local"
    --global-cache-dir "${ZIG_GLOBAL_CACHE_DIR:-$probe_build/zig-global}"
)
(
    cd "$ghostty_source"
    "$zig_bin" build test-lib-vt -Dtest-filter=PageAllocation "${build_args[@]}" --summary failures
    "$zig_bin" build test-lib-vt -Dtest-filter='incremental decode' "${build_args[@]}" --summary failures
    "$zig_bin" build -Demit-lib-vt=true -Demit-exe=false \
        -Demit-macos-app=false -Demit-xcframework=false -Doptimize=ReleaseSafe \
        --prefix "$probe_build" "${build_args[@]}" --summary failures
)
xcrun clang -std=c11 -Wall -Wextra -Werror -DGHOSTTY_STATIC \
    -I "$ghostty_source/include" "$probe_dir/probe.c" \
    "$probe_build/lib/libghostty-vt.a" -lc++ -o "$probe_build/probe"
"$probe_build/probe"
