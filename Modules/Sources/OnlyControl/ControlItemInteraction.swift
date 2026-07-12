public enum ControlItemDetail: Equatable, Hashable, Sendable {
    case authenticator
}

public enum ControlItemInteraction: Equatable, Sendable {
    case performControl
    case presentDetail(ControlItemDetail)
}
