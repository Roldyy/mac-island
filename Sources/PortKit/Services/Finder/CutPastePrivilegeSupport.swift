// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

enum CutPastePrivilegeSupport {
    /// Cancellation can follow a partial move. Only retain items that have not
    /// landed; lack of permission to inspect a source is not proof it moved.
    static func reconcile(_ urls: [URL], into directory: URL, canceled: Bool,
                          fm: FileManager) -> (moved: Int, failed: Int, stillCut: [URL]) {
        let remaining = urls.filter { source in
            do {
                _ = try fm.attributesOfItem(atPath: source.path)
                return true
            } catch {
                let error = error as NSError
                let missing = (error.domain == NSCocoaErrorDomain
                    && error.code == NSFileReadNoSuchFileError)
                    || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT))
                let destination = directory.appendingPathComponent(source.lastPathComponent)
                return !missing || !fm.fileExists(atPath: destination.path)
            }
        }
        return (urls.count - remaining.count, canceled ? 0 : remaining.count,
                canceled ? remaining : [])
    }

    /// Mac Island: items the file system refused for lack of permission are never handed to Finder (which would ask
    /// for an administrator password). They count as failed, nothing moves, and the cut mark is dropped.
    static func leaveInPlace(_ refused: [URL]) -> (moved: Int, failed: Int, stillCut: [URL]) {
        (0, refused.count, [])
    }

    static func needsPrivileges(_ error: Error) -> Bool {
        let error = error as NSError
        var candidates = [error]
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            candidates.append(underlying)
        }
        return candidates.contains(where: isPermissionDenied)
    }

    private static func isPermissionDenied(_ error: NSError) -> Bool {
        switch error.domain {
        case NSCocoaErrorDomain:
            return error.code == NSFileWriteNoPermissionError
                || error.code == NSFileReadNoPermissionError
        case NSPOSIXErrorDomain:
            return error.code == Int(EACCES) || error.code == Int(EPERM)
        default:
            return false
        }
    }
}
