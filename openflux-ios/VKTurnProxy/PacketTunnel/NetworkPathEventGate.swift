/// Owned by the provider's serial path queue. Only the latest path observation
/// may finish; late SSID callbacks and callbacks after stop are ignored.
struct NetworkPathEventGate {
    private var generation: UInt64 = 0
    private var pending: UInt64?

    mutating func begin() -> UInt64 {
        generation &+= 1
        pending = generation
        return generation
    }

    mutating func finish(_ ticket: UInt64) -> Bool {
        guard pending == ticket else { return false }
        pending = nil
        return true
    }

    func isPending(_ ticket: UInt64) -> Bool { pending == ticket }

    mutating func invalidate() {
        pending = nil
    }
}
