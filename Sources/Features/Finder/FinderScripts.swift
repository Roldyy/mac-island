/// AppleScript sources. `application id` addresses Finder by bundle id; the caller has already
/// checked that Finder is frontmost, so these never launch it.
enum FinderScripts {
    static let finderBundleID = "com.apple.finder"

    /// POSIX paths of the selected items, joined by the record separator.
    static let selection = """
    tell application id "com.apple.finder"
        set sel to selection as alias list
        set out to {}
        repeat with a in sel
            set end of out to POSIX path of a
        end repeat
        set AppleScript's text item delimiters to (character id 30)
        return out as text
    end tell
    """

    /// The folder a paste lands in: front window's folder, or the Desktop when no window is open.
    static let targetFolder = """
    tell application id "com.apple.finder"
        return POSIX path of (insertion location as alias)
    end tell
    """
}
