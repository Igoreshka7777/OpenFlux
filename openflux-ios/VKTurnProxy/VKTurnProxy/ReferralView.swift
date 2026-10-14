import SwiftUI
import UIKit

private struct ReferralSummary: Decodable {
    let schema: Int
    let currency: String
    let balance: Int64
    let held: Int64
    let count: Int
    let url: String
    enum CodingKeys: String, CodingKey {
        case schema, currency
        case balance = "balance_kopecks", held = "held_kopecks"
        case count = "referrals_count", url = "referral_url"
    }
    var valid: Bool {
        schema == 1 && currency == "RUB" && count >= 0 &&
        url.range(of: #"^https://openfluxvpn\.ru/r/[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }
}

private final class ReferralRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

private enum ReferralAPI {
    static let session = URLSession(configuration: .ephemeral, delegate: ReferralRedirectPolicy(), delegateQueue: nil)
    static func fetch(password: String) async throws -> ReferralSummary {
        var request = URLRequest(url: URL(string: "https://openfluxvpn.ru/api/client/referrals")!)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(password)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let result = try JSONDecoder().decode(ReferralSummary.self, from: data)
        guard result.valid else { throw URLError(.cannotParseResponse) }
        return result
    }
}

struct ReferralView: View {
    let password: String
    @State private var summary: ReferralSummary?
    @State private var loading = false
    @State private var error = ""
    @State private var copied = false
    @State private var sharing = false
    @State private var refresh = 0
    private func money(_ kopecks: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return (formatter.string(from: NSDecimalNumber(decimal: Decimal(kopecks) / 100)) ?? "—") + " ₽"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Реферальная программа").font(.system(size: 22, weight: .bold))
            if password.isEmpty {
                Text("Добавьте личную ссылку подключения, чтобы увидеть баланс и приглашения.")
                    .foregroundColor(OpenFluxStyle.muted)
            } else {
                Text("Ваш баланс").foregroundColor(OpenFluxStyle.muted)
                Text(summary.map { money($0.balance) } ?? "— ₽")
                    .font(.system(size: 54, weight: .heavy, design: .rounded))
                    .foregroundColor(OpenFluxStyle.orange)
                    .minimumScaleFactor(0.4).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let data = summary, data.held > 0 {
                    Text("В обработке: \(money(data.held))").font(.caption).foregroundColor(OpenFluxStyle.muted)
                }
                HStack {
                    Text("Приглашено друзей").foregroundColor(OpenFluxStyle.muted)
                    Spacer()
                    Text(summary.map { String($0.count) } ?? "—").font(.system(size: 24, weight: .bold))
                }
                Rectangle().fill(OpenFluxStyle.orange.opacity(0.75)).frame(height: 1)
                Text("Ваша реферальная ссылка").font(.subheadline).foregroundColor(OpenFluxStyle.muted)
                if let data = summary {
                    Text(data.url).font(.system(size: 14)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(OpenFluxStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(OpenFluxStyle.border))
                    HStack(spacing: 10) {
                        Button { UIPasteboard.general.string = data.url; copied = true } label: {
                            Text(copied ? "Скопировано ✓" : "Копировать")
                                .font(.system(size: 14, weight: .bold)).frame(maxWidth: .infinity, minHeight: 48)
                                .background(OpenFluxStyle.orange, in: RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                        Button { sharing = true } label: {
                            Text("Поделиться").font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(OpenFluxStyle.orange))
                        }.buttonStyle(.plain)
                    }
                }
                if !error.isEmpty {
                    if summary != nil { Text("Показаны последние полученные данные").font(.caption).foregroundColor(OpenFluxStyle.muted) }
                    Text(error).font(.caption).foregroundColor(Color(red: 1, green: 0.70, blue: 0.65))
                }
                Button { refresh += 1 } label: {
                    HStack {
                        if loading { ProgressView().tint(OpenFluxStyle.orange) }
                        Text(loading ? "Обновляем…" : "Обновить баланс").font(.caption)
                    }.frame(maxWidth: .infinity, minHeight: 32).foregroundColor(OpenFluxStyle.muted)
                }.disabled(loading).buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .background(LinearGradient(colors: [Color(red: 0.09, green: 0.08, blue: 0.09), Color(red: 0.19, green: 0.125, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(OpenFluxStyle.orange))
        .foregroundColor(.white)
        .task(id: "\(password):\(refresh)") {
            guard !password.isEmpty else { summary = nil; return }
            loading = true; error = ""
            defer { loading = false }
            do { summary = try await ReferralAPI.fetch(password: password) }
            catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = "Не удалось обновить данные. Проверьте соединение и повторите." } }
        }
        .sheet(isPresented: $sharing) {
            if let data = summary { ShareSheet(activityItems: ["Присоединяйся к OpenFlux: \(data.url)"]) }
        }
    }
}
