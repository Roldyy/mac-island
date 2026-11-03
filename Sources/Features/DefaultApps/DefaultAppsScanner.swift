import Foundation

/// Lists the installed apps and which of them is the current default handler of something. Read-only.
public struct DefaultAppsScanner: Sendable {
    let launchServices: any LaunchServicesFacading
    let catalog: any ContentTypeCataloging

    public init(launchServices: any LaunchServicesFacading, catalog: any ContentTypeCataloging) {
        self.launchServices = launchServices
        self.catalog = catalog
    }

    public func scan() -> ScanResult {
        var profiles: [AppProfile] = []
        var seen: Set<String> = []
        for url in launchServices.installedApplicationURLs() {
            guard let plist = launchServices.infoDictionary(at: url),
                  let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty, bundleID.utf8.count <= 255,
                  seen.insert(bundleID).inserted else { continue }
            let name = Self.displayName(plist: plist, url: url)
            profiles.append(AppProfile(bundleID: bundleID, name: name, url: url,
                                       declared: DeclaredTypesExtractor.extract(from: plist, catalog: catalog)))
        }

        // The universe: every type any installed app declares. Each is asked once.
        var defaults: [String: String] = [:]
        for type in Set(profiles.flatMap(\.declared.contentTypes)).sorted() {
            if let handler = launchServices.defaultHandlerBundleID(forContentType: type) { defaults[type] = handler }
        }

        var byHandler: [String: [String]] = [:]
        for (type, handler) in defaults { byHandler[handler, default: []].append(type) }
        let replaceable: [ReplaceableApp] = profiles.compactMap { profile in
            guard let types = byHandler[profile.bundleID], !types.isEmpty else { return nil }
            return ReplaceableApp(profile: profile, handled: types.sorted().map(handledType))
        }.sorted { ($0.count, $1.profile.name) > ($1.count, $0.profile.name) }

        return ScanResult(apps: profiles, defaults: defaults, replaceable: replaceable)
    }

    func handledType(_ id: String) -> HandledType {
        HandledType(id: id, summary: catalog.description(forIdentifier: id) ?? id,
                    extensions: Array(catalog.extensions(forIdentifier: id).prefix(4)),
                    isProtected: ProtectionPolicy.isProtected(contentType: id))
    }

    static func displayName(plist: [String: Any], url: URL) -> String {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = plist[key] as? String, !name.isEmpty { return name }
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
