import Foundation

/// Shares only an in-flight read, never a cached access decision.
/// One cancelled UI waiter must not cancel another caller's verification.
@MainActor
final class StartupRequestCoalescer<Value> {
    private var pending: [String: (UUID, Task<Value, Never>)] = [:]

    func value(for key: String, operation: @escaping @MainActor () async -> Value) async -> Value {
        if let existing = pending[key] { return await existing.1.value }
        let id = UUID()
        let task = Task { await operation() }
        pending[key] = (id, task)
        let result = await task.value
        if pending[key]?.0 == id { pending.removeValue(forKey: key) }
        return result
    }
}
