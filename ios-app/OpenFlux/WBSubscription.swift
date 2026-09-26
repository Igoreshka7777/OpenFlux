import Foundation

enum WBSubscriptionError: LocalizedError {
    case invalidURL
    case invalidResponse
    case tooLarge
    case missingNode
    case invalidNode

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Вставьте HTTPS-подписку или прямую ссылку olcrtc://wbstream"
        case .invalidResponse: return "Не удалось загрузить подписку"
        case .tooLarge: return "Файл подписки слишком большой"
        case .missingNode: return "В подписке нет узла WB Stream"
        case .invalidNode: return "Неверные параметры узла WB Stream"
        }
    }
}

enum WBSubscription {
    static func load(_ link: String) async throws -> [String: Any] {
        let input = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.hasPrefix("olcrtc://wbstream?") {
            return try parse(input)
        }
        guard let url = URL(string: input),
              url.scheme?.lowercased() == "https", url.host != nil else {
            throw WBSubscriptionError.invalidURL
        }
        var request = URLRequest(url: url,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 20)
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              http.url?.scheme?.lowercased() == "https" else {
            throw WBSubscriptionError.invalidResponse
        }
        guard data.count <= 1_048_576 else { throw WBSubscriptionError.tooLarge }
        guard let text = String(data: data, encoding: .utf8) else {
            throw WBSubscriptionError.invalidResponse
        }
        return try parse(text)
    }

    static func parse(_ text: String) throws -> [String: Any] {
        let lines = text.split(whereSeparator: \.isNewline)
        guard let line = lines.map(String.init).first(where: {
            $0.hasPrefix("olcrtc://wbstream?vp8channel@")
        }) else {
            throw WBSubscriptionError.missingNode
        }
        let withoutPrefix = String(line.dropFirst("olcrtc://wbstream?vp8channel@".count))
        guard let hash = withoutPrefix.firstIndex(of: "#") else {
            throw WBSubscriptionError.invalidNode
        }
        let rawRoom = String(withoutPrefix[..<hash])
        let afterHash = withoutPrefix[withoutPrefix.index(after: hash)...]
        let key = String(afterHash.prefix(while: { $0 != "$" })).lowercased()
        let room = rawRoom.removingPercentEncoding ?? rawRoom
        guard !room.isEmpty, room.count <= 256,
              room.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              key.count == 64,
              key.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "0123456789abcdef").contains($0)
              }) else {
            throw WBSubscriptionError.invalidNode
        }
        let name = lines.first(where: { $0.hasPrefix("#name:") })
            .map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? "WB Stream"
        return [
            "name": name,
            "provider": "wbstream",
            "transport": "vp8channel",
            "room": room,
            "key": key,
            "vp8FPS": 30,
            "vp8BatchSize": 64
        ]
    }
}
