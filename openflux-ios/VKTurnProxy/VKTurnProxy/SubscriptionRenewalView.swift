import SwiftUI
import UIKit
import WebKit
import NetworkExtension

@MainActor
final class SubscriptionMonitor: ObservableObject {
    static let shared = SubscriptionMonitor()
    struct Entry {
        let status: SubscriptionAccess
        let presentation: Int
    }
    @Published private(set) var entries: [String: Entry] = [:]
    private var revisions: [String: Int] = [:]

    @discardableResult
    func refresh(password: String, presentAgain: Bool = false) async -> SubscriptionAccess? {
        let revision = (revisions[password] ?? 0) + 1
        revisions[password] = revision
        guard let status = await SubscriptionAPI.fetch(password: password), !Task.isCancelled,
              revisions[password] == revision else { return nil }
        let old = entries[password]
        let changed = status.expired && (presentAgain || old?.status.expired != true || old?.status.expiresAt != status.expiresAt)
        let entry = Entry(status: status, presentation: (old?.presentation ?? 0) + (changed ? 1 : 0))
        entries[password] = entry
        if status.expired, let expiry = status.expiresAt {
            await SubscriptionNotices.show(password: password, expiry: expiry)
            guard revisions[password] == revision else { return status }
            TunnelManager.shared.stopExpiredSubscription(password: password)
        } else if status.state == "active" {
            SubscriptionNotices.clear(password: password)
        }
        return status
    }
}

/// Owns its observations below the NavigationView, preserving Settings/chat state.
struct SubscriptionPresentationHost: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = ServerStore.shared
    @ObservedObject private var monitor = SubscriptionMonitor.shared
    @ObservedObject private var updates = IOSUpdateMonitor.shared
    @State private var dismissedPresentation: Int?
    private var password: String { store.activeServer.useCsqtt ? store.activeServer.csqttPassword : "" }
    private var entry: SubscriptionMonitor.Entry? { monitor.entries[password] }
    private var presented: Binding<Bool> {
        Binding(get: { updates.showUpdate || (entry?.status.expired == true && entry?.presentation != dismissedPresentation) },
                set: { if !$0 { dismissedPresentation = entry?.presentation } })
    }

    var body: some View {
        Color.clear
            .onChange(of: password) { _ in dismissedPresentation = nil }
            .onChange(of: scenePhase) { phase in if phase == .active { dismissedPresentation = nil } }
            .task(id: password + (scenePhase == .active ? ":active" : ":inactive")) {
                guard scenePhase == .active, !password.isEmpty else { return }
                let watchedPassword = password
                while !Task.isCancelled {
                    await monitor.refresh(password: watchedPassword)
                    do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                }
            }
            .task(id: scenePhase == .active) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await updates.refresh()
                    do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                }
            }
            .fullScreenCover(isPresented: presented) {
                if updates.showUpdate {
                    IOSUpdateView()
                } else {
                    SubscriptionRenewalView(password: password) { dismissedPresentation = entry?.presentation }
                }
            }
    }
}

struct SubscriptionSettingsCard: View {
    let password: String
    @ObservedObject private var monitor = SubscriptionMonitor.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var checked = false
    @State private var offline = false
    private var status: SubscriptionAccess? { monitor.entries[password]?.status }

    private var summary: String {
        guard !password.isEmpty else { return "Добавьте ссылку подключения" }
        guard let status = status else { return checked ? "Не удалось получить срок" : "Проверяем…" }
        if status.expired { return "Подписка закончилась" }
        if status.state == "disabled" { return "Доступ отключён" }
        if status.state == "limit" { return "Лимит трафика исчерпан" }
        guard status.state == "active" else { return "Срок недоступен" }
        guard let days = status.daysRemaining else { return "Без ограничения срока" }
        return days > 0 ? "Осталось \(days) дн." : "Срок истекает"
    }

    var body: some View {
        OpenFluxCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Подписка").font(.system(size: 18, weight: .bold))
                Text(summary).font(.system(size: 24, weight: .bold)).foregroundColor(OpenFluxStyle.orange)
                if let expiry = status?.expiresAt, expiry > 0 {
                    Text("До " + Self.dateFormat.string(from: Date(timeIntervalSince1970: TimeInterval(expiry))))
                        .font(.caption).foregroundColor(OpenFluxStyle.muted)
                }
                if offline && status != nil {
                    Text("Нет связи с сервером. Последние полученные данные.")
                        .font(.caption).foregroundColor(OpenFluxStyle.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: password + (scenePhase == .active ? ":active" : ":inactive")) {
            guard scenePhase == .active else { return }
            checked = false
            guard !password.isEmpty else { checked = true; return }
            while !Task.isCancelled {
                let result = await monitor.refresh(password: password)
                guard !Task.isCancelled else { return }
                checked = true
                offline = result == nil
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            }
        }
    }

    private static let dateFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "dd.MM.yyyy HH:mm"
        return formatter
    }()
}

struct SubscriptionRenewalView: View {
    let password: String
    let onClose: () -> Void
    @State private var checking = false
    @State private var message = ""
    @State private var showPayment = false

    private func section(_ number: String, _ title: String) -> some View {
        HStack(spacing: 16) {
            Text(number + "  /  " + title).font(.system(size: 11, weight: .bold)).tracking(1)
            Rectangle().fill(OpenFluxStyle.orange.opacity(0.4)).frame(height: 1)
        }.foregroundColor(OpenFluxStyle.orange)
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Назад", action: onClose).foregroundColor(OpenFluxStyle.orange)
                Spacer()
                Text("Подписка").font(.headline)
            }.padding(.horizontal, 20).padding(.top, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("●  OPENFLUX").font(.system(size: 23, weight: .bold)).tracking(3).foregroundColor(OpenFluxStyle.orange)
                    Text("Продлите\nподписку").font(.system(size: 38, weight: .bold))
                    Text("Срок доступа закончился. Вернитесь к подключению за несколько шагов.").foregroundColor(OpenFluxStyle.muted)
                    section("01", "ПРОДЛЕНИЕ")
                    OpenFluxCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Ещё 30 дней с OpenFlux").font(.title3.bold())
                            Text("Ваша подписка уже выбрана. Актуальная цена и реквизиты откроются на следующем экране.").foregroundColor(OpenFluxStyle.muted)
                            Button { showPayment = true } label: {
                                Text("Продлить подписку →").font(.headline).frame(maxWidth: .infinity).padding(18)
                                    .background(LinearGradient(colors: [.orange, OpenFluxStyle.orange], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
                            }
                            Text("После перевода нажмите «Я оплатил». Доступ продлится после подтверждения администратором.").font(.footnote).foregroundColor(OpenFluxStyle.muted)
                        }
                    }
                    section("02", "НУЖНА ПОМОЩЬ")
                    Text("Связаться с администратором").font(.footnote).foregroundColor(OpenFluxStyle.muted)
                    HStack {
                        Link("Telegram ↗", destination: URL(string: "https://t.me/Igorekk777")!)
                        Spacer()
                        Link("ВКонтакте ↗", destination: URL(string: "https://vk.ru/id39833875")!)
                    }.font(.headline).padding(18).background(OpenFluxStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                }.padding(24)
            }
            if !message.isEmpty { Text(message).font(.footnote).foregroundColor(OpenFluxStyle.muted).padding(.horizontal, 20) }
            Button {
                checking = true
                Task {
                    let status = await SubscriptionMonitor.shared.refresh(password: password)
                    checking = false
                    if status?.state == "active" { onClose() }
                    else { message = status == nil ? "Не удалось проверить доступ. Проверьте интернет и повторите." : "Продление ещё не подтверждено. Если уже оплатили, повторно платить не нужно." }
                }
            } label: {
                Text(checking ? "Проверяем…" : "Я оплатил — проверить доступ")
                    .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(16)
                    .background(OpenFluxStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            }.disabled(checking).padding(.horizontal, 16).padding(.bottom, 12)
        }
        .foregroundColor(.white).background(OpenFluxStyle.background.ignoresSafeArea()).interactiveDismissDisabled()
        .fullScreenCover(isPresented: $showPayment) {
            NavigationView {
                OpenFluxAccessPortal(password: password) { link in
                    do {
                        let parsed = try BackupManager.parseConnectionLinkString(link)
                        _ = ConnectionLinkPrompt.apply(parsed)
                        UserDefaults.standard.set(link, forKey: "openFluxConnectionLink")
                        showPayment = false
                        onClose()
                    } catch { message = "Не удалось принять ссылку. Свяжитесь с администратором."; showPayment = false }
                }
                .navigationTitle("Продлить подписку").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) { Button("Назад") { showPayment = false } }
                    ToolbarItem(placement: .navigationBarTrailing) { Link("Помощь ↗", destination: URL(string: "https://t.me/Igorekk777")!) }
                }
            }
        }
    }
}
