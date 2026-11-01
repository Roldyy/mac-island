// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Provides the display names used by macOS for built-in alert sounds.
///
/// Apple's `AlertSounds.loctable` renames several of the files shipped in
/// `/System/Library/Sounds`. This table mirrors those names so the sound
/// picker matches macOS rather than exposing the underlying file names.
///
/// Languages not represented by a translated table intentionally use the
/// English names, matching Apple's localization data.
enum AlertSoundStrings {

    // MARK: - Public API

    /// Returns the macOS display name for a sound file.
    ///
    /// Sounds that do not have a renamed display name fall back to their
    /// original file name.
    static func displayName(
        for fileName: String,
        language: AppLanguage
    ) -> String {
        names(for: language)[fileName] ?? fileName
    }

    /// Sorts sound file names by their visible display name.
    ///
    /// Sorting uses the app's selected language rather than the Mac's
    /// current system language. If two display names are identical, the
    /// underlying file names provide a deterministic tie-breaker.
    static func sortedNames(
        _ fileNames: [String],
        language: AppLanguage
    ) -> [String] {
        let locale = Locale(identifier: language.rawValue)
        let table = names(for: language)

        return fileNames.sorted {
            let lhsDisplayName = table[$0] ?? $0
            let rhsDisplayName = table[$1] ?? $1

            let comparison = lhsDisplayName.compare(
                rhsDisplayName,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: locale
            )

            switch comparison {
            case .orderedAscending:
                return true
            case .orderedDescending:
                return false
            case .orderedSame:
                return $0.localizedStandardCompare($1) == .orderedAscending
            }
        }
    }

    // MARK: - Localization

    private static func names(for language: AppLanguage) -> [String: String] {
        switch language {
        case .enUS:
            return english

        default:
            return french

        }
    }

    // MARK: - English

    private static let english: [String: String] = [
        "Basso": "Mezzo",
        "Blow": "Breeze",
        "Bottle": "Pebble",
        "Frog": "Jump",
        "Funk": "Funky",
        "Glass": "Crystal",
        "Hero": "Heroine",
        "Morse": "Pong",
        "Ping": "Sonar",
        "Pop": "Bubble",
        "Purr": "Pluck",
        "Sosumi": "Sonumi",
        "Submarine": "Submerge",
        "Tink": "Boop",
    ]

    // MARK: - French

    private static let french: [String: String] = [
        "Basso": "Mezzo",
        "Blow": "Brise",
        "Bottle": "Galet",
        "Frog": "Saut",
        "Funk": "Funky",
        "Glass": "Cristal",
        "Hero": "Héroïne",
        "Morse": "Pong",
        "Ping": "Sonar",
        "Pop": "Bulle",
        "Purr": "Pincement",
        "Sosumi": "Sonumi",
        "Submarine": "Submersible",
        "Tink": "Boop",
    ]
}
