import Foundation

/// One row of a declarative page: what was noted from the reference page, and the real control if one exists.
public struct SettingsRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let item: SettingsItem
    public let control: LiveControl?

    /// A row is live only when a control with a real preference key backs it.
    public var isLive: Bool { control != nil }
    /// Rows that are not live are shown greyed and carry the "Bientôt" badge.
    public var isEnabled: Bool { isLive }
}

public struct SettingsBlock: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let rows: [SettingsRow]
}

/// Builds what a declarative page shows. Pure: no view, no defaults.
public enum SettingsPageModel {
    public static func blocks(for page: SettingsPage) -> [SettingsBlock] {
        let all = blocks(pageID: page.id, pageTitle: page.featureID == nil ? nil : page.title,
                         items: SettingsPageContent.items(for: page.id), live: SettingsLive.controls(for: page.id))
        // A registered body owns the whole page: the noted rows were placeholders for it, so none stays behind as
        // a greyed "Bientôt" row. The rows that really work (a live control) stay above the body.
        return SettingsPageBodies.hasBody(for: page.id) ? keepingLiveRows(all) : all
    }

    /// The blocks reduced to their live rows; a block left empty goes away.
    static func keepingLiveRows(_ blocks: [SettingsBlock]) -> [SettingsBlock] {
        blocks.compactMap { block in
            let live = block.rows.filter(\.isLive)
            return live.isEmpty ? nil : SettingsBlock(id: block.id, title: block.title, rows: live)
        }
    }

    static func blocks(pageID: String, pageTitle: String? = nil, items: [SettingsItem], live: SettingsLive.Page?) -> [SettingsBlock] {
        var result: [SettingsBlock] = []
        var used = Set<String>()
        // Controls with no row in the reference page come first.
        if let extras = live?.extras, !extras.isEmpty {
            let rows = extras.map { control in
                SettingsRow(id: "\(pageID).extra.\(control.key)", item: item(for: control), control: control)
            }
            result.append(SettingsBlock(id: "\(pageID).extras", title: "", rows: rows))
        }
        for (index, block) in SettingsItem.blocks(items).enumerated() {
            var rows: [SettingsRow] = []
            for (n, item) in block.items.enumerated() {
                // A caption never gets a control; two rows with one label share the first control only.
                var control: LiveControl?
                if item.kind != .caption, item.kind != .heading, !used.contains(item.label) {
                    control = live?.bound[item.label]
                    if control != nil { used.insert(item.label) }
                }
                rows.append(SettingsRow(id: "\(pageID).\(index).\(n).\(item.label)", item: item, control: control))
            }
            result.append(SettingsBlock(id: "\(pageID).\(index)", title: block.title, rows: tidy(rows, pageTitle: pageTitle)))
        }
        return result.filter { !$0.rows.isEmpty }
    }

    /// A caption right before an unlabeled control becomes that control's label; the master switch of a
    /// feature page (same name as the page) is dropped, the status card above already holds it.
    static func tidy(_ rows: [SettingsRow], pageTitle: String?) -> [SettingsRow] {
        var out: [SettingsRow] = []
        var index = 0
        while index < rows.count {
            let row = rows[index]
            if row.item.kind == .toggle, row.item.label == pageTitle, !row.isLive { index += 1; continue }
            if row.item.kind == .caption, index + 1 < rows.count {
                let next = rows[index + 1]
                if next.item.label.isEmpty, next.item.kind != .caption {
                    let item = SettingsItem(kind: next.item.kind, label: row.item.label, value: next.item.value,
                                            options: next.item.options)
                    out.append(SettingsRow(id: next.id, item: item, control: next.control))
                    index += 2
                    continue
                }
            }
            out.append(row)
            index += 1
        }
        return out
    }

    static func item(for control: LiveControl) -> SettingsItem {
        let label = control.title ?? control.key
        switch control.kind {
        case .toggle, .stringFlag: return SettingsItem(kind: .toggle, label: label)
        case .choice: return SettingsItem(kind: .menu, label: label)
        case .stepper: return SettingsItem(kind: .stepper, label: label)
        case .slider: return SettingsItem(kind: .slider, label: label)
        case .shortcut: return SettingsItem(kind: .field, label: label)
        case .stringChoice: return SettingsItem(kind: .menu, label: label)
        case .action: return SettingsItem(kind: .button, label: label)
        case .readout: return SettingsItem(kind: .field, label: label)
        }
    }

    /// Every toggle of the page that a user could flip right now.
    public static func enabledToggles(for page: SettingsPage) -> [SettingsRow] {
        blocks(for: page).flatMap(\.rows).filter { $0.item.kind == .toggle && $0.isEnabled }
    }
}
