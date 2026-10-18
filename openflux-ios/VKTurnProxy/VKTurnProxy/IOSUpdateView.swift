import SwiftUI
import UIKit

@MainActor
final class IOSUpdateMonitor: ObservableObject {
    static let shared = IOSUpdateMonitor()
    @Published private(set) var policy = IOSUpdateAPI.cached
    @Published private(set) var deferredBuild = 0
    var required: Bool { policy?.required(for: IOSUpdateAPI.build) == true }
    var showUpdate: Bool { required || (policy?.available(for: IOSUpdateAPI.build) == true && policy?.latestBuild != deferredBuild) }
    func refresh() async {
        policy = await IOSUpdateAPI.fetch(force: true)
        // Keep the VPN available while the user downloads the update.
    }
    func deferOptional() { if !required { deferredBuild = policy?.latestBuild ?? 0 } }
}

struct IOSUpdateView: View {
    @ObservedObject private var monitor = IOSUpdateMonitor.shared
    @State private var checking = false
    @State private var openingInstall = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("●  OPENFLUX").font(.system(size: 23, weight: .bold)).tracking(3).foregroundColor(OpenFluxStyle.orange)
                Spacer(minLength: 30)
                Text("01  /  ОБНОВЛЕНИЕ").font(.caption.bold()).tracking(2).foregroundColor(OpenFluxStyle.orange)
                Text("Новая версия.\nТот же OpenFlux.").font(.system(size: 36, weight: .bold))
                OpenFluxCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Сборка \(monitor.policy?.latestBuild ?? 0)").font(.title2.bold())
                        Text(monitor.policy?.message ?? "Доступно обновление OpenFlux.").foregroundColor(OpenFluxStyle.muted)
                        Text("Сервер подготовит новую версию с вашим сохранённым сертификатом. Повторная регистрация и покупка сертификата не нужны.").font(.subheadline).foregroundColor(OpenFluxStyle.muted)
                        Button {
                            openingInstall = true
                            Task { @MainActor in
                                defer { openingInstall = false }
                                let page = IOSUpdateAPI.installationURL(Bundle.main.object(forInfoDictionaryKey: "OpenFluxUpdateURL") as? String)
                                if let install = await IOSUpdateAPI.readyInstallationURL(page) {
                                    TunnelManager.shared.rememberConnectionForUpdate()
                                    if !(await UIApplication.shared.open(install, options: [:])) {
                                        await UIApplication.shared.open(page, options: [:])
                                    }
                                } else {
                                    TunnelManager.shared.rememberConnectionForUpdate()
                                    await UIApplication.shared.open(page, options: [:])
                                }
                            }
                        } label: {
                            Text(openingInstall ? "Проверяем готовность…" : "Установить обновление →").font(.headline).frame(maxWidth: .infinity).padding(18)
                                .background(OpenFluxStyle.orange, in: RoundedRectangle(cornerRadius: 14))
                        }.disabled(openingInstall)
                        Text("Готовое обновление устанавливается сразу после вашего подтверждения. Если файл ещё подписывается, откроется страница подготовки. Приложение удалять не нужно.").font(.footnote).foregroundColor(OpenFluxStyle.muted)
                        Text("Во время подготовки OpenFlux сохраняет VPN-соединение. При установке iOS может его прервать. После обновления откройте OpenFlux — приложение попробует восстановить ранее включённый VPN.").font(.footnote).foregroundColor(OpenFluxStyle.muted)
                    }
                }
                Button(checking ? "Проверяем…" : "Проверить обновление") {
                    checking = true
                    Task { await monitor.refresh(); checking = false }
                }.disabled(checking).foregroundColor(OpenFluxStyle.orange)
                if !monitor.required {
                    Button("Позже") { monitor.deferOptional() }
                        .disabled(openingInstall).foregroundColor(OpenFluxStyle.muted)
                }
                Link("Связаться с администратором ↗", destination: URL(string: "https://t.me/Igorekk777")!).foregroundColor(OpenFluxStyle.muted)
            }.padding(24)
        }.foregroundColor(.white).background(OpenFluxStyle.background.ignoresSafeArea()).interactiveDismissDisabled(monitor.required || openingInstall)
    }
}
