import Foundation
precondition(startupAccessFresh(state: "active", expiresAt: 2000, serverTime: 1000, checkedAt: 10, now: 11))
precondition(!startupAccessFresh(state: "active", expiresAt: 2000, serverTime: 1000, checkedAt: 10, now: 20))
precondition(!startupAccessFresh(state: "active", expiresAt: 1005, serverTime: 1000, checkedAt: 10, now: 15))
for state in ["expired", "disabled", "limit", "unknown"] {
    precondition(!startupAccessFresh(state: state, expiresAt: 2000, serverTime: 1000, checkedAt: 10, now: 11))
}
precondition(!startupAccessFresh(state: "active", expiresAt: 2000, serverTime: 1000, checkedAt: nil, now: 11))
precondition(!startupAccessFresh(state: "active", expiresAt: 2000, serverTime: 1000, checkedAt: 10, now: 9))
precondition(!startupAccessFresh(state: "active", expiresAt: 2000, serverTime: 0, checkedAt: 10, now: 11))
precondition(startupAccessFresh(state: "active", expiresAt: nil, serverTime: 1000, checkedAt: 10, now: 11))
print("Startup freshness checks passed: fresh, stale, expired, disabled, missing and clock rollback")
