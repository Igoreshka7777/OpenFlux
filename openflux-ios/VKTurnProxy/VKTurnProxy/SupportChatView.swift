import SwiftUI

private struct SupportMessage: Decodable, Identifiable {
    let id: Int
    let body: String
    let sender: String
}

private struct SupportConversation: Decodable {
    let messages: [SupportMessage]
}

private enum SupportRequestError: Error {
    case status(Int)

    var message: String {
        switch self {
        case .status(401): return "Ключ доступа не найден. Вставьте действующую личную ссылку в настройках."
        case .status(503): return "Поддержка временно недоступна. Попробуйте позже."
        case .status(let code): return "Сервер поддержки ответил с ошибкой \(code)."
        }
    }
}

@MainActor
private final class SupportChatModel: ObservableObject {
    @Published var messages: [SupportMessage] = []
    @Published var error = ""
    @Published var sending = false
    private var pollTask: Task<Void, Never>?
    private var pendingNonce: String?
    private let endpoint = URL(string: "https://2.56.174.146/api/client/conversation")!

    func start(password: String) {
        pollTask?.cancel()
        guard !password.isEmpty else {
            messages = []
            error = "Вставьте личную ссылку подключения в настройках, чтобы открыть чат."
            return
        }
        pollTask = Task {
            while !Task.isCancelled {
                await refresh(password: password)
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    func stop() { pollTask?.cancel(); pollTask = nil }
    func resetPendingSend() { pendingNonce = nil }

    func refresh(password: String) async {
        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 8
            request.setValue("Bearer \(password)", forHTTPHeaderField: "Authorization")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                throw SupportRequestError.status(status)
            }
            messages = try JSONDecoder().decode(SupportConversation.self, from: data).messages
            error = ""
        } catch let requestError as SupportRequestError {
            self.error = requestError.message
        } catch {
            self.error = "Не удалось загрузить чат. Проверьте подключение к интернету."
        }
    }

    func send(password: String, body: String) async -> Bool {
        guard !sending else { return false }
        sending = true
        defer { sending = false }
        let nonce = pendingNonce ?? UUID().uuidString.lowercased()
        pendingNonce = nonce
        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 8
            request.httpMethod = "POST"
            request.setValue("Bearer \(password)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["body": body, "nonce": nonce])
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                throw SupportRequestError.status(status)
            }
            pendingNonce = nil
            await refresh(password: password)
            return true
        } catch let requestError as SupportRequestError {
            self.error = requestError.message
            return false
        } catch {
            self.error = "Отправка не подтверждена. Повторное нажатие безопасно."
            return false
        }
    }
}

struct SupportChatView: View {
    let password: String
    let onClose: () -> Void
    @StateObject private var model = SupportChatModel()
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 21, weight: .semibold))
                        .frame(width: 38, height: 44)
                }
                .accessibilityLabel("Назад")
                Circle().fill(OpenFluxStyle.accent).frame(width: 11, height: 11)
                Text("OPENFLUX")
                    .font(.system(size: 17, weight: .bold)).tracking(2)
                Spacer()
            }
            .padding(.top, 12)
            Text("Поддержка")
                .font(.system(size: 28, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            if !model.error.isEmpty {
                Text(model.error).font(.caption).foregroundColor(.red)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.messages) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.sender == "client" ? "Вы" : "Поддержка OpenFlux")
                                .font(.caption.bold()).foregroundColor(OpenFluxStyle.orange)
                            Text(message.body).textSelection(.enabled)
                            if let link = firstHTTPSLink(message.body) {
                                Link("Открыть ссылку", destination: link)
                                    .font(.subheadline.bold()).foregroundColor(OpenFluxStyle.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: message.sender == "client" ? .trailing : .leading)
                        .padding(12)
                        .background(OpenFluxStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenFluxStyle.border))
                    }
                }
                .padding()
            }
            TextField("Ваше сообщение", text: $draft)
                .padding(15)
                .background(OpenFluxStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenFluxStyle.border))
                .onChange(of: draft) { value in
                    model.resetPendingSend()
                    if value.count > 500 { draft = String(value.prefix(500)) }
                }
                .disabled(password.isEmpty)
            Button(model.sending ? "Отправляем…" : "ОТПРАВИТЬ") {
                let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { if await model.send(password: password, body: body) { draft = "" } }
            }
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity).frame(height: 52)
            .background(OpenFluxStyle.accent, in: RoundedRectangle(cornerRadius: 15))
            .disabled(password.isEmpty || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.sending)
        }
        .padding(.horizontal, 24)
        .foregroundColor(.white)
        .background(OpenFluxStyle.background.ignoresSafeArea())
        .onAppear { model.start(password: password) }
        .onChange(of: password) { newPassword in
            model.stop()
            model.start(password: newPassword)
        }
        .onDisappear { model.stop() }
    }

    private func firstHTTPSLink(_ text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
            .first(where: { $0.scheme?.lowercased() == "https" && $0.host != nil })
    }
}
