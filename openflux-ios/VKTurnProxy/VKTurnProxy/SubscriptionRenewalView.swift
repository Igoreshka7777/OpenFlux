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
    @State private var dismissedPresentation: Int?
    private var password: String { store.activeServer.useCsqtt ? store.activeServer.csqttPassword : "" }
    private var entry: SubscriptionMonitor.Entry? { monitor.entries[password] }
    private var presented: Binding<Bool> {
        Binding(get: { entry?.status.expired == true && entry?.presentation != dismissedPresentation },
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
            .fullScreenCover(isPresented: presented) {
                SubscriptionRenewalView(password: password) { dismissedPresentation = entry?.presentation }
            }
    }
}

struct SubscriptionRenewalView: View {
    let password: String
    let onClose: () -> Void
    @State private var checking = false
    @State private var message = ""
    @State private var loadFailed = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Назад", action: onClose).foregroundColor(OpenFluxStyle.orange)
                Spacer()
                Text("Подписка").font(.headline)
            }.padding(.horizontal, 20).padding(.top, 16)
            if loadFailed {
                VStack(alignment: .leading, spacing: 20) {
                    Spacer()
                    Text("Подписка закончилась").font(.largeTitle.bold())
                    Text("Продлите доступ через администратора. Если интернет недоступен, подключитесь к Wi-Fi или мобильной сети.")
                        .foregroundColor(OpenFluxStyle.muted)
                    Link("Продлить в Telegram ↗", destination: URL(string: "https://t.me/Igorekk777")!)
                        .font(.headline).foregroundColor(OpenFluxStyle.orange)
                    Link("Написать ВКонтакте ↗", destination: URL(string: "https://vk.ru/id39833875")!)
                        .font(.headline).foregroundColor(OpenFluxStyle.orange)
                    Spacer()
                }.padding(26)
            } else {
                SubscriptionRenewalWebView(onFailure: { loadFailed = true })
            }
            if !message.isEmpty { Text(message).font(.footnote).foregroundColor(OpenFluxStyle.muted).padding(.horizontal, 20) }
            Button {
                checking = true
                Task {
                    let status = await SubscriptionMonitor.shared.refresh(password: password)
                    checking = false
                    if let status = status {
                        message = status.expired ? "Продление ещё не подтверждено. Свяжитесь с администратором." : ""
                        if status.state == "active" { onClose() }
                    } else {
                        message = "Не удалось проверить подписку. Проверьте интернет и повторите."
                    }
                }
            } label: {
                Text(checking ? "Проверяем…" : "Я продлил — проверить доступ")
                    .font(.subheadline.bold()).frame(maxWidth: .infinity).padding(16)
                    .background(OpenFluxStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            }.disabled(checking).padding(.horizontal, 16).padding(.bottom, 12)
        }
        .foregroundColor(.white)
        .background(OpenFluxStyle.background.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}

private struct SubscriptionRenewalWebView: UIViewRepresentable {
    let onFailure: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onFailure: onFailure) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 0.035, green: 0.035, blue: 0.04, alpha: 1)
        var request = URLRequest(url: SubscriptionAPI.renewalURL)
        request.timeoutInterval = 12
        view.load(request)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        let onFailure: () -> Void
        init(onFailure: @escaping () -> Void) { self.onFailure = onFailure }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url == SubscriptionAPI.renewalURL { decisionHandler(.allow); return }
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated && ["https://t.me/Igorekk777", "https://vk.ru/id39833875"].contains(url.absoluteString) {
                UIApplication.shared.open(url)
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { onFailure() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { onFailure() }
        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
                decisionHandler(.cancel); onFailure()
            } else { decisionHandler(.allow) }
        }
    }
}
