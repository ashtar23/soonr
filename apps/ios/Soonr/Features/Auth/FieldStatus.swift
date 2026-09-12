/// What one field currently reports about itself, so its message and its
/// indicator come from the same value and cannot disagree.
enum FieldStatus: Equatable {
    case idle
    case checking
    case ok
    case problem(String)

    var message: String? {
        if case let .problem(message) = self {
            return message
        }

        return nil
    }

    var isProblem: Bool {
        message != nil
    }
}
