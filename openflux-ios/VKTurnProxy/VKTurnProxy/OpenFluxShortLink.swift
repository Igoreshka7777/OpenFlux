import Foundation

private final class OpenFluxNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum OpenFluxShortLink {
    static func accepts(_ value: String) -> Bool {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.range(of: #"\Ahttps://openfluxvpn\.ru/s/[A-Za-z0-9_-]{22}\z"#,
                         options: .regularExpression) != nil
    }
    static func resolve(_ value: String) async throws -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Native links keep their original parser and never make a network request.
        guard accepts(raw) else { return raw }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        config.httpShouldSetCookies = false
        config.urlCache = nil
        let session = URLSession(configuration: config, delegate: OpenFluxNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: raw)!)
        request.setValue("application/vnd.openflux.connection", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "OpenFlux", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Не удалось получить настройки. Проверьте ссылку и интернет, затем повторите."])
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 8192 else {
                throw NSError(domain: "OpenFlux", code: 2, userInfo: [NSLocalizedDescriptionKey: "Некорректный ответ сервера"])
            }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              result.lowercased().hasPrefix("csqtt://") else {
            throw NSError(domain: "OpenFlux", code: 3, userInfo: [NSLocalizedDescriptionKey: "Сервер не вернул ссылку подключения"])
        }
        return result
    }
}
