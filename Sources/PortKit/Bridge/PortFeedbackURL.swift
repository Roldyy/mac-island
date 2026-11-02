// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import Foundation

/// Mac Island has no feedback window: "Report a bug" and "Suggest a feature" (quick panel, Command Bar, General page)
/// open the project's issue form in the browser.
public enum PortFeedbackURL {
    public static let issues = "https://github.com/Roldyy/mac-island/issues/new"

    /// `"bug"` and `"feature"` are the two `FeedbackKind` raw values; anything else opens the plain form.
    public static func url(kind: String) -> URL {
        let label: String
        switch kind {
        case "bug": label = "bug"
        case "feature": label = "enhancement"
        default: return URL(string: issues)!
        }
        return URL(string: issues + "?labels=" + label)!
    }
}
