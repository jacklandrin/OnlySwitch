import Foundation

actor RemoteConnectionCoordinator {
    private let connect: @Sendable (PairedMac) async -> Void
    private let disconnect: @Sendable (UUID) async -> Void
    private var selected: PairedMac?

    init(
        connect: @escaping @Sendable (PairedMac) async -> Void,
        disconnect: @escaping @Sendable (UUID) async -> Void
    ) {
        self.connect = connect
        self.disconnect = disconnect
    }

    func select(_ mac: PairedMac?) async {
        guard selected?.id != mac?.id else { return }
        if let previous = selected { await disconnect(previous.id) }
        selected = mac
        if let mac { await connect(mac) }
    }
}
