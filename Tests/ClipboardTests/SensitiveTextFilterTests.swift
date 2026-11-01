import AppKit
import Testing
@testable import ClipboardFeature

/// The opt-in guess. Synthetic strings only: none of these is a real credential.
@Suite struct SensitiveTextFilterTests {
    @Test(arguments: [
        "password: hunter2hunter2",
        "API_KEY=abc123def456",
        "{\"token\": \"abcdef123456\"}",
        "curl --password s3cretvalue https://example.test",
        "Authorization: Bearer abcdefghijklmnop",
        "sk-test0123456789abcdef0123",
        "ghp_0123456789abcdefghijklmnop",
        "AKIAABCDEFGHIJKLMNOP",
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.c2lnbmF0dXJl",
        "-----BEGIN RSA PRIVATE KEY-----\nMIIB\n-----END RSA PRIVATE KEY-----",
        "k7#Qp9!zX2@mW5$rT8&yU1*n",
        "4242 4242 4242 4242",
    ])
    func flagsWhatLooksLikeASecret(_ text: String) {
        #expect(SensitiveTextFilter.looksSensitive(text), "\(text.prefix(6))…")
    }

    @Test(arguments: [
        "hello world",
        "The token expired yesterday, please ask again",
        "max_tokens: 100 is the default",
        "https://example.test/path?q=a1b2c3d4e5f6g7h8i9j0",
        "123e4567-e89b-12d3-a456-426614174000",
        "/Users/someone/Documents/report-2026-final.pdf",
        "Réunion à 14h30 salle B, apporter le dossier",
        "1234 5678 9012 3456",   // 16 digits, fails the Luhn check
        "",
        "   ",
    ])
    func keepsOrdinaryText(_ text: String) {
        #expect(!SensitiveTextFilter.looksSensitive(text))
    }

    @MainActor @Test func theSettingIsOffByDefaultAndOnlyAffectsText() {
        final class Box { var captures: [PasteboardCapture?] = [] }
        let td = TempDefaults()
        let pb = makePasteboard()
        let box = Box()
        let watcher = PasteboardWatcher(pasteboard: pb)
        watcher.settings = { ClipboardSettings(defaults: td.defaults) }
        watcher.frontmostBundleID = { "com.example.app" }
        watcher.onChange = { _, capture, _ in box.captures.append(capture) }

        pb.clearContents(); pb.setString("password: hunter2hunter2", forType: .string)
        watcher.poll()
        #expect(box.captures == [.text("password: hunter2hunter2")], "off: recorded as before")

        td.defaults.set(true, forKey: "clipboardHistoryFilterSensitiveText")
        pb.clearContents(); pb.setString("password: hunter2hunter2", forType: .string)
        watcher.poll()
        #expect(box.captures.count == 2 && box.captures[1] == nil, "on: reported as a change, nothing captured")

        pb.clearContents(); pb.setString("une phrase ordinaire", forType: .string)
        watcher.poll()
        #expect(box.captures.last == .text("une phrase ordinaire"))
    }
}
