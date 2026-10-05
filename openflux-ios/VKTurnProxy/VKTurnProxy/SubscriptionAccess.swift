import Foundation
import CryptoKit
import UserNotifications

struct SubscriptionAccess: Decodable, Equatable {
    let state: String
    let expiresAt: Int64?
    let serverTime: Int64

    enum CodingKeys: String, CodingKey {
        case state
        case expiresAt = "expires_at"
        case serverTime = "server_time"
    }

    var expired: Bool {
        guard state == "expired", let expiry = expiresAt, expiry > 0 else { return false }
        return serverTime > expiry
    }
}

private final class SubscriptionRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward a connection credential to a redirect destination.
        completionHandler(nil)
    }
}

enum SubscriptionAPI {
    static let renewalURL = URL(string: "https://2.56.174.146/renew")!
    private static let endpoint = URL(string: "https://2.56.174.146/api/client/subscription")!
    private static let session = URLSession(configuration: .ephemeral,
        delegate: SubscriptionRedirectPolicy(), delegateQueue: nil)

    static func fetch(password: String) async -> SubscriptionAccess? {
        guard !password.isEmpty else { return nil }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(password)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(SubscriptionAccess.self, from: data)
        } catch { return nil }
    }
}

enum SubscriptionNotices {
    private static var preferences: UserDefaults {
        UserDefaults(suiteName: "group.org.igoreshka7777.openflux") ?? .standard
    }
    private static func identifier(_ password: String) -> String {
        "openflux-expiry-" + SHA256.hash(data: Data(password.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func clear(password: String) {
        let key = identifier(password)
        preferences.removeObject(forKey: key)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [key])
    }

    static func show(password: String, expiry: Int64) async {
        let key = identifier(password)
        guard (preferences.object(forKey: key) as? NSNumber)?.int64Value != expiry else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Подписка OpenFlux закончилась"
        content.body = "Откройте OpenFlux, чтобы продлить доступ через Telegram или ВКонтакте."
        content.sound = .default
        content.userInfo = ["open_subscription_renewal": true]
        preferences.set(NSNumber(value: expiry), forKey: key)
        do { try await center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil)) }
        catch { preferences.removeObject(forKey: key) }
    }
}
