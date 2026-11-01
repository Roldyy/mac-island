// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit
import Foundation

// The upload services of Vorssaint talked to a Vorssaint server. These keep the same names so the screenshot
// and recorder code compiles, but nothing is ever sent: `isAvailable` is false and every call fails at once.

enum ScreenshotShareError: Error {
    case invalidImage
    case invalidEndpoint
    case unavailable
    case rejected
    case invalidResponse
    case localStorage
}

enum RecordingShareError: Error {
    case invalidArtifact
    case invalidEndpoint
    case unavailable
    case rejected
    case invalidResponse
    case localStorage
}

@MainActor
final class ScreenshotShareService: ObservableObject {
    static let shared = ScreenshotShareService()
    static let isAvailable = false

    @Published private(set) var records: [ScreenshotShareRecord] = []

    private init() {}

    func refresh(now: Date = Date()) {}

    func createLink(pngData: Data, duration: ScreenshotShareDuration) async throws -> ScreenshotShareRecord {
        throw ScreenshotShareError.unavailable
    }

    func delete(_ record: ScreenshotShareRecord) async throws {
        throw ScreenshotShareError.unavailable
    }

    @discardableResult
    func copy(_ url: URL) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(url.absoluteString, forType: .string)
    }
}

@MainActor
final class RecordingShareService: ObservableObject {
    static let shared = RecordingShareService()
    static let isAvailable = false

    @Published private(set) var records: [RecordingShareRecord] = []

    private init() {}

    func refresh(now: Date = Date()) {}

    func createLink(artifact: RecorderExporter.ShareArtifact,
                    duration: RecordingShareDuration) async throws -> RecordingShareRecord {
        artifact.discard()
        throw RecordingShareError.unavailable
    }

    func delete(_ record: RecordingShareRecord) async throws {
        throw RecordingShareError.unavailable
    }

    @discardableResult
    func copy(_ url: URL) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(url.absoluteString, forType: .string)
    }
}
