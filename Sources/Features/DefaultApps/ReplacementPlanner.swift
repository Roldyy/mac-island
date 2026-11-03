import Foundation

/// Which of the replaced app's types are in play.
public enum TypeSelection: Equatable, Sendable {
    /// Every type that is not protected and that the replacement can open.
    case all
    /// Only these (lower-case UTIs). A protected one is honoured only when it is also in `explicitProtected`.
    case picked(Set<String>)
}

/// A candidate replacement and how many of the replaced app's types it can take.
public struct ReplacementCandidate: Identifiable, Equatable, Sendable {
    public let profile: AppProfile
    public let coverage: Int
    public var id: String { profile.bundleID }
}

/// Builds the preview and answers "can this app open that type". Pure: nothing here touches LaunchServices.
public struct ReplacementPlanner: Sendable {
    let catalog: any ContentTypeCataloging

    public init(catalog: any ContentTypeCataloging) { self.catalog = catalog }

    /// The app declares the type itself, or a parent it conforms to (never one of the catch-all parents).
    public func canOpen(_ app: AppProfile, contentType id: String) -> Bool {
        if app.declared.contentTypes.contains(id) { return true }
        return app.declared.contentTypes.contains { parent in
            !ProtectionPolicy.tooGenericToDeclare.contains(parent) && catalog.conforms(id, to: parent)
        }
    }

    public func canOpen(_ app: AppProfile, scheme: String) -> Bool { app.declared.schemes.contains(scheme.lowercased()) }

    /// Apps (other than the replaced one) that can open at least one unprotected type of `source`, best coverage first.
    public func candidates(for source: ReplaceableApp, among apps: [AppProfile]) -> [ReplacementCandidate] {
        apps.filter { $0.bundleID != source.profile.bundleID }.compactMap { app in
            let coverage = source.handled.filter { !$0.isProtected && canOpen(app, contentType: $0.id) }.count
            return coverage > 0 ? ReplacementCandidate(profile: app, coverage: coverage) : nil
        }.sorted { ($0.coverage, $1.profile.name) > ($1.coverage, $0.profile.name) }
    }

    public func preview(source: ReplaceableApp, replacement: AppProfile, selection: TypeSelection,
                        explicitProtected: Set<String> = [], scan: ScanResult) -> ReplacementPreview {
        var items: [PreviewItem] = []
        var refused: [RefusedItem] = []
        guard source.profile.bundleID != replacement.bundleID else {
            return ReplacementPreview(sourceName: source.profile.name, replacement: replacement, items: [], refused: [])
        }
        let wanted: [HandledType]
        switch selection {
        case .all: wanted = source.handled
        case .picked(let ids): wanted = source.handled.filter { ids.contains($0.id) }
        }
        for type in wanted {
            let current = scan.defaults[type.id]
            let picked = explicitProtected.contains(type.id)
            if type.isProtected && !picked {
                refused.append(RefusedItem(kind: .contentType, identifier: type.id, title: type.summary, reason: .protectedItem))
            } else if current == replacement.bundleID {
                refused.append(RefusedItem(kind: .contentType, identifier: type.id, title: type.summary, reason: .alreadyDefault))
            } else if !canOpen(replacement, contentType: type.id) {
                refused.append(RefusedItem(kind: .contentType, identifier: type.id, title: type.summary, reason: .replacementCannotOpen))
            } else {
                items.append(PreviewItem(kind: .contentType, identifier: type.id, title: type.summary, extensions: type.extensions,
                                         previousBundleID: current, previousName: scan.name(of: current),
                                         isProtected: type.isProtected, explicitlyPicked: type.isProtected && picked))
            }
        }
        return ReplacementPreview(sourceName: source.profile.name, replacement: replacement, items: items, refused: refused)
    }

    /// A URL scheme the user picked by name. Protected schemes need `confirmedProtected`.
    public func schemePreview(replacement: AppProfile, scheme rawScheme: String, confirmedProtected: Bool,
                              currentHandler: String?, currentName: String?) -> ReplacementPreview {
        guard let scheme = DeclaredTypesExtractor.cleanScheme(rawScheme) else {
            return ReplacementPreview(sourceName: nil, replacement: replacement, items: [], refused: [])
        }
        let title = "Liens \(scheme):"
        let protected = ProtectionPolicy.isProtected(scheme: scheme)
        var refused: [RefusedItem] = []
        var items: [PreviewItem] = []
        if protected && !confirmedProtected {
            refused.append(RefusedItem(kind: .scheme, identifier: scheme, title: title, reason: .protectedItem))
        } else if currentHandler == replacement.bundleID {
            refused.append(RefusedItem(kind: .scheme, identifier: scheme, title: title, reason: .alreadyDefault))
        } else if !canOpen(replacement, scheme: scheme) {
            refused.append(RefusedItem(kind: .scheme, identifier: scheme, title: title, reason: .replacementCannotOpen))
        } else {
            items.append(PreviewItem(kind: .scheme, identifier: scheme, title: title, previousBundleID: currentHandler,
                                     previousName: currentName, isProtected: protected, explicitlyPicked: protected))
        }
        return ReplacementPreview(sourceName: currentName, replacement: replacement, items: items, refused: refused)
    }
}
