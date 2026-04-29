// Sources/GrafttyKit/Editor/EditorPreference.swift
import Foundation

/// What the layered lookup returned. The `kind` says what to do; the
/// `source` is captured so the Settings UI can display the resolution
/// chain ("currently using $EDITOR from shell: nvim") and tests can
/// assert which branch fired.
public struct ResolvedEditor: Equatable {
    public enum Kind: Equatable {
        case app(bundleURL: URL)
        case cli(command: String)
    }

    public enum Source: Equatable {
        case userPreference
        case shellEnv
        case defaultFallback
    }

    public let kind: Kind
    public let source: Source

    public init(kind: Kind, source: Source) {
        self.kind = kind
        self.source = source
    }
}
