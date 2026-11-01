// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import SwiftUI

/// The one feature the foundation binds to prove the path end to end: the URL cleaner.
///
/// Why this one: it needs no permission (no tap, no Accessibility), it only rewrites a link someone copied
/// while its own switch is on, its service has a real `stop()` (timer and in-flight read), and it has a
/// complete ported Settings page (`URLCleanerSettings`) that reads no other service. It is off by default (the
/// descriptor is never on by default, and the service also waits for its own page toggle), so binding it
/// changes nothing for a user who does not open the page.
enum FoundationExampleLane {
    @MainActor static func bind(into binding: PortFeatureBinding) {
        binding.bind(
            .urlCleaner,
            page: PortFeaturePage(pageID: "urlcleaner") { AnyView(URLCleanerSettings()) },
            start: { URLCleanerService.shared.syncWithPreferences() },
            stop: { URLCleanerService.shared.stop() })
    }
}
