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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if password.isEmpty {
                    Text("Добавьте личную ссылку подключения в настройках, чтобы увидеть баланс и приглашения.")
                        .foregroundColor(OpenFluxStyle.muted)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ВАШ БАЛАНС").font(.system(size: 12, weight: .bold)).tracking(2)
                        Text(summary.map { money($0.balance) } ?? "— ₽")
                            .font(.system(size: 60, weight: .heavy, design: .rounded))
                            .minimumScaleFactor(0.45).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Доступно бонусных рублей").font(.subheadline).foregroundColor(Color(red: 0.88, green: 0.82, blue: 0.76))
                        if let data = summary, data.held > 0 {
                            Text("В обработке: \(money(data.held))").font(.caption).foregroundColor(OpenFluxStyle.muted)
                        }
                        if !error.isEmpty && summary != nil {
                            Text("Показаны последние полученные данные").font(.caption)
                        }
                    }
                    .foregroundColor(OpenFluxStyle.orange).padding(24)
                    .background(Color(red: 0.13, green: 0.10, blue: 0.06), in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(OpenFluxStyle.orange.opacity(0.65)))
                    OpenFluxCard {
                        HStack {
                            Text("Приглашено друзей")
                            Spacer()
                            Text(summary.map { String($0.count) } ?? "—")
                                .font(.system(size: 32, weight: .bold)).foregroundColor(OpenFluxStyle.orange)
                        }
                    }
                    OpenFluxCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Ваша реферальная ссылка").font(.headline)
                            Text("Приглашайте друзей по этой ссылке. Здесь появятся ваши бонусы за их оплаты.")
                                .font(.subheadline).foregroundColor(OpenFluxStyle.muted)
                            if let data = summary {
                                Text(data.url).font(.subheadline).foregroundColor(OpenFluxStyle.orange).textSelection(.enabled)
                                Button {
                                    UIPasteboard.general.string = data.url; copied = true
                                } label: {
                                    Text(copied ? "Ссылка скопирована ✓" : "Копировать ссылку")
                                        .font(.system(size: 16, weight: .bold)).frame(maxWidth: .infinity).padding(16)
                                        .background(OpenFluxStyle.orange, in: RoundedRectangle(cornerRadius: 16))
                                }.buttonStyle(.plain)
                                Button { sharing = true } label: {
                                    Text("Поделиться").font(.system(size: 16, weight: .semibold))
                                        .frame(maxWidth: .infinity).padding(16)
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(OpenFluxStyle.border))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if !error.isEmpty { Text(error).font(.subheadline).foregroundColor(Color(red: 1, green: 0.70, blue: 0.65)) }
                    Button { refresh += 1 } label: {
                        HStack {
                            if loading { ProgressView().tint(OpenFluxStyle.orange) }
                            Text(loading ? "Обновляем…" : "Обновить данные")
                        }.frame(maxWidth: .infinity).padding(16)
                            .background(OpenFluxStyle.surface, in: RoundedRectangle(cornerRadius: 16))
                    }.disabled(loading).buttonStyle(.plain)
                }
            }.padding(24)
        }
        .background(OpenFluxStyle.background.ignoresSafeArea())
        .foregroundColor(.white)
        .navigationTitle("Реферальная программа").navigationBarTitleDisplayMode(.inline)
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
