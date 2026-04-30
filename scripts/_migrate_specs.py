#!/usr/bin/env -S uv run python3
# /// script
# requires-python = ">=3.11"
# ///
"""One-time migration: parse the hand-written SPECS.md into:

  1. scripts/spec-sections.json   — section / subsection title metadata
                                    used by scripts/generate-specs.py.
  2. Tests/GrafttyTests/Specs/<Prefix>Todo.swift
                                  — one inventory file per spec-ID prefix,
                                    every spec rendered as
                                    @Test(.disabled("not yet implemented"),
                                          "@spec ID: EARS text").

After running this script, scripts/generate-specs.py can scan for @spec
markers and reproduce SPECS.md from the inventory + any promoted tests.

This script is not part of the normal flow and can be deleted once the
migration is committed.
"""

from __future__ import annotations

import json
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SPECS_MD = REPO_ROOT / "SPECS.md"
SECTIONS_JSON = REPO_ROOT / "scripts" / "spec-sections.json"
TODO_DIR = REPO_ROOT / "Tests" / "GrafttyTests" / "Specs"
ALREADY_PROMOTED = re.compile(r"@spec\s+([A-Z]+-[0-9]+(?:\.[0-9]+)?)")

SPEC_LINE = re.compile(r"^\*\*([A-Z]+-[0-9]+(?:\.[0-9]+)?)\*\*\s+(.*)$")
SECTION_HEAD = re.compile(r"^##\s+([0-9]+[A-Z]?)\.\s+(.+)$")
SUBSECTION_HEAD = re.compile(r"^###\s+([0-9]+[A-Z]?\.[0-9]+)\s+(.+)$")
TOMBSTONED_BODY = re.compile(r"^~~.*~~$")


@dataclass
class Spec:
    spec_id: str
    text: str
    section_id: str
    section_title: str
    subsection_id: str | None
    subsection_title: str | None

    @property
    def prefix(self) -> str:
        return self.spec_id.split("-", 1)[0]

    @property
    def major(self) -> int:
        # LAYOUT-2.13 → 2; LAYOUT-3 → 3.
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


def parse_specs_md(text: str) -> list[Spec]:
    section_id = section_title = ""
    subsection_id = subsection_title = None
    specs: list[Spec] = []

    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if m := SECTION_HEAD.match(line):
            section_id, section_title = m.group(1), m.group(2).strip()
            subsection_id = subsection_title = None
            continue
        if m := SUBSECTION_HEAD.match(line):
            subsection_id, subsection_title = m.group(1), m.group(2).strip()
            continue
        if m := SPEC_LINE.match(line):
            body = m.group(2).strip()
            if TOMBSTONED_BODY.match(body):
                # Author marked the spec as removed by wrapping the
                # entire body in ~~ ~~. The new model has no tombstones —
                # absent annotation == absent spec. Drop it.
                continue
            specs.append(
                Spec(
                    spec_id=m.group(1),
                    text=body,
                    section_id=section_id,
                    section_title=section_title,
                    subsection_id=subsection_id,
                    subsection_title=subsection_title,
                )
            )
    return specs


def derive_section_titles(specs: list[Spec]) -> dict:
    # For each prefix, pick the section title where the prefix's specs
    # are most heavily concentrated. The author's hand-organized SPECS.md
    # places specs by topic — most prefixes map cleanly to one section,
    # but a few (TERM-9.x under "Keyboard Shortcuts", GIT-2.6 under "PR
    # Fetching") drift; we accept that drift and put TERM-9.x under
    # "Terminal Lifecycle" because that's where TERM-* belongs by ID.
    prefix_section_counts: dict[str, dict[str, int]] = defaultdict(
        lambda: defaultdict(int)
    )
    prefix_section_order: dict[str, list[str]] = defaultdict(list)
    for s in specs:
        title = s.section_title
        if title and prefix_section_counts[s.prefix][title] == 0:
            prefix_section_order[s.prefix].append(title)
        prefix_section_counts[s.prefix][title] += 1

    sections: dict[str, str] = {}
    for prefix, counts in prefix_section_counts.items():
        sections[prefix] = max(counts.items(), key=lambda kv: kv[1])[0]

    # Subsections: keyed by (prefix, major). Pick the title most-often
    # used for the prefix-major group; if the original author placed a
    # spec in a different section, we still derive a per-major title
    # from majority vote within that prefix-major group.
    sub_counts: dict[tuple[str, int], dict[str, int]] = defaultdict(
        lambda: defaultdict(int)
    )
    for s in specs:
        if s.subsection_title:
            sub_counts[(s.prefix, s.major)][s.subsection_title] += 1

    subsections: dict[str, str] = {}
    for (prefix, major), counts in sub_counts.items():
        subsections[f"{prefix}.{major}"] = max(
            counts.items(), key=lambda kv: kv[1]
        )[0]

    # Section ordering: preserve the order major sections appeared in
    # SPECS.md so the generated file's prefix order matches the author's
    # mental model (LAYOUT first, then STATE, then TERM, …).
    seen: list[str] = []
    for s in specs:
        if s.prefix not in seen:
            seen.append(s.prefix)

    return {
        "intro": (
            "Requirements for a macOS worktree-aware terminal multiplexer "
            "built on libghostty.\n\nThis file is generated from `@spec` "
            "annotations in `Sources/` and `Tests/`. Do not edit manually — "
            "run `scripts/generate-specs.py` to regenerate."
        ),
        "section_order": seen,
        "sections": sections,
        "subsections": subsections,
    }


def swift_string_literal(text: str) -> str:
    # Always emit a multi-line """...""" literal so embedded quotes,
    # backslashes, and very long lines don't have to be escaped. Swift
    # interprets backslash escapes inside multi-line literals; pre-
    # escape any backslash so they round-trip literally.
    body = text.replace("\\", "\\\\").replace('"""', '\\"\\"\\"')
    return f'"""\n{body}\n"""'


def slug(spec_id: str) -> str:
    # LAYOUT-2.13 → layout_2_13. Used for the (otherwise unused) Swift
    # function name; must be a valid Swift identifier.
    return spec_id.lower().replace("-", "_").replace(".", "_")


def render_inventory_file(prefix: str, specs: list[Spec]) -> str:
    specs_sorted = sorted(specs, key=Spec.sort_key)
    body_parts: list[str] = []
    for s in specs_sorted:
        marker = f"@spec {s.spec_id}: {s.text}"
        body_parts.append(
            f'    @Test({swift_string_literal(marker)}, .disabled("not yet implemented"))\n'
            f"    func {slug(s.spec_id)}() async throws {{ }}\n"
        )

    suite_name = f"{prefix} — pending specs"
    return (
        "// Auto-generated inventory of unimplemented specs in this section.\n"
        "// Promote a @Test(.disabled(...)) entry to a real @Test in a *Tests.swift\n"
        "// file before implementing the behavior, then delete the entry from this\n"
        "// inventory file. SPECS.md is regenerated from these markers by\n"
        "// scripts/generate-specs.py.\n"
        "\n"
        "import Testing\n"
        "\n"
        f'@Suite("{suite_name}")\n'
        f"struct {prefix.capitalize()}Todo {{\n"
        + "\n".join(body_parts)
        + "}\n"
    )


def collect_already_promoted() -> set[str]:
    # IDs that already have a @spec marker outside the *Todo.swift
    # inventory — i.e. promoted to a real test or attached to a type.
    # Re-running the migration must not re-add those to inventory or
    # the generator's "behavior in two places" check will fire.
    promoted: set[str] = set()
    for root in (REPO_ROOT / "Sources", REPO_ROOT / "Tests"):
        if not root.exists():
            continue
        for path in root.rglob("*.swift"):
            if path.parent.name == "Specs" and path.name.endswith("Todo.swift"):
                continue
            for m in ALREADY_PROMOTED.finditer(path.read_text()):
                promoted.add(m.group(1))
    return promoted


def main() -> None:
    text = SPECS_MD.read_text()
    all_specs = parse_specs_md(text)
    print(f"Parsed {len(all_specs)} specs from SPECS.md")

    promoted = collect_already_promoted()
    specs = all_specs
    if promoted:
        specs = [s for s in all_specs if s.spec_id not in promoted]
        print(
            f"Skipping {len(all_specs) - len(specs)} specs already promoted "
            "to real tests / type doc comments outside *Todo.swift."
        )

    seen: dict[str, Spec] = {}
    duplicates: list[tuple[Spec, Spec]] = []
    for s in specs:
        if s.spec_id in seen:
            duplicates.append((seen[s.spec_id], s))
        else:
            seen[s.spec_id] = s
    if duplicates:
        for first, second in duplicates:
            print(f"  duplicate {second.spec_id}: '{first.text[:60]}…' vs '{second.text[:60]}…'")
        raise SystemExit(
            f"SPECS.md has {len(duplicates)} duplicate spec ID(s); resolve by "
            "renumbering one occurrence before re-running."
        )

    # Section titles come from the FULL set of parsed specs (including
    # promoted ones), so a fully-promoted prefix doesn't lose its title
    # in scripts/spec-sections.json.
    config = derive_section_titles(all_specs)

    # Preserve titles from any existing sections.json — once the file
    # has been bootstrapped from the original old-format SPECS.md, later
    # re-runs (against the regenerated new-format SPECS.md) can't re-
    # derive titles from headings the new format doesn't carry. Merge:
    # existing non-empty titles win; new prefixes pick up empty defaults
    # the user can fill in.
    if SECTIONS_JSON.exists():
        existing = json.loads(SECTIONS_JSON.read_text())
        for key in ("sections", "subsections"):
            for prefix, title in existing.get(key, {}).items():
                if title and not config[key].get(prefix):
                    config[key][prefix] = title
    SECTIONS_JSON.parent.mkdir(parents=True, exist_ok=True)
    SECTIONS_JSON.write_text(json.dumps(config, indent=2) + "\n")
    print(f"Wrote {SECTIONS_JSON.relative_to(REPO_ROOT)}")

    by_prefix: dict[str, list[Spec]] = defaultdict(list)
    for s in specs:
        by_prefix[s.prefix].append(s)

    TODO_DIR.mkdir(parents=True, exist_ok=True)
    keep_files: set[Path] = set()
    for prefix, group in sorted(by_prefix.items()):
        out = TODO_DIR / f"{prefix.capitalize()}Todo.swift"
        out.write_text(render_inventory_file(prefix, group))
        keep_files.add(out)

    # Delete inventory files for prefixes that no longer have any
    # un-promoted specs — otherwise stale .disabled entries would
    # collide with real promoted tests on the next generate.
    deleted = 0
    for stale in TODO_DIR.glob("*Todo.swift"):
        if stale not in keep_files:
            stale.unlink()
            deleted += 1
    print(
        f"Wrote {len(by_prefix)} inventory files under "
        f"{TODO_DIR.relative_to(REPO_ROOT)}/"
        + (f"; pruned {deleted} now-empty file(s)" if deleted else "")
    )


if __name__ == "__main__":
    main()
