#!/usr/bin/env -S uv run python3
# /// script
# requires-python = ">=3.11"
# ///
"""Regenerate SPECS.md from `@spec` annotations in Sources/ and Tests/.

Walks every .swift file under Sources/ and Tests/, captures every `@spec
ID: text` marker (whether on a Swift Testing `@Test` / `@Suite`, on a
`/// @spec ID` doc comment over a type / XCTest method, or on a
`@Test(.disabled(...))` inventory entry), validates uniqueness, and
writes SPECS.md grouped by ID prefix and prefix-major.

Section / subsection titles come from `scripts/spec-sections.json` (one-
time output of scripts/_migrate_specs.py).

CI invokes this script with --check to verify the file is current.
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SPECS_MD = REPO_ROOT / "SPECS.md"
SECTIONS_JSON = REPO_ROOT / "scripts" / "spec-sections.json"

# A spec marker may appear inside:
#   1. a `"""..."""` multi-line string literal (Swift Testing displayName)
#   2. a `"..."` single-line string literal (Swift Testing displayName)
#   3. a `///` doc-comment block (any kind: above a type, function, etc.)
#
# We capture all three by first finding `@spec <ID>` anywhere, then
# extracting the surrounding "carrier" (the string literal or the doc-
# comment block) to read the EARS text.

SPEC_TOKEN = re.compile(r"@spec\s+([A-Z]+-[0-9]+(?:\.[0-9]+)?)\s*:?\s*", re.MULTILINE)


@dataclass(frozen=True)
class SpecMarker:
    spec_id: str
    text: str
    file: Path
    line: int
    kind: str  # "test" | "type" | "todo"

    @property
    def prefix(self) -> str:
        return self.spec_id.split("-", 1)[0]

    @property
    def major(self) -> int:
        suffix = self.spec_id.split("-", 1)[1]
        return int(suffix.split(".", 1)[0])

    @property
    def minor(self) -> int | None:
        suffix = self.spec_id.split("-", 1)[1]
        if "." not in suffix:
            return None
        return int(suffix.split(".", 1)[1])

    def sort_key(self) -> tuple[int, int]:
        return (self.major, self.minor if self.minor is not None else -1)


def line_of_offset(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def extract_carrier(text: str, marker_start: int) -> tuple[str, str]:
    # Given the start of a `@spec` token, return (kind, raw_carrier_text).
    # kind ∈ {"triple", "single", "doc"}:
    #   - triple: marker is inside a triple-quoted Swift literal.
    #   - single: marker is inside a normal "…" Swift string literal.
    #   - doc:    marker is on a `///` doc-comment line.
    line_start = text.rfind("\n", 0, marker_start) + 1
    line_text = text[line_start : text.find("\n", marker_start)]

    if line_text.lstrip().startswith("///"):
        # doc-comment carrier
        return "doc", _extract_doc_block(text, marker_start)

    triple_open = text.rfind('"""', 0, marker_start)
    if triple_open != -1:
        triple_close = text.find('"""', triple_open + 3)
        if triple_close != -1 and triple_open < marker_start < triple_close:
            return "triple", text[triple_open + 3 : triple_close]

    single_open = text.rfind('"', 0, marker_start)
    if single_open != -1:
        nl_between = text.find("\n", single_open + 1, marker_start)
        if nl_between == -1:
            single_close = text.find('"', single_open + 1)
            if single_close > marker_start:
                return "single", text[single_open + 1 : single_close]

    raise ValueError(
        f"@spec marker at offset {marker_start} is not inside a recognised "
        "string literal or doc-comment block"
    )


def _extract_doc_block(text: str, marker_start: int) -> str:
    line_start = text.rfind("\n", 0, marker_start) + 1
    lines: list[str] = []
    cursor = line_start
    while cursor < len(text):
        line_end = text.find("\n", cursor)
        if line_end == -1:
            line_end = len(text)
        line = text[cursor:line_end]
        stripped = line.lstrip()
        if not stripped.startswith("///"):
            break
        lines.append(stripped[3:].lstrip())
        cursor = line_end + 1
    return "\n".join(lines)


def parse_carrier_text(kind: str, carrier: str, spec_id: str) -> str:
    """Strip the leading `@spec <ID>:` prefix and any surrounding noise."""
    # The marker may appear after some preamble in the carrier (common
    # for doc comments where the first line could be something like
    # "Implementation note. @spec FOO-1 ..."). Slice from the marker.
    idx = carrier.find(f"@spec {spec_id}")
    if idx == -1:
        raise ValueError(f"@spec {spec_id} not found in carrier")
    body = re.sub(
        r"^@spec\s+[A-Z]+-[0-9]+(?:\.[0-9]+)?\s*:?\s*", "", carrier[idx:]
    )
    body = re.sub(r"\s*\n\s*", " ", body.strip())
    if kind in ("triple", "single"):
        # Reverse the only Swift escape the inventory writer emits:
        # `\\` (two on-disk backslashes) → `\` (one). Doc comments are
        # not Swift string literals, so leave their backslashes alone.
        body = body.replace("\\\\", "\\")
    return body


def kind_of(file: Path) -> str:
    # `*Todo.swift` files under Tests/ are inventory; everything else
    # under Tests/ is a real test; everything under Sources/ is a type
    # annotation.
    if file.name.endswith("Todo.swift"):
        return "todo"
    if "Tests" in file.parts:
        return "test"
    return "type"


def scan_swift_file(file: Path) -> list[SpecMarker]:
    source = file.read_text()
    markers: list[SpecMarker] = []
    for m in SPEC_TOKEN.finditer(source):
        spec_id = m.group(1)
        try:
            carrier_kind, carrier = extract_carrier(source, m.start())
        except ValueError as exc:
            print(
                f"warning: {file.relative_to(REPO_ROOT)}:{line_of_offset(source, m.start())}: {exc}",
                file=sys.stderr,
            )
            continue
        body = parse_carrier_text(carrier_kind, carrier, spec_id)
        markers.append(
            SpecMarker(
                spec_id=spec_id,
                text=body,
                file=file,
                line=line_of_offset(source, m.start()),
                kind=kind_of(file),
            )
        )
    return markers


def collect_markers(roots: list[Path]) -> list[SpecMarker]:
    out: list[SpecMarker] = []
    for root in roots:
        for path in root.rglob("*.swift"):
            out.extend(scan_swift_file(path))
    return out


def validate(markers: list[SpecMarker]) -> list[str]:
    """Return a list of error strings; empty list means valid."""
    errors: list[str] = []

    by_id_kind: dict[tuple[str, str], list[SpecMarker]] = defaultdict(list)
    for m in markers:
        # Treat "test" and "todo" as the same kind for uniqueness
        # purposes — the rule is "one behavioral location per spec".
        bucket = "behavioral" if m.kind in ("test", "todo") else "type"
        by_id_kind[(m.spec_id, bucket)].append(m)
    for (spec_id, bucket), entries in by_id_kind.items():
        if len(entries) > 1:
            locs = ", ".join(
                f"{m.file.relative_to(REPO_ROOT)}:{m.line}" for m in entries
            )
            errors.append(
                f"spec {spec_id} has multiple {bucket} locations (only one allowed): {locs}"
            )

    by_id: dict[str, list[SpecMarker]] = defaultdict(list)
    for m in markers:
        if m.kind in ("test", "todo"):
            by_id[m.spec_id].append(m)
    for spec_id, entries in by_id.items():
        kinds = {m.kind for m in entries}
        if "test" in kinds and "todo" in kinds:
            locs = ", ".join(
                f"{m.file.relative_to(REPO_ROOT)}:{m.line} ({m.kind})"
                for m in entries
            )
            errors.append(
                f"spec {spec_id} is both an active test and a .disabled inventory entry: {locs} "
                "(delete the inventory entry once the real test exists)"
            )

    return errors


def render_specs_md(markers: list[SpecMarker], config: dict) -> str:
    section_titles: dict[str, str] = config.get("sections", {})
    subsection_titles: dict[str, str] = config.get("subsections", {})
    section_order: list[str] = config.get("section_order", [])

    # For each spec ID, prefer the type marker's text if both a test and
    # a type carry the same ID (they should match, but in practice the
    # test title wins for behavior; the type doc is the structural
    # mirror). When only one exists, that one wins.
    by_id: dict[str, SpecMarker] = {}
    for m in markers:
        existing = by_id.get(m.spec_id)
        if existing is None or (
            existing.kind == "type" and m.kind in ("test", "todo")
        ):
            by_id[m.spec_id] = m

    by_prefix: dict[str, list[SpecMarker]] = defaultdict(list)
    for m in by_id.values():
        by_prefix[m.prefix].append(m)

    ordered_prefixes: list[str] = list(section_order)
    for prefix in sorted(by_prefix):
        if prefix not in ordered_prefixes:
            ordered_prefixes.append(prefix)

    parts: list[str] = ["# Graftty — EARS Requirements Specification", ""]
    intro = config.get("intro")
    if intro:
        parts.append(intro)
        parts.append("")

    for prefix in ordered_prefixes:
        if prefix not in by_prefix:
            continue
        section_title = section_titles.get(prefix, prefix)
        parts.append(f"## {prefix} — {section_title}")
        parts.append("")

        major_groups: dict[int, list[SpecMarker]] = defaultdict(list)
        for m in by_prefix[prefix]:
            major_groups[m.major].append(m)
        for major in sorted(major_groups):
            sub_title = subsection_titles.get(f"{prefix}.{major}")
            heading = f"### {prefix}-{major}.x"
            if sub_title:
                heading += f" — {sub_title}"
            parts.append(heading)
            parts.append("")
            for m in sorted(major_groups[major], key=SpecMarker.sort_key):
                parts.append(f"**{m.spec_id}** {m.text}")
                parts.append("")

    return "\n".join(parts).rstrip() + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero if SPECS.md is out of date",
    )
    args = parser.parse_args()

    if not SECTIONS_JSON.exists():
        print(
            f"error: {SECTIONS_JSON.relative_to(REPO_ROOT)} not found; "
            "run scripts/_migrate_specs.py to bootstrap the section map.",
            file=sys.stderr,
        )
        return 2
    config = json.loads(SECTIONS_JSON.read_text())

    markers = collect_markers([REPO_ROOT / "Sources", REPO_ROOT / "Tests"])
    errors = validate(markers)
    if errors:
        for err in errors:
            print(f"error: {err}", file=sys.stderr)
        return 2

    rendered = render_specs_md(markers, config)

    if args.check:
        existing = SPECS_MD.read_text() if SPECS_MD.exists() else ""
        if existing == rendered:
            return 0
        diff = "".join(
            difflib.unified_diff(
                existing.splitlines(keepends=True),
                rendered.splitlines(keepends=True),
                fromfile="SPECS.md (on disk)",
                tofile="SPECS.md (regenerated)",
            )
        )
        sys.stdout.write(diff)
        print(
            "\nerror: SPECS.md is out of date; run scripts/generate-specs.py",
            file=sys.stderr,
        )
        return 1

    SPECS_MD.write_text(rendered)
    print(f"Wrote {SPECS_MD.relative_to(REPO_ROOT)} ({len(markers)} markers)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
