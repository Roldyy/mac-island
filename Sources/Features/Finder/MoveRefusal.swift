enum MoveRefusal: Error, Equatable {
    case noItems
    case destinationUnavailable
    case intoItself
    case sameFolder
    case needsConfirmation(count: Int)
}
