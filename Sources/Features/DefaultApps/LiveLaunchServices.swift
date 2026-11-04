import AppKit
import Foundation
import UniformTypeIdentifiers

/// The real LaunchServices door (public NSWorkspace API only). Reads are cached per instance for bundle ids.
public final class LiveLaunchServices: LaunchServicesFacading, @unchecked Sendable {
    /// How long one `setDefault` may wait for macOS's own sheet before the call is reported as failed.
    static let writeTimeout: Duration = .seconds(120)
    static let maxPlistBytes = 4 * 1024 * 1024
    static let maxApps = 2000

    private let lock = NSLock()
    private var bundleIDs: [String: String?] = [:]

    public init() {}

    public func installedApplicationURLs() -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Applications/Utilities"),
            home.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
        ]
        var found: [URL] = []
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else { continue }
            for item in items.sorted(by: { $0.path < $1.path }) {
                if item.pathExtension == "app" {
                    found.append(item)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    // One vendor folder level (Adobe, Microsoft...), never deeper.
                    let inner = (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                    found += inner.filter { $0.pathExtension == "app" }.sorted { $0.path < $1.path }
                }
                if found.count >= Self.maxApps { return found }
            }
        }
        return found
    }

    public func infoDictionary(at appURL: URL) -> [String: Any]? {
        let url = appURL.appendingPathComponent("Contents/Info.plist")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0, size <= Self.maxPlistBytes,
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist
    }

    public func defaultHandlerBundleID(forContentType id: String) -> String? {
        guard let type = UTType(id) else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: type).flatMap(bundleID(at:))
    }

    public func defaultHandlerBundleID(forScheme scheme: String) -> String? {
        guard let url = URL(string: "\(scheme)://example") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: url).flatMap(bundleID(at:))
    }

    public func applicationURL(forBundleID id: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    public func setDefault(appURL: URL, contentType id: String) async throws {
        guard let type = UTType(id) else { throw LaunchServicesError("Type inconnu : \(id)") }
        try await write { try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) }
    }

    public func setDefault(appURL: URL, scheme: String) async throws {
        try await write { try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpenURLsWithScheme: scheme) }
    }

    private func bundleID(at url: URL) -> String? {
        lock.lock()
        if let cached = bundleIDs[url.path] { lock.unlock(); return cached }
        lock.unlock()
        let id = Bundle(url: url)?.bundleIdentifier
        lock.lock(); bundleIDs[url.path] = .some(id); lock.unlock()
        return id
    }

    /// Runs one write on the main actor and gives up after `writeTimeout` (a sheet nobody answers).
    private func write(_ operation: @escaping @MainActor @Sendable () async throws -> Void) async throws {
        let gate = OnceGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let worker = Task { @MainActor in
                do {
                    try await operation()
                    gate.resume(continuation, with: .success(()))
                } catch {
                    gate.resume(continuation, with: .failure(Self.classify(error)))
                }
            }
            Task {
                try? await Task.sleep(for: Self.writeTimeout)
                if gate.resume(continuation, with: .failure(LaunchServicesError("macOS n’a pas répondu à temps : le réglage peut encore changer.", timedOut: true))) {
                    worker.cancel()
                }
            }
        }
    }

    static func classify(_ error: Error) -> LaunchServicesError {
        let ns = error as NSError
        let cancelled = ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError
        return LaunchServicesError(cancelled ? "Refusé dans la fenêtre de macOS." : ns.localizedDescription, userCancelled: cancelled)
    }
}

/// Resumes a continuation exactly once, whoever gets there first.
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    @discardableResult
    func resume(_ continuation: CheckedContinuation<Void, Error>, with result: Result<Void, Error>) -> Bool {
        lock.lock()
        if done { lock.unlock(); return false }
        done = true
        lock.unlock()
        continuation.resume(with: result)
        return true
    }
}

/// UTType-backed catalog.
public struct LiveContentTypeCatalog: ContentTypeCataloging {
    public init() {}

    public func identifier(forExtension ext: String) -> String? {
        guard let type = UTType(filenameExtension: ext), !type.identifier.hasPrefix("dyn.") else { return nil }
        return type.identifier
    }

    public func extensions(forIdentifier id: String) -> [String] {
        guard let type = UTType(id) else { return [] }
        return type.tags[.filenameExtension] ?? []
    }

    public func description(forIdentifier id: String) -> String? {
        UTType(id)?.localizedDescription
    }

    public func conforms(_ id: String, to parent: String) -> Bool {
        if id == parent { return true }
        guard let type = UTType(id), let parentType = UTType(parent) else { return false }
        return type.conforms(to: parentType)
    }
}
