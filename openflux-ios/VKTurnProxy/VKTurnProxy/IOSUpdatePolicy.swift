import Foundation

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
