import AppKit
import IslandKit
import SwiftTerm

/// SwiftTerm view for the island. It records when output last arrived, reports the first click so the island
/// can hand the keyboard over before the terminal becomes first responder, and carries what the island's
/// missing menu bar would otherwise provide: copy, paste, select all, clear, zoom, a context menu and drops.
///
/// SwiftTerm implements `copy(_:)` and `paste(_:)` but never handles a command-key event itself: it leaves that
/// to the main menu, and the island is an accessory app with none.
final class ActivityTerminalView: LocalProcessTerminalView {
    private(set) var lastOutputAt = Date()
    var onClick: (() -> Void)?

    private let fontSize = TerminalFontSize(defaults: AppDefaults.make() ?? .standard)
    private var toastLabel: NSTextField?
    private var toastWork: DispatchWorkItem?

    /// Selection fill: SwiftTerm's default teal is too close to the light text.
    static let selectionColor = NSColor(calibratedRed: 0.16, green: 0.34, blue: 0.78, alpha: 1)

    /// Whether the mouse belongs to the program in the terminal (SwiftTerm's `allowMouseReporting`). With it on,
    /// a TUI that asks for mouse events gets them and selecting needs Shift held; off, drags always select.
    static let appMouseKey = "terminalAppMouse"

    private var selectedText: String {
        guard selection.active else { return "" }
        return selection.getSelectedText()
    }

    var hasSelection: Bool { !selectedText.isEmpty }

    func configureInteraction() {
        selectedTextBackgroundColor = Self.selectionColor
        let defaults = AppDefaults.make() ?? .standard
        allowMouseReporting = (defaults.object(forKey: Self.appMouseKey) as? Bool) ?? true
        registerForDraggedTypes([.fileURL, .string])
    }

    /// Font a colour profile asked for; used only when it is installed and fixed-pitch. The size stays the user's.
    private var profileFontName: String?

    func applySavedFontSize() {
        font = terminalFont(size: fontSize.current)
    }

    private func terminalFont(size: Double) -> NSFont {
        if let name = profileFontName, let custom = NSFont(name: name, size: size), custom.isFixedPitch { return custom }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Wears a colour profile: palette, foreground, background, cursor, selection and (when usable) its font.
    func applyColorProfile(_ profile: TerminalColorProfile) {
        installColors(profile.ansi.map(\.terminalColor))
        nativeBackgroundColor = profile.background.nsColor
        nativeForegroundColor = profile.foreground.nsColor
        caretColor = profile.cursor.nsColor
        selectedTextBackgroundColor = profile.selection.nsColor
        profileFontName = profile.fontName
        applySavedFontSize()
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        lastOutputAt = Date()
        super.dataReceived(slice: slice)
    }

    // MARK: Mouse and focus

    /// The click that makes the island key must still reach the terminal (it starts the selection).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
        if window?.firstResponder !== self {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    // MARK: Keys

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Called for every view of the window: only the focused terminal answers. SwiftTerm's `keyDown`
        // is not open, so this is the one hook: AppKit offers every command-key event here before keyDown.
        guard window?.firstResponder === self, handleShortcut(event) else {
            return super.performKeyEquivalent(with: event)
        }
        return true
    }

    private func handleShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let action = TerminalKeyRouting.action(
                modifiers: event.modifierFlags, key: event.charactersIgnoringModifiers, hasSelection: hasSelection)
        else { return false }
        perform(action)
        return true
    }

    func perform(_ action: TerminalKeyAction) {
        switch action {
        case .copy: copy(self)
        case .paste: paste(self)
        case .selectAll: selectAll(nil)
        case .clear: clearScreen()
        case .interrupt: send(data: [0x03][...])
        case .fontLarger, .fontSmaller, .fontReset:
            let size = TerminalFontSize.next(fontSize.current, action: action)
            fontSize.current = size
            font = terminalFont(size: size)
        }
    }

    /// Wipe the scrollback, then send Ctrl+L so the shell clears the screen and redraws its prompt.
    func clearScreen() {
        getTerminal().clearScrollback()
        send(data: [0x0c][...])
    }

    // MARK: Copy and paste

    override func copy(_ sender: Any) {
        let text = selectedText
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        showToast("Copié")
    }

    override func paste(_ sender: Any) {
        insert(from: .general)
    }

    private func insert(from pasteboard: NSPasteboard) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
        guard let text = TerminalPaste.content(fileURLs: urls, string: pasteboard.string(forType: .string))
        else { return }
        send(data: TerminalPaste.payload(text: text, bracketed: getTerminal().bracketedPasteMode)[...])
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let copyItem = item("Copier", #selector(menuCopy))
        copyItem.isEnabled = hasSelection
        menu.addItem(copyItem)
        let pasteItem = item("Coller", #selector(menuPaste))
        pasteItem.isEnabled = NSPasteboard.general.availableType(from: [.string, .fileURL]) != nil
        menu.addItem(pasteItem)
        menu.addItem(item("Tout sélectionner", #selector(menuSelectAll)))
        menu.addItem(item("Effacer", #selector(menuClear)))
        menu.addItem(.separator())
        let mouse = item("Souris des applications", #selector(menuToggleAppMouse))
        mouse.state = allowMouseReporting ? .on : .off
        mouse.toolTip = "Activée : un programme comme un éditeur reçoit la souris, sélectionner demande Maj. "
            + "Désactivée : la souris sélectionne toujours."
        menu.addItem(mouse)
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func menuCopy() { perform(.copy) }
    @objc private func menuPaste() { perform(.paste) }
    @objc private func menuSelectAll() { perform(.selectAll) }
    @objc private func menuClear() { perform(.clear) }

    @objc private func menuToggleAppMouse() {
        allowMouseReporting.toggle()
        (AppDefaults.make() ?? .standard).set(allowMouseReporting, forKey: Self.appMouseKey)
    }

    // MARK: Drag and drop

    private func canAccept(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: [.fileURL, .string]) != nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        canAccept(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canAccept(sender.draggingPasteboard) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard canAccept(sender.draggingPasteboard) else { return false }
        onClick?()
        window?.makeFirstResponder(self)
        insert(from: sender.draggingPasteboard)
        return true
    }

    // MARK: Toast

    private func showToast(_ text: String) {
        let label = toastLabel ?? makeToast()
        label.stringValue = text
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 20, height: label.frame.height + 8)
        label.frame = NSRect(
            x: bounds.maxX - size.width - 10, y: bounds.maxY - size.height - 8,
            width: size.width, height: size.height)
        label.alphaValue = 1
        toastWork?.cancel()
        let work = DispatchWorkItem { [weak label] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                label?.animator().alphaValue = 0
            }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }

    private func makeToast() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.95, alpha: 1)
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 0.95).cgColor
        label.layer?.cornerRadius = 8
        label.autoresizingMask = [.minXMargin, .minYMargin]
        label.setAccessibilityLabel("Copié dans le presse-papiers")
        addSubview(label)
        toastLabel = label
        return label
    }
}
