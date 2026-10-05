import Foundation

func access(_ state: String = "active", _ expiry: Int64?, _ now: Int64 = 1_000) -> SubscriptionAccess {
    SubscriptionAccess(state: state, expiresAt: expiry, serverTime: now)
}
precondition(access("active", 1_001).daysRemaining == 1)
precondition(access("active", 87_400).daysRemaining == 1)
precondition(access("active", 87_401).daysRemaining == 2)
precondition(access("expired", 999).daysRemaining == 0)
precondition(access("active", nil).daysRemaining == nil)
precondition(access("active", 0).daysRemaining == nil)
precondition(access("expired", 999).expired)
precondition(!access("active", 999).expired)
precondition(!access("expired", 1_000).expired)
let data = Data("{\"state\":\"active\",\"expires_at\":87401,\"server_time\":1000}".utf8)
let decoded = try JSONDecoder().decode(SubscriptionAccess.self, from: data)
precondition(decoded.daysRemaining == 2)
print("Subscription checks passed")
