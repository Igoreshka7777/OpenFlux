import SwiftUI
import NetworkExtension

struct LiquidCabinetButton: View {
    var body: some View {
        Link(destination: URL(string: "https://open-flux.ru/account")!) {
            HStack { Image(systemName: "person"); Text("Личный кабинет"); Spacer(); Image(systemName: "arrow.up.right") }
                .font(.system(size: 17, weight: .medium)).foregroundColor(Color(red: 1, green: 0.89, blue: 0.77))
                .padding(20).frame(maxWidth: .infinity)
                .background(OpenFluxStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(OpenFluxStyle.orange.opacity(0.45)))
        }.buttonStyle(.plain)
    }
}

struct LiquidNavigation: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                Text("Главная").foregroundColor(OpenFluxStyle.orange)
                NavigationLink("Подписка", destination: LiquidSection(kind: "Подписка"))
                NavigationLink("Рефералы", destination: LiquidSection(kind: "Рефералы"))
                NavigationLink("Приложения", destination: LiquidSection(kind: "Приложения"))
                NavigationLink("Настройки", destination: SettingsView())
            }.font(.system(size: 14)).foregroundColor(Color(red: 1, green: 0.89, blue: 0.77)).padding(.vertical, 12)
        }
    }
}

struct LiquidSection: View {
    let kind: String
    @ObservedObject private var store = ServerStore.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text(kind).font(.largeTitle); Spacer(); OpenFluxSupportButton() }
                if kind == "Подписка" {
                    SubscriptionSettingsCard(password: store.activeServer.csqttPassword)
                    LiquidCabinetButton()
                } else if kind == "Рефералы" {
                    ReferralView(password: store.activeServer.csqttPassword)
                } else {
                    OpenFluxCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("OpenFlux для Android и iPhone").font(.title2)
                            Text("Установка приложения и управление устройствами доступны на сайте.").foregroundColor(OpenFluxStyle.muted)
                            LiquidCabinetButton()
                        }
                    }
                    NavigationLink("Ссылка подключения →", destination: SettingsView())
                }
            }.padding(24)
        }.foregroundColor(.white).background(OpenFluxBackdrop()).navigationBarHidden(false).navigationBarTitleDisplayMode(.inline)
    }
}

struct LiquidJournalView: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack { Text("Журнал приложения").font(.title2); Spacer(); OpenFluxSupportButton() }.padding(.horizontal, 20)
            LogsView(tunnel: TunnelManager.shared, embedded: true)
        }.foregroundColor(.white).background(OpenFluxBackdrop()).navigationBarHidden(false).navigationBarTitleDisplayMode(.inline)
    }
}

struct LiquidPowerControl: View {
    let status: String
    let connected: Bool
    @ObservedObject private var store = ServerStore.shared
    @ObservedObject private var monitor = SubscriptionMonitor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var access: SubscriptionAccess? { monitor.entries[store.activeServer.csqttPassword]?.status }
    private var fill: Double {
        guard let access = access else { return 0 }
        guard access.state == "active" else { return 0 }
        guard let days = access.daysRemaining else { return 1 }
        return min(1, max(0, Double(days) / 30))
    }
    private var daysLabel: String {
        guard !store.activeServer.csqttPassword.isEmpty else { return "Добавьте доступ" }
        guard let access = access else { return "Срок уточняется" }
        if access.state == "disabled" { return "Доступ отключён" }
        if access.state == "limit" { return "Лимит исчерпан" }
        if access.expired { return "Срок закончился" }
        guard let days = access.daysRemaining else { return "Без ограничения срока" }
        return "\(days) дн."
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.8) / 4.8 * .pi * 2
            ZStack {
                Circle().fill(Color(red: 0.09, green: 0.04, blue: 0.02))
                LiquidWave(level: fill, phase: phase)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.76, blue: 0.2), Color(red: 1, green: 0.39, blue: 0), Color(red: 0.39, green: 0.09, blue: 0)], startPoint: .top, endPoint: .bottom))
                    .clipShape(Circle())
                LiquidWave(level: fill, phase: phase)
                    .stroke(Color(red: 1, green: 0.85, blue: 0.49), lineWidth: 1.5).clipShape(Circle())
                Circle().stroke(OpenFluxStyle.orange.opacity(0.14), lineWidth: 14).blur(radius: 6)
                Circle().stroke(LinearGradient(colors: [Color(red: 1, green: 0.94, blue: 0.7), OpenFluxStyle.orange, Color(red: 0.55, green: 0.19, blue: 0.02)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                Ellipse().fill(LinearGradient(colors: [.white.opacity(0.17), .clear], startPoint: .top, endPoint: .bottom)).frame(width: 160, height: 65).offset(x: -32, y: -83).rotationEffect(.degrees(-18))
                VStack(spacing: 14) {
                    Image(systemName: "power").font(.system(size: 46, weight: .light))
                    Text(status).font(.system(size: 19, weight: .medium))
                    Text(daysLabel).font(.system(size: 24, weight: .semibold))
                }.foregroundColor(Color(red: 1, green: 0.92, blue: 0.79)).shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            }.padding(9)
        }.frame(maxWidth: 320).aspectRatio(1, contentMode: .fit)
            .contentShape(Circle()).accessibilityLabel(connected ? "Отключить VPN" : "Подключить VPN")
            .task(id: store.activeServer.csqttPassword) { _ = await monitor.refresh(password: store.activeServer.csqttPassword) }
    }
}

private struct LiquidWave: Shape {
    let level: Double
    let phase: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.height * (1 - level)
        path.move(to: CGPoint(x: 0, y: rect.height))
        for step in 0...100 {
            let x = rect.width * CGFloat(step) / 100
            let wave = sin(Double(x / rect.width) * .pi * 2 + phase) * Double(rect.height) * 0.017
            path.addLine(to: CGPoint(x: x, y: y + CGFloat(wave)))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height)); path.closeSubpath()
        return path
    }
}
