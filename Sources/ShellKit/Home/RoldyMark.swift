// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import AppKit
import SwiftUI

/// The small Roldy Management mark in a corner of the island home: white wordmark and blue square on transparent,
/// drawn from an embedded PNG (a SwiftPM target without resources has no bundle to load one from).
struct RoldyMark: View {
    private static let base64 =
        "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" +
        "CziO0vmCqcpmzIf8VwKDcMI7H1HEvIOIfjWq04rwliedwwgHwC01mEMWaGf3Mv3u6/Q9AN8LooyROQkZJAFky6yF7P7OHwOoM2sr4bsWQIOnc0" +
        "g59mgLTiGak4koqezIHLDt3N0oJUWaP2PmlwB4DYA3AjgNwEvhFEEq15zxNzh1S/oApIho16iuGzNBzO68jcDp4UjzyG4rAPxhHNl0////ANzt" +
        "s41YuXXUH1OmMgHg1wD2ARggor+N0f7Ke0Oy54GZBnBCVO/2yS0Pz70a1sTr17OxBVuALevltO+TDKzaBKO3DTZAPF82FOZx7zjhVvQbVft5KY" +
        "BjAZyg/lyLQ01qadRmHYEThWEB2A7gOQBPEVF2dAusGTBlaMy+XJme/pl6rbGQI/cm7+Dhl8RlUN5jD+EhKJPEDG6qF+YyqHcrTZnmwkb1k0o/" +
        "m5r0RLIZkPwHsTdfKKK0UCIxAtrLvNAPKK1Bz55wYgxnp5xC1ueC26waGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGh" +
        "oaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoa" +
        "GhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaCw/U3t5urF+/HgAkEfF0P6C9vd0AgNbWVr" +
        "vSg3XHumnTJm5ra5OVfBczCwA01Xnx/DwTUaXHRgDEli1b0NraKgHwTAqNej9t2QICtgBYD2AL1q9fX5YMTXU9Dr1vcgQ5L35lvBJ7hJlpyxaI" +
        "qc3HeqxfH5xcjpI/e2pj3SIABCIj3vdPFTPFG3MKaqL09/wHWu9kMmlO8jPGxo0bhZ6tfwzota4szGSy//R4vLqGSG5fsWJFDgCmqDESEfF996" +
        "US1dURM5sdfvDcc8/NuH9fGXLob1q8eHH4+eefebylpWVvJd7lfmZXV9+rly078vC9e//4CyIa2rhxoxjr9HV/PpncdlJj46Il+/cfONjcfNZu" +
        "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" +
        "A6If1/LuTS0fH5rdEAAAAASUVORK5CYII="

    static let image: NSImage? = Data(base64Encoded: base64).flatMap(NSImage.init(data:))

    /// Width in points; the home corner uses the default, the credit cards a larger one.
    var width: CGFloat = 58
    var opacity: Double = 0.85

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: width)
                .opacity(opacity)
                .accessibilityLabel("Roldy Management")
                .allowsHitTesting(false)
        }
    }
}
