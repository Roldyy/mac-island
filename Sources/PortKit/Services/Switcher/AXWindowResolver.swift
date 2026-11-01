// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import ApplicationServices
import CoreGraphics

/// Resolves an Accessibility window element to its WindowServer id. Exported by
/// ApplicationServices and used by macOS window switchers; there is no public
/// alternative for this mapping. Looked up at runtime, so a macOS that drops the
/// symbol answers nil instead of failing to launch or crashing at the first call.
enum AXWindowResolver {
    private typealias GetWindowFunction =
        @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow: GetWindowFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */,
                                 "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindowFunction.self)
    }()

    /// Whether this macOS still exports the symbol.
    static var isAvailable: Bool { getWindow != nil }

    static func windowID(for element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        guard getWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }
}
