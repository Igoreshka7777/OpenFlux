import Foundation

@main struct Checks {
    @MainActor static func main() async {
        let requests = StartupRequestCoalescer<String?>()
        var calls = 0
        let fetch: @MainActor () async -> String? = {
            calls += 1
            try? await Task.sleep(nanoseconds: 50_000_000)
            return "expired"
        }
        async let a = requests.value(for: "same", operation: fetch)
        async let b = requests.value(for: "same", operation: fetch)
        let pair = await (a, b)
        precondition(pair.0 == "expired" && pair.1 == "expired" && calls == 1)
        _ = await requests.value(for: "same", operation: fetch)
        precondition(calls == 2, "No stale response may be cached")
        async let c = requests.value(for: "account-a", operation: fetch)
        async let d = requests.value(for: "account-b", operation: fetch)
        _ = await (c, d)
        precondition(calls == 4, "Different credentials must stay isolated")
        let first = Task { await requests.value(for: "cancel", operation: fetch) }
        await Task.yield()
        let second = Task { await requests.value(for: "cancel", operation: fetch) }
        first.cancel()
        let result = await second.value
        _ = await first.value
        precondition(result == "expired" && calls == 5, "A cancelled waiter must not cancel verification")
        let failed = await requests.value(for: "retry", operation: { nil })
        precondition(failed == nil)
        let retry = await requests.value(for: "retry", operation: { "active" })
        precondition(retry == "active", "Failures must not poison retries")
        print("Coalescing passed: duplicate, expiry, isolation, cancellation, retry")
    }
}
