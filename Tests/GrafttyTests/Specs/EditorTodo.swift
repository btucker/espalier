// Auto-generated inventory of unimplemented specs in this section.
// Promote a @Test(.disabled(...)) entry to a real @Test in a *Tests.swift
// file before implementing the behavior, then delete the entry from this
// inventory file. SPECS.md is regenerated from these markers by
// scripts/generate-specs.py.

import Testing

@Suite("EDITOR — pending specs")
struct EditorTodo {
    @Test("""
@spec EDITOR-1.1: When the user cmd-clicks a file path in a terminal pane, the application shall open the file via the configured editor.
""", .disabled("not yet implemented"))
    func editor_1_1() async throws { }

    @Test("""
@spec EDITOR-1.2: If the configured editor is a known CLI editor, the application shall split the source pane to the right and run the editor in the new pane.
""", .disabled("not yet implemented"))
    func editor_1_2() async throws { }

    @Test("""
@spec EDITOR-1.3: If the configured editor is a GUI app, the application shall dispatch the file to the app via NSWorkspace, without creating a new pane.
""", .disabled("not yet implemented"))
    func editor_1_3() async throws { }

    @Test("""
@spec EDITOR-1.4: If the cmd-clicked target carries a `:line(:col)` suffix, the application shall strip the suffix before resolving the path, and shall pass the line number to known CLI editors using `+<line>`.
""", .disabled("not yet implemented"))
    func editor_1_4() async throws { }

    @Test("""
@spec EDITOR-1.5: If the cmd-clicked target is not a file path, the application shall open it via NSWorkspace (preserving existing handling for `http(s)`, `mailto:`, `ssh:`, and other URL schemes).
""", .disabled("not yet implemented"))
    func editor_1_5() async throws { }

    @Test("""
@spec EDITOR-1.6: If the cmd-clicked target resolves to a path that does not exist on disk, the application shall emit a system beep and not open anything.
""", .disabled("not yet implemented"))
    func editor_1_6() async throws { }

    @Test("""
@spec EDITOR-1.7: When no editor is explicitly configured in Settings, the application shall use the value of `$EDITOR` as defined by the user's login shell.
""", .disabled("not yet implemented"))
    func editor_1_7() async throws { }

    @Test("""
@spec EDITOR-1.8: If `$EDITOR` is unset, the application shall fall back to `vi`.
""", .disabled("not yet implemented"))
    func editor_1_8() async throws { }
}
