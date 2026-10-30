enum TapWatchdog {
    /// macOS turns an active tap off when its callback is slow (timeout) or on some user input:
    /// both mean "switch it back on".
    static func shouldReenable(disabledByTimeout: Bool, disabledByUserInput: Bool) -> Bool {
        disabledByTimeout || disabledByUserInput
    }
}
