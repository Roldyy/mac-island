import Foundation

/// The helper's XPC interface. Only `Int`, `Bool`, `String` and `Data` (JSON, see `FanWire`) cross
/// the boundary: all are property-list types NSXPC decodes securely without a class allowlist.
@objc(MIFanHelperXPC)
public protocol FanHelperXPC {
    /// Returns the helper's `FanHelperContract.protocolVersion`.
    func hello(clientVersion: Int, reply: @escaping @Sendable (Int) -> Void)
    /// JSON `FanState`, or nil and an error message.
    func fetchState(reply: @escaping @Sendable (Data?, String?) -> Void)
    /// JSON `FanCommand` in, JSON `FanCommandResult` out.
    func perform(command: Data, reply: @escaping @Sendable (Data?, String?) -> Void)
    /// Keeps manual mode alive. False when this client does not own manual mode (anymore).
    func heartbeat(reply: @escaping @Sendable (Bool) -> Void)
    /// JSON `FanSelfTestReport`. Reads only.
    func selfTestReadOnly(reply: @escaping @Sendable (Data?, String?) -> Void)
}
