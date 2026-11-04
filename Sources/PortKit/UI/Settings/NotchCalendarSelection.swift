// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import AppKit
import EventKit
import SwiftUI

/// Per-calendar checkboxes, grouped by account like Calendar.app. Unchecked
/// calendars stay out of the Calendar section and the event countdown.
struct NotchCalendarSelection: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var choices: [NotchCalendarChoice] = []
    @State private var excluded = NotchCalendarSupport.excludedCalendars()

    var body: some View {
        let groups = NotchCalendarSupport.grouped(choices)
        let text = FeatureStrings.notchCalendar(l10n.language)
        let account = CalendarAccountStrings.strings(l10n.language)
        VStack(alignment: .leading, spacing: 6) {
            if !groups.isEmpty {
                Divider()
                Text(text.calendars).font(.subheadline.weight(.medium))
                if CalendarAccountHint.needsGoogleAccount(choices) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(account.googleTitle, systemImage: "person.crop.circle.badge.plus").font(.callout.weight(.medium))
                        Text(account.googleHint).font(.caption).foregroundStyle(.secondary)
                        Button(account.openAccounts) {
                            for url in CalendarAccountHint.settingsURLs where NSWorkspace.shared.open(url) { return }
                        }
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                ForEach(groups, id: \.first?.sourceID) { group in
                    if let first = group.first {
                        accountHeader(first, group, text, account)
                    }
                    ForEach(group) { choice in
                        Toggle(isOn: shown(choice.id)) {
                            HStack(spacing: 6) {
                                Circle().fill(choice.color.color).frame(width: 8, height: 8)
                                Text(choice.title).lineLimit(1)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(choice.title)
                    }
                }
            }
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await reload() }
        }
    }

    /// The account's title with its icon, and Tout / Aucun for its calendars alone.
    private func accountHeader(_ first: NotchCalendarChoice, _ group: [NotchCalendarChoice],
                               _ text: NotchCalendarStrings, _ account: CalendarAccountStrings) -> some View {
        let state = CalendarSelection.accountState(group, excluded: excluded)
        let name = first.source.isEmpty ? text.calendars : first.source
        return HStack(spacing: 6) {
            Label(name, systemImage: first.kind.symbol)
                .font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Button(account.selectAll) { setAccount(group, shown: true) }
                .disabled(state == .all)
                .accessibilityLabel(String(format: account.selectAllLabel, name))
            Button(account.selectNone) { setAccount(group, shown: false) }
                .disabled(state == .none)
                .accessibilityLabel(String(format: account.selectNoneLabel, name))
        }
        .buttonStyle(.link).font(.caption)
        .padding(.top, 4)
    }

    private func setAccount(_ group: [NotchCalendarChoice], shown: Bool) {
        CalendarSelection.store(CalendarSelection.setAccount(group, shown: shown, excluded: excluded))
        excluded = NotchCalendarSupport.excludedCalendars()
        NotchCalendarService.shared.syncWithPreferences()
    }

    private func reload() async {
        choices = await NotchCalendarService.shared.calendarChoices()
        excluded = NotchCalendarSupport.excludedCalendars()
    }

    private func shown(_ identifier: String) -> Binding<Bool> {
        Binding(get: { !excluded.contains(identifier) }, set: { shown in
            NotchCalendarSupport.setCalendar(identifier, shown: shown)
            excluded = NotchCalendarSupport.excludedCalendars()
            NotchCalendarService.shared.syncWithPreferences()
        })
    }
}
