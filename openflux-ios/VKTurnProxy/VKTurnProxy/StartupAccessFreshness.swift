import Foundation

/// A short-lived successful answer only; clock rollback and expiry force a fresh request.
func startupAccessFresh(state: String, expiresAt: Int64?, serverTime: Int64, checkedAt: TimeInterval?, now: TimeInterval) -> Bool {
    guard state == "active", serverTime > 0, let checkedAt, now >= checkedAt else { return false }
    let age = now - checkedAt
    guard age.isFinite, age < 10 else { return false }
    guard let expiry = expiresAt, expiry != 0 else { return true }
    return expiry > serverTime && Double(expiry - serverTime) > age + 1
}
