import Foundation

/// Shared between the app and the root helper. Pure policy and the XPC contract live here;
/// the full contract is `FanHelperContract`.
public enum FanShared {
    public static let helperLabel = FanHelperContract.machServiceName
    public static let teamID = FanHelperContract.teamID
}
