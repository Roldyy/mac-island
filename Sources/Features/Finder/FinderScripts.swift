/// AppleScript sources. `application id` addresses Finder by bundle id; the caller has already
/// checked that Finder is frontmost, so these never launch it.
enum FinderScripts {
    static let finderBundleID = "com.apple.finder"

    /// A list: item 1 is the number of selected items, then one POSIX path per item. A list keeps every
    /// name in its own item, whatever characters it holds (no delimiter to inject).
    static let selection = """
    tell application id "com.apple.finder"
        set sel to selection as alias list
        set out to {count of sel}
        repeat with a in sel
            set end of out to POSIX path of a
        end repeat
        return out
    end tell
    """

    /// The folder a paste lands in: front window's folder, or the Desktop when no window is open.
    static let targetFolder = """
    tell application id "com.apple.finder"
        return POSIX path of (insertion location as alias)
    end tell
    """
}
