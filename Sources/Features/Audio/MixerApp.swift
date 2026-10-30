import Foundation

struct MixerApp: Identifiable, Equatable {
    var id: String          // bundle id
    var name: String
    var pid: Int32
    var processIDs: [UInt32]
    var position: Double    // slider position 0...1
    var isMuted: Bool
    var isLive: Bool        // a tap is currently controlling this app
}
