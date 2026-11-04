import Foundation
@testable import DefaultAppsFeature

/// A catalog with a handful of types, so no test depends on what this Mac knows.
struct FakeCatalog: ContentTypeCataloging {
    var ids: [String: String] = ["txt": "public.plain-text", "md": "net.daringfireball.markdown", "json": "public.json", "rtf": "public.rtf",
                                 "swift": "public.swift-source"]
    var parents: [String: [String]] = [
        "public.plain-text": ["public.text"], "net.daringfireball.markdown": ["public.plain-text", "public.text"],
        "public.json": ["public.text"], "public.rtf": ["public.text"], "public.swift-source": ["public.text"],
    ]
    var descriptions: [String: String] = [
        "public.plain-text": "Texte brut", "net.daringfireball.markdown": "Markdown", "public.json": "JSON", "public.rtf": "RTF",
        "public.swift-source": "Source Swift", "public.folder": "Dossier",
    ]
    var examples: [String: [String]] = [
        "public.plain-text": ["txt", "text"], "net.daringfireball.markdown": ["md", "markdown"], "public.json": ["json"],
        "public.rtf": ["rtf"], "public.swift-source": ["swift"],
    ]

    func identifier(forExtension ext: String) -> String? { ids[ext] }
    func extensions(forIdentifier id: String) -> [String] { examples[id] ?? [] }
    func description(forIdentifier id: String) -> String? { descriptions[id] }
    func conforms(_ id: String, to parent: String) -> Bool { id == parent || (parents[id] ?? []).contains(parent) }
}

/// Never touches LaunchServices. Records every write and can fail, cancel or ignore them.
final class FakeLaunchServices: LaunchServicesFacading, @unchecked Sendable {
    struct Write: Equatable { let kind: ChangeKind; let identifier: String; let app: URL }

    private let lock = NSLock()
    var apps: [(url: URL, plist: [String: Any])] = []
    var handlers: [String: String] = [:]
    var schemeHandlers: [String: String] = [:]
    var urls: [String: URL] = [:]
    var failing: Set<String> = []
    var cancelling: Set<String> = []
    /// Writes that succeed without changing the value read back.
    var ignoring: Set<String> = []
    /// Called before each write is recorded (a test checks the journal from here).
    var beforeWrite: (@Sendable (ChangeKind, String) -> Void)?
    var delay: Duration = .zero
    /// Writes that macOS answers too late: the new value lands, but the caller gets a timeout.
    var timingOut: Set<String> = []

    private var _writes: [Write] = []
    private var current = 0
    private(set) var peak = 0
    var writes: [Write] { lock.lock(); defer { lock.unlock() }; return _writes }

    func install(_ bundleID: String, name: String, path: String, plist extra: [String: Any] = [:]) {
        let url = URL(fileURLWithPath: path)
        var plist = extra
        plist["CFBundleIdentifier"] = bundleID
        plist["CFBundleName"] = name
        apps.append((url, plist))
        urls[bundleID] = url
    }

    func installedApplicationURLs() -> [URL] { apps.map(\.url) }
    func infoDictionary(at appURL: URL) -> [String: Any]? { apps.first { $0.url == appURL }?.plist }

    func defaultHandlerBundleID(forContentType id: String) -> String? { lock.lock(); defer { lock.unlock() }; return handlers[id] }
    func defaultHandlerBundleID(forScheme scheme: String) -> String? { lock.lock(); defer { lock.unlock() }; return schemeHandlers[scheme] }
    func applicationURL(forBundleID id: String) -> URL? { urls[id] }

    func setDefault(appURL: URL, contentType id: String) async throws { try await write(.contentType, id, appURL) }
    func setDefault(appURL: URL, scheme: String) async throws { try await write(.scheme, scheme, appURL) }

    private func write(_ kind: ChangeKind, _ id: String, _ app: URL) async throws {
        beforeWrite?(kind, id)
        lock.lock(); current += 1; peak = max(peak, current); _writes.append(Write(kind: kind, identifier: id, app: app)); lock.unlock()
        if delay > .zero { try? await Task.sleep(for: delay) }
        lock.lock(); current -= 1; lock.unlock()
        if timingOut.contains(id) {
            let bundle = urls.first { $0.value == app }?.key
            lock.lock()
            switch kind {
            case .contentType: handlers[id] = bundle
            case .scheme: schemeHandlers[id] = bundle
            }
            lock.unlock()
            throw LaunchServicesError("macOS n’a pas répondu à temps.", timedOut: true)
        }
        if cancelling.contains(id) { throw LaunchServicesError("Refusé dans la fenêtre de macOS.", userCancelled: true) }
        if failing.contains(id) { throw LaunchServicesError("Échec simulé.") }
        if ignoring.contains(id) { return }
        let bundle = urls.first { $0.value == app }?.key
        lock.lock(); defer { lock.unlock() }
        switch kind {
        case .contentType: handlers[id] = bundle
        case .scheme: schemeHandlers[id] = bundle
        }
    }
}

/// The fixture world: TextEdit owns the text types, Sublime Text can open most of them, Preview opens PDFs.
enum Fixture {
    static let textEdit = "com.apple.TextEdit"
    static let sublime = "com.sublimetext.4"
    static let preview = "com.apple.Preview"
    static let browser = "com.example.browser"

    static func textEditPlist() -> [String: Any] {
        ["CFBundleDocumentTypes": [
            ["CFBundleTypeRole": "Editor", "LSItemContentTypes": ["public.plain-text", "public.rtf", "public.folder"]],
            ["CFBundleTypeRole": "Editor", "CFBundleTypeExtensions": ["txt", "md", "*"]],
            ["CFBundleTypeRole": "None", "LSItemContentTypes": ["com.example.declined"]],
        ]]
    }

    static func sublimePlist() -> [String: Any] {
        [
            "CFBundleDocumentTypes": [
                ["CFBundleTypeRole": "Editor", "LSItemContentTypes": ["public.text", "public.data"]],
                ["CFBundleTypeRole": "Editor", "CFBundleTypeExtensions": ["json", ".swift"]],
            ],
            "CFBundleURLTypes": [["CFBundleURLSchemes": ["subl", "HTTP"]]],
        ]
    }

    /// TextEdit default for the text types (+ folder); Sublime installed; a browser owning http.
    static func world() -> FakeLaunchServices {
        let ls = FakeLaunchServices()
        ls.install(textEdit, name: "TextEdit", path: "/System/Applications/TextEdit.app", plist: textEditPlist())
        ls.install(sublime, name: "Sublime Text", path: "/Applications/Sublime Text.app", plist: sublimePlist())
        ls.install(preview, name: "Preview", path: "/System/Applications/Preview.app",
                   plist: ["CFBundleDocumentTypes": [["LSItemContentTypes": ["com.adobe.pdf"]]]])
        ls.install(browser, name: "Browser", path: "/Applications/Browser.app",
                   plist: ["CFBundleURLTypes": [["CFBundleURLSchemes": ["http", "https"]]]])
        for type in ["public.plain-text", "public.rtf", "net.daringfireball.markdown", "public.folder"] { ls.handlers[type] = textEdit }
        ls.handlers["public.json"] = textEdit
        ls.handlers["public.swift-source"] = textEdit
        ls.handlers["com.adobe.pdf"] = preview
        ls.schemeHandlers["http"] = browser
        return ls
    }
}
