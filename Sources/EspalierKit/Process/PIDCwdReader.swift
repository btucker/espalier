import Foundation
import Darwin

/// Read another process's current working directory via macOS's
/// `proc_pidinfo(PROC_PIDVNODEPATHINFO)`. Used by `PWD-1.3` as a
/// shell-independent fallback to OSC 7 — survives zmx sessions
/// whose inner shell has no Ghostty shell integration loaded, and
/// also covers users on bash/fish whose chpwd hook we never
/// installed in the first place.
public enum PIDCwdReader {

    /// Return the cwd of `pid` as an absolute path string, or nil
    /// if the process doesn't exist, the caller can't see it
    /// (permission), or the kernel call fails for any other reason.
    ///
    /// Path length is capped at `MAXPATHLEN` by the kernel struct —
    /// paths that long are already unusable for terminal workflows
    /// so the truncation isn't a concern in practice.
    public static func cwd(ofPID pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let rc = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, ptr, size)
        }
        guard rc == size else { return nil }

        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cStr in
                // The kernel writes a NUL-terminated path; String(cString:)
                // stops at the terminator. An empty string means the cdir
                // inode has no usable path (e.g., deleted directory); treat
                // it as unknown.
                let value = String(cString: cStr)
                return value.isEmpty ? nil : value
            }
        }
    }
}
