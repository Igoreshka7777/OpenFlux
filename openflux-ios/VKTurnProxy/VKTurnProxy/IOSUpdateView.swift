import SwiftUI
import UIKit

@MainActor
final class IOSUpdateMonitor: ObservableObject {
    static let shared = IOSUpdateMonitor()
    @Published private(set) var policy = IOSUpdateAPI.cached
    var required: Bool { policy?.required(for: IOSUpdateAPI.build) == true }
    var showUpdate: Bool { policy?.available(for: IOSUpdateAPI.build) == true }
    func refresh() async {
        policy = await IOSUpdateAPI.fetch(force: true)
        // Keep the VPN available while the user downloads the update.
    }
}

struct IOSUpdateView: View {
    @ObservedObject private var monitor = IOSUpdateMonitor.shared
    @State private var checking = false
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
                            let url = IOSUpdateAPI.installationURL(Bundle.main.object(forInfoDictionaryKey: "OpenFluxUpdateURL") as? String)
                            UIApplication.shared.open(url)
                        } label: {
                            Text("Установить обновление →").font(.headline).frame(maxWidth: .infinity).padding(18)
                                .background(OpenFluxStyle.orange, in: RoundedRectangle(cornerRadius: 14))
                        }
                        Text("Подготовка обычно занимает около 5 минут. Подтвердите установку на iPhone. Приложение удалять не нужно.").font(.footnote).foregroundColor(OpenFluxStyle.muted)
                    }
                }
                Button(checking ? "Проверяем…" : "Проверить обновление") {
                    checking = true
                    Task { await monitor.refresh(); checking = false }
                }.disabled(checking).foregroundColor(OpenFluxStyle.orange)
                Link("Связаться с администратором ↗", destination: URL(string: "https://t.me/Igorekk777")!).foregroundColor(OpenFluxStyle.muted)
            }.padding(24)
        }.foregroundColor(.white).background(OpenFluxStyle.background.ignoresSafeArea()).interactiveDismissDisabled(true)
    }
}
