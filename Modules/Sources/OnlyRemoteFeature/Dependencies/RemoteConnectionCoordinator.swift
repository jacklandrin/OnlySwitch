import Foundation

actor RemoteConnectionCoordinator {
    private let connect: @Sendable (PairedMac) async -> Void
    private let disconnect: @Sendable (UUID) async -> Void
    private var plannedSelection: PairedMac?
    private var operationTail: Task<Void, Never>?

    init(
        connect: @escaping @Sendable (PairedMac) async -> Void,
        disconnect: @escaping @Sendable (UUID) async -> Void
    ) {
        self.connect = connect
        self.disconnect = disconnect
    }

    func select(_ mac: PairedMac?) async {
        guard plannedSelection?.id != mac?.id else {
            if let operationTail { await operationTail.value }
            return
        }
        let previous = plannedSelection
        plannedSelection = mac
        let predecessor = operationTail
        let connect = self.connect
        let disconnect = self.disconnect
        let operation = Task {
            if let predecessor { await predecessor.value }
            if let previous { await disconnect(previous.id) }
            if let mac { await connect(mac) }
        }
        operationTail = operation
        await operation.value
    }
}
