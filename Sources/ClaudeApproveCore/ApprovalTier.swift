import Foundation

/// How much of a permission request may travel through the island.
///  - `refuse`: never enters the channel, the native dialog alone decides.
///  - `denyOnly`: the island may show Refuser and Ouvrir, never Autoriser; an allow decision is ignored by the hook.
///  - `allow`: the island may show Autoriser once, when the whole request fits on one line.
/// Everything unknown is `denyOnly`; every doubt resolves to a stricter tier.
/// Port (method, not code) of the tier rules of the rm-board approval hook; same shared cases.
public enum ApprovalTier: String, Sendable, Equatable {
    case allow
    case denyOnly = "deny-only"
    case refuse
}

public struct ApprovalVerdict: Equatable, Sendable {
    public var tier: ApprovalTier
    public var why: String
    public init(_ tier: ApprovalTier, _ why: String) { self.tier = tier; self.why = why }
}

/// What the file system says about the request, resolved by `ApprovalContext.resolve` (the classifier itself stays pure).
public struct ApprovalContext: Equatable, Sendable {
    public var home: String
    /// The chat's folder, symlinks resolved ("" when unknown).
    public var cwdReal: String
    /// The target path resolved from its directory ("" when unknown).
    public var real: String
    public var isLink: Bool
    public var isDir: Bool
    /// Bash only: each word of the command read as a path, parent resolved.
    public var wordReals: [String]
    /// Bash only: one of those words is itself a symlink.
    public var wordLink: Bool

    public init(home: String, cwdReal: String = "", real: String = "", isLink: Bool = false, isDir: Bool = false,
                wordReals: [String] = [], wordLink: Bool = false) {
        self.home = home; self.cwdReal = cwdReal; self.real = real; self.isLink = isLink; self.isDir = isDir
        self.wordReals = wordReals; self.wordLink = wordLink
    }
}

public enum ApprovalClassifier {
    // MARK: patterns (matched on lower-cased text; the macOS disk ignores case)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // A pattern that does not compile is a programming error caught by the first test run.
        try! NSRegularExpression(pattern: pattern, options: [])
    }

    /// Control characters (not \n \t \r, which a file's text may hold), bidi overrides, zero-width characters.
    private static let hiddenRE = regex(
        #"[\x{0001}-\x{0008}\x{000b}\x{000c}\x{000e}-\x{001f}\x{007f}-\x{009f}\x{200b}-\x{200f}\x{202a}-\x{202e}\x{2060}-\x{2069}\x{feff}]"#)

    /// Secret-looking paths, in a path or anywhere in a command (a path may start after a blank there).
    private static let secretRE = regex(
        #"(^|[/\s])(\.ssh|\.aws|\.gnupg|\.kube|\.docker|\.azure|\.gcloud|\.password-store|otb_memory|\.rm-board|be\.roldy\.macisland)(/|$|\s)"#
        + #"|(^|[/\s])\.config/(gh|gcloud|git|op|1password|rclone)(/|$|\s)"#
        + #"|(^|[/\s])\.(netrc|npmrc|pypirc|pgpass|my\.cnf|git-credentials|gitconfig|zsh_history|bash_history|python_history|psql_history|claude\.json|vault-token)($|\s)"#
        + #"|(^|[/\s])\.env($|[.*?\s])"#
        + #"|\.(pem|key|p12|pfx|p8|keystore|kdbx|jks|ppk|ovpn|token)($|\s)"#
        + #"|(^|[/\s])(credentials|secrets?|service[-_]account)[^/\s]*($|\s)"#
        + #"|(^|[/\s])id_(rsa|ed25519|ecdsa|dsa)"#
        + #"|keychains?(/|$)|(^|/)library/(cookies|application support/(google/chrome|firefox|1password))"#
        + #"|(^|[/\s])\.claude/(\.credentials|settings)"#)

    private static let dotdotRE = regex(#"(^|/)\.\.(/|$)"#)
    private static let shellSyntaxRE = regex(#"[;&|<>$`(){}\\'"*?!~\[\]]"#)
    private static let mcpNameRE = regex(#"^mcp__[A-Za-z0-9_-]+__[A-Za-z0-9_-]+$"#)
    private static let mcpWriteRE = regex(
        #"(^|_)(write|create|update|delete|unlink|send|execute|reset|call|run|set|post|apply|import|export|start|stop|restore|neutralize|pull|branch|commit|push|upload|move|copy|rename|trash|modify|respond|forward|draft|approve|cancel)(_|$)"#)
    private static let mcpReadRE = regex(#"(^|_)(search|read|list|get|status|find|describe|fields)(_|$)"#)
    private static let hiddenPartRE = regex(#"/\."#)
    private static let generatedRE = regex(#"/(node_modules|site-packages|__pycache__|library)/"#)
    private static let configFileRE = regex(#"^settings.*\.json$|^claude\.md$|\.pth$"#)
    private static let dateSetRE = regex(#"^-[a-zA-Z]*s|^--set"#)
    private static let tailFollowRE = regex(#"^-[a-zA-Z0-9]*[fF]|^--follow|^--pid"#)

    private static func test(_ re: NSRegularExpression, _ text: String) -> Bool {
        re.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) != nil
    }
    private static func secret(_ s: String) -> Bool { test(secretRE, s.lowercased()) }
    private static func hidden(_ s: String) -> Bool { test(hiddenRE, s) }
    private static func hasDotdot(_ s: String) -> Bool { test(dotdotRE, s) }
    private static func length(_ s: String) -> Int { s.unicodeScalars.count }
    /// Judged on scalars, never on Characters: "\r\n" is ONE Character that equals neither "\n" nor "\r".
    static func hasLineBreak(_ s: String) -> Bool { s.unicodeScalars.contains { $0 == "\n" || $0 == "\r" } }
    /// Words split on scalars (space, tab, CR, LF) for the same reason.
    static func words(_ s: String) -> [String] {
        var out: [String] = [], current = String.UnicodeScalarView()
        for scalar in s.unicodeScalars {
            if scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" {
                if !current.isEmpty { out.append(String(current)); current = String.UnicodeScalarView() }
            } else { current.append(scalar) }
        }
        if !current.isEmpty { out.append(String(current)) }
        return out
    }

    // MARK: classification

    private static func deny(_ why: String) -> ApprovalVerdict { ApprovalVerdict(.denyOnly, why) }
    private static let allowed = ApprovalVerdict(.allow, "ok")
    private static func refuse(_ why: String) -> ApprovalVerdict { ApprovalVerdict(.refuse, why) }

    private static func expand(_ p: String, home: String) -> String {
        if p == "~" { return home }
        if p.hasPrefix("~/") { return home + "/" + p.dropFirst(2) }
        return p
    }

    /// A read-style path: not a secret, not the root or the home folder, no traversal we could not resolve.
    private static func readPathOK(_ value: Any?, _ ctx: ApprovalContext) -> Bool {
        guard let p = value as? String, !p.isEmpty else { return false }
        let e = expand(p, home: ctx.home)
        let lowHome = ctx.home.lowercased()
        if secret(e) || secret(ctx.real) { return false }
        let le = e.lowercased(), lr = ctx.real.lowercased()
        if le == "/" || le == lowHome || lr == "/" || lr == lowHome { return false }
        if hasDotdot(e) && ctx.real.isEmpty { return false }
        return true
    }

    private static func bash(_ input: [String: Any], _ ctx: ApprovalContext) -> ApprovalVerdict {
        if !Set(input.keys).subtracting(["command", "description", "timeout"]).isEmpty {
            return deny("extra keys (sandbox or background flags)")
        }
        guard let c = input["command"] as? String else { return deny("no command") }
        if length(c) > 80 { return deny("long") }
        if c.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" }) { return deny("multiline") }
        if test(shellSyntaxRE, c) { return deny("shell syntax") }
        if secret(c) { return deny("secret path") }
        if ctx.wordLink { return deny("an argument is a symlink") }
        if ctx.wordReals.contains(where: secret) { return deny("an argument resolves to a secret") }
        if ctx.wordReals.contains(where: { let l = $0.lowercased(); return l.hasPrefix("/dev/") || l.hasPrefix("/proc/") }) {
            return deny("device path")
        }
        let words = Self.words(c)
        let verb = words.first ?? ""
        let args = Array(words.dropFirst())
        guard ["ls", "cat", "head", "tail", "wc", "pwd", "stat", "which", "date"].contains(verb) else {
            return deny("not a read-only verb")
        }
        if verb == "date", args.contains(where: { test(dateSetRE, $0) }) { return deny("date set") }
        if verb == "tail", args.contains(where: { test(tailFollowRE, $0) }) { return deny("tail follow") }
        return allowed
    }

    private static func compactJSONLength(_ value: Any) -> Int {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return Int.max }
        return length(text)
    }

    private static func mcp(_ tool: String, _ input: [String: Any]) -> ApprovalVerdict {
        if !test(mcpNameRE, tool) { return deny("odd mcp name") }
        if compactJSONLength(input) > 60 { return deny("arguments too long to show") }
        let name = tool.components(separatedBy: "__").last ?? ""
        if test(mcpWriteRE, name) { return deny("mcp that writes") }
        if test(mcpReadRE, name) { return allowed }
        return deny("mcp not on the read list")
    }

    /// An edit is allowed only when the change itself fits on the card line: no newline, 60 characters or fewer in all.
    private static func edit(_ tool: String, _ input: [String: Any], _ ctx: ApprovalContext) -> ApprovalVerdict {
        let r = ctx.real.lowercased(), c = ctx.cwdReal.lowercased(), lowHome = ctx.home.lowercased()
        let texts = ["content", "new_string", "old_string"].compactMap { input[$0] as? String }
        if tool == "MultiEdit" { return deny("multi edit is not shown in full") }
        if ctx.isLink { return deny("symlink") }
        if ctx.real.isEmpty { return deny("unresolved path") }
        if c.isEmpty || c == "/" || c == lowHome { return deny("chat folder too broad") }
        if !r.hasPrefix(c + "/") { return deny("outside the chat folder") }
        if secret(r) { return deny("secret path") }
        let rest = String(r.dropFirst(c.count))
        if test(hiddenPartRE, rest) { return deny("hidden folder or file") }
        if test(generatedRE, rest) { return deny("generated or system folder") }
        if test(configFileRE, r.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? "") {
            return deny("config or startup file")
        }
        if texts.contains(where: hasLineBreak) { return deny("multi-line change") }
        if texts.reduce(0, { $0 + length($1) }) > 60 { return deny("large change") }
        if (input["replace_all"] as? Bool) == true { return deny("replace all") }
        return allowed
    }

    /// Every string value of the input, at any depth (keys are not included).
    static func strings(in value: Any) -> [String] {
        switch value {
        case let s as String: return [s]
        case let d as [String: Any]: return d.values.flatMap { strings(in: $0) }
        case let a as [Any]: return a.flatMap { strings(in: $0) }
        default: return []
        }
    }

    public static func classify(toolName: String?, toolInput: Any?, context ctx: ApprovalContext) -> ApprovalVerdict {
        guard let tool = toolName, !tool.isEmpty else { return refuse("no tool") }
        let input = (toolInput as? [String: Any]) ?? [:]
        let strs = strings(in: input)
        let total = strs.reduce(0) { $0 + length($1) }
        if ["AskUserQuestion", "ExitPlanMode", "WebFetch"].contains(tool) { return refuse("never remote") }
        if strs.contains(where: { $0.contains(".rm-board") || $0.contains("be.roldy.macisland") }) { return refuse("channel path") }
        if total > 30000 { return refuse("size") }
        if strs.contains(where: hidden) { return refuse("hidden characters") }
        let pathValues = ["file_path", "path", "notebook_path"].compactMap { input[$0] as? String }
        if pathValues.contains(where: hasLineBreak) { return deny("newline in a path") }

        var verdict: ApprovalVerdict
        switch tool {
        case "Read":
            verdict = readPathOK(input["file_path"], ctx) && !ctx.isLink ? allowed : deny("read target")
        case "Glob":
            let pattern = input["pattern"] ?? ""
            let path = input["path"] ?? "x"
            let patternText = (pattern as? String) ?? ""
            verdict = readPathOK(pattern, ctx) && readPathOK(path, ctx) && !hasDotdot(patternText)
                ? allowed : deny("glob target")
        case "Grep":
            if !(input["path"] is String) { verdict = deny("search without a file") }
            else if ctx.isDir || ctx.isLink { verdict = deny("search over a folder or a link") }
            else if !Set(input.keys).subtracting(["pattern", "path", "output_mode", "-n", "-i", "head_limit", "type"]).isEmpty {
                verdict = deny("search options not shown")
            }
            else { verdict = readPathOK(input["path"], ctx) ? allowed : deny("grep target") }
        case "Write", "Edit", "MultiEdit":
            verdict = edit(tool, input, ctx)
        case "Bash":
            verdict = bash(input, ctx)
        case _ where tool.hasPrefix("mcp__"):
            verdict = mcp(tool, input)
        default:
            verdict = deny("tool not in a tier")
        }
        if verdict.tier == .allow && total > 200 { verdict = deny("request too long for one line") }
        return verdict
    }
}
