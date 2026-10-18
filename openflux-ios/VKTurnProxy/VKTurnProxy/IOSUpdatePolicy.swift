import Foundation

struct IOSUpdateConnectionIntent: Codable {
    let build: Int
    let serverID: UUID
    let created: TimeInterval
    private static let key = "openflux-update-connection-intent-v1"

    static func remember(build: Int, serverID: UUID, defaults: UserDefaults = .standard, now: TimeInterval = Date().timeIntervalSince1970) {
        let value = Self(build: build, serverID: serverID, created: now)
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    static func clear(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }

    static func takeAfterUpdate(build: Int, serverID: UUID, defaults: UserDefaults = .standard, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let data = defaults.data(forKey: key), let intent = try? JSONDecoder().decode(Self.self, from: data) else { return false }
        guard build != intent.build else { return false }
        clear(defaults: defaults) // One attempt, never a reconnect loop.
        return build > intent.build && intent.build > 0 && intent.serverID == serverID && now >= intent.created && now - intent.created <= 86400
    }
}

struct IOSUpdatePolicy: Codable, Equatable {
    let schema: Int
    let applicationID: String
    let latestBuild: Int
    let minimumBuild: Int
    let message: String
    enum CodingKeys: String, CodingKey {
        case schema, message
        case applicationID = "application_id", latestBuild = "latest_build", minimumBuild = "minimum_build"
    }
    var valid: Bool {
        schema == 1 && applicationID == "org.igoreshka7777.openflux" && latestBuild > 0 &&
        minimumBuild >= 0 && minimumBuild <= latestBuild && latestBuild < 10000000 && message.count <= 1000
    }
    func required(for build: Int) -> Bool { valid && build > 0 && build < minimumBuild }
    func available(for build: Int) -> Bool { valid && build > 0 && build < latestBuild }
}

enum IOSCheckoutRequest {
    static func make(password: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://openfluxvpn.ru/checkout/app")!)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let safe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        request.httpBody = Data(("password=" + (password.addingPercentEncoding(withAllowedCharacters: safe) ?? "")).utf8)
        return request
    }
}

private final class IOSUpdateRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum IOSUpdateAPI {
    private struct DeliveryStatus: Decodable {
        let ready: Bool
        let version: String
        let install_url: String?
    }
    static var build: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }
    private static var defaults: UserDefaults { UserDefaults(suiteName: "group.org.igoreshka7777.openflux") ?? .standard }
    private static let key = "openflux-ios-update-policy-v1"
    private static let session = URLSession(configuration: .ephemeral, delegate: IOSUpdateRedirectPolicy(), delegateQueue: nil)
    static var cached: IOSUpdatePolicy? {
        guard let data = defaults.data(forKey: key), let policy = try? JSONDecoder().decode(IOSUpdatePolicy.self, from: data), policy.valid else { return nil }
        return policy
    }
    static func installationURL(_ raw: String?) -> URL {
        if let raw = raw, let url = URL(string: raw), url.scheme == "https", url.host == "openfluxvpn.ru",
           url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
           url.path.range(of: "^/ios/update/[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil { return url }
        return URL(string: "https://openfluxvpn.ru/ios")!
    }
    static func validatedInstallURL(_ raw: String?) -> URL? {
        guard let raw, let parts = URLComponents(string: raw), parts.scheme == "itms-services",
              (parts.host ?? "").isEmpty, parts.path.isEmpty, parts.fragment == nil,
              parts.user == nil, parts.password == nil, parts.port == nil,
              let items = parts.queryItems, items.count == 2,
              items.filter({ $0.name == "action" && $0.value == "download-manifest" }).count == 1,
              let manifest = items.first(where: { $0.name == "url" })?.value,
              let url = URL(string: manifest), url.scheme == "https", url.host == "openfluxvpn.ru",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              url.path.range(of: "^/ios/install/[A-Za-z0-9_-]{43}/manifest\\.plist$", options: .regularExpression) != nil
        else { return nil }
        return parts.url
    }
    static func readyInstallationURL(_ personalURL: URL) async -> URL? {
        guard installationURL(personalURL.absoluteString) == personalURL,
              personalURL.path.hasPrefix("/ios/update/") else { return nil }
        var request = URLRequest(url: personalURL.appendingPathComponent("status"))
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200, data.count < 16384,
                  let status = try? JSONDecoder().decode(DeliveryStatus.self, from: data), status.ready,
                  let version = Int(status.version), version > build, version < 10000000,
                  version >= (cached?.latestBuild ?? 0) else { return nil }
            return validatedInstallURL(status.install_url)
        } catch { return nil }
    }
    static func fetch(force: Bool = false) async -> IOSUpdatePolicy? {
        if !force && Date().timeIntervalSince1970 - defaults.double(forKey: key + "-checked") < 60 { return cached }
        var request = URLRequest(url: URL(string: "https://openfluxvpn.ru/ios/updates/policy")!)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            guard !Task.isCancelled, (response as? HTTPURLResponse)?.statusCode == 200, data.count < 16384,
                  let policy = try? JSONDecoder().decode(IOSUpdatePolicy.self, from: data), policy.valid else { return cached }
            defaults.set(data, forKey: key)
            defaults.set(Date().timeIntervalSince1970, forKey: key + "-checked")
            return policy
        } catch { return cached }
    }
}
