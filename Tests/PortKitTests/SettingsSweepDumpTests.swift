// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Roldy Management

import AppKit
import Foundation
import IslandKit
import IslandTestSupport
import SwiftUI
import Testing
@testable import PortKit
@testable import ShellKit

/// Parity sweep helper: renders each Settings page the way the app wires it (every lane bound, every ported body
/// registered, the registry holding every descriptor), writes a PNG and a flat text dump of its accessibility tree.
/// `MIS_SWEEP_PAGES` (comma list of page ids) picks the pages; `MIS_SWEEP_DIR` the output folder. Without the
/// folder the test does nothing, so a normal run stays quick.
@MainActor
@Suite(.serialized) struct SettingsSweepDumpTests {
    @Test func dumpPages() throws {
        guard let dir = ProcessInfo.processInfo.environment["MIS_SWEEP_DIR"] else { return }
        let ids = (ProcessInfo.processInfo.environment["MIS_SWEEP_PAGES"] ?? "").split(separator: ",").map(String.init)
        try PortHostFixture.isolated { defaults in
            PortBridge.configure(defaults: defaults)
            PortBridge.bindLanes()
            let ported = PortFeatureBinding.shared
            let marker = CrashMarker(url: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("mis-sweep-marker-\(UUID().uuidString)"))
            let registry = FeatureRegistry(descriptors: ShellDescriptors.all + ported.descriptors, defaults: defaults,
                                           crashMarker: marker, withdraw: { _ in })
            PortBridge.registerDefaults()
            SettingsPageBodies.removeAll()
            for pageID in PortBridge.registeredPageIDs {
                SettingsPageBodies.register(pageID: pageID) { PortBridge.settingsBody(pageID: pageID) ?? AnyView(EmptyView()) }
            }
            for page in ported.pages {
                SettingsPageBodies.register(pageID: page.pageID, featureID: page.featureID, registry: registry,
                                            openPermission: { _ in }, page.body)
            }
            SettingsPageBodies.registerComposed(pageID: "island") {
                AnyView(IslandLayoutSettings(home: HomeModel(defaults: defaults), openIsland: {},
                                             extras: { AnyView(PortIslandExtrasSettings()) }))
            }
            let env = SettingsEnvironment(
                registry: registry, defaults: defaults, sheetTabs: [:], openPermission: { _ in }, relaunch: nil,
                login: LoginItemModel(defaults: defaults),
                backup: SettingsBackup(defaults: defaults, domain: "sweep",
                                       directory: URL(fileURLWithPath: NSTemporaryDirectory())))
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var planned: [String] = []
            for id in ids {
                guard let page = SettingsPageCatalog.page(id) else { continue }
                let rows = SettingsPageModel.blocks(for: page).flatMap(\.rows)
                let bad = rows.filter { !$0.isLive && $0.item.kind != .caption && $0.item.kind != .heading }
                planned.append("\(id) body=\(SettingsPageBodies.hasBody(for: id)) soon=\(page.isComingSoon) live=\(rows.filter(\.isLive).count) planned=\(bad.count) \(bad.map(\.item.label))")
            }
            try planned.joined(separator: "\n").write(toFile: "\(dir)/planned.txt", atomically: true, encoding: .utf8)
            for id in ids {
                let view = SettingsPageView(pageID: id, env: env)
                    .frame(width: 760, height: 3000)
                    .background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: 760, height: 3000)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: .darkAqua)
                window.contentView = host
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
                host.layoutSubtreeIfNeeded()
                var lines: [String] = []
                Self.walk(host, depth: 0, into: &lines)
                try lines.joined(separator: "\n").write(toFile: "\(dir)/\(id).txt", atomically: true, encoding: .utf8)
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(id).png"))
                }
            }
        }
    }


    @Test func listUnboundFeatures() throws {
        guard let dir = ProcessInfo.processInfo.environment["MIS_SWEEP_DIR"] else { return }
        try PortHostFixture.isolated { defaults in
            PortBridge.configure(defaults: defaults)
            PortBridge.bindLanes()
            let starters = Set(PortFeatureBinding.shared.starters.keys)
            let ours = Set(ShellDescriptors.all.map(\.id))
            var out: [String] = []
            for f in AppFeature.allCases where !starters.contains(f.registryID) {
                out.append("\(f.rawValue) -> \(f.registryID) ours=\(ours.contains(f.registryID))")
            }
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try out.joined(separator: "\n").write(toFile: "\(dir)/unbound.txt", atomically: true, encoding: .utf8)
        }
    }

    private static func walk(_ element: Any, depth: Int, into lines: inout [String]) {
        guard depth < 40, let object = element as? NSObject else { return }
        let role = (object.value(forKey: "accessibilityRole") as? String) ?? ""
        var parts: [String] = []
        for key in ["accessibilityTitle", "accessibilityLabel", "accessibilityValue", "accessibilityHelp"] {
            if let text = object.value(forKey: key) { parts.append("\(text)") }
        }
        let text = parts.filter { !$0.isEmpty }.joined(separator: " | ")
        if !role.isEmpty || !text.isEmpty {
            lines.append(String(repeating: " ", count: depth) + role.replacingOccurrences(of: "AX", with: "") + ": " + text)
        }
        if let children = (object as? NSAccessibilityProtocol)?.accessibilityChildren() {
            for child in children { walk(child, depth: depth + 1, into: &lines) }
        } else if let view = object as? NSView {
            for sub in view.subviews { walk(sub, depth: depth + 1, into: &lines) }
        }
    }
}
