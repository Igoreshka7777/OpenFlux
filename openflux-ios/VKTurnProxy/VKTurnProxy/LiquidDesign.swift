import SwiftUI
import NetworkExtension

struct LiquidCabinetButton: View {
    var body: some View {
        Link(destination: URL(string: "https://open-flux.ru/account")!) {
            HStack { Image(systemName: "person"); Text("Личный кабинет"); Spacer(); Image(systemName: "chevron.right") }
                .font(.system(size: 14, weight: .medium)).foregroundColor(Color(red: 1, green: 0.89, blue: 0.77))
                .padding(16).frame(maxWidth: .infinity)
                .background(OpenFluxStyle.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(OpenFluxStyle.orange.opacity(0.45)))
        }.buttonStyle(.plain)
    }
}

struct LiquidNavigation: View {
    var body: some View {
        HStack {
            navIcon("Главная", "house.fill").foregroundColor(OpenFluxStyle.orange)
            NavigationLink(destination: LiquidSection(kind: "Подписка")) { navIcon("Подписка", "crown") }
            NavigationLink(destination: LiquidSection(kind: "Рефералы")) { navIcon("Рефералы", "person.2") }
            NavigationLink(destination: SettingsView()) { navIcon("Настройки", "gearshape") }
        }.foregroundColor(OpenFluxStyle.muted).padding(.vertical, 12)
    }
    private func navIcon(_ name: String, _ icon: String) -> some View {
        VStack(spacing: 5) { Image(systemName: icon).font(.system(size: 18)); Text(name).font(.system(size: 9)) }.frame(maxWidth: .infinity)
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
                Circle().fill(RadialGradient(colors: [Color(red: 0.06, green: 0.03, blue: 0.02), Color(red: 0.15, green: 0.07, blue: 0.03), Color(red: 0.46, green: 0.19, blue: 0.02)], center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: 260))
                LiquidWave(level: fill, phase: phase)
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.76, blue: 0.2), Color(red: 1, green: 0.39, blue: 0), Color(red: 0.39, green: 0.09, blue: 0)], startPoint: .top, endPoint: .bottom))
                    .clipShape(Circle())
                LiquidWave(level: fill, phase: phase)
                    .stroke(Color(red: 1, green: 0.85, blue: 0.49), lineWidth: 1.5).clipShape(Circle())
                LiquidWave(level: fill, phase: phase + 1.2).stroke(Color.orange.opacity(0.8), lineWidth: 1).clipShape(Circle())
                Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.25), .clear], center: .init(x: 0.55, y: 0.65), startRadius: 0, endRadius: 170))
                Canvas { context, size in
                    for i in 1...35 {
                        let x = size.width * (0.5 + sin(Double(i) * 2.7) * 0.39)
                        let y = size.height * (0.5 + sin(Double(i) * 4.3) * 0.39)
                        if y > size.height * (1-fill) + 10 {
                            let r = CGFloat(i % 3 + 1)
                            context.stroke(Path(ellipseIn: CGRect(x:x,y:y,width:r*2,height:r*2)),with:.color(.yellow.opacity(0.28)),lineWidth:0.7)
                        }
                    }
                }.clipShape(Circle())
                Circle().stroke(OpenFluxStyle.orange.opacity(0.3), lineWidth: 10).blur(radius: 8)
                Circle().inset(by: 5).stroke(Color.orange.opacity(0.7), lineWidth: 0.7)
                Circle().stroke(LinearGradient(colors: [Color(red: 1, green: 0.94, blue: 0.7), OpenFluxStyle.orange, Color(red: 0.55, green: 0.19, blue: 0.02)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                Ellipse().fill(LinearGradient(colors: [.white.opacity(0.17), .clear], startPoint: .top, endPoint: .bottom)).frame(width: 160, height: 65).offset(x: -32, y: -83).rotationEffect(.degrees(-18))
                VStack(spacing: 9) {
                    Image(systemName: "power").font(.system(size: 46, weight: .light))
                    Text(status).font(.system(size: 16, weight: .regular))
                    Text(daysLabel).font(.system(size: 23, weight: .medium))
                }.offset(y: 20).foregroundColor(Color(red: 1, green: 0.92, blue: 0.79)).shadow(color: .black.opacity(0.35), radius: 3, y: 1)
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

struct LiquidStats: View {
    @ObservedObject private var store = ServerStore.shared
    @ObservedObject private var monitor = SubscriptionMonitor.shared
    @State private var balance: String = "— ₽"
    private var days: String {
        guard let access = monitor.entries[store.activeServer.csqttPassword]?.status else { return "—" }
        guard access.state == "active" else { return "Не активна" }
        return access.daysRemaining.map { "\($0) дн." } ?? "Без лимита"
    }
    var body: some View {
        HStack(spacing: 10) {
            NavigationLink(destination: LiquidSection(kind: "Подписка")) { stat("Подписка",days,"осталось","crown") }
            NavigationLink(destination: LiquidSection(kind: "Рефералы")) { stat("Бонусы",balance,"на балансе","gift") }
        }.buttonStyle(.plain).task(id: store.activeServer.csqttPassword) {
            balance = "— ₽"
            guard !store.activeServer.csqttPassword.isEmpty else { return }
            if let summary = try? await ReferralAPI.fetch(password: store.activeServer.csqttPassword) {
                let formatter = NumberFormatter(); formatter.maximumFractionDigits = 2; formatter.locale = Locale(identifier: "ru_RU"); formatter.numberStyle = .decimal
                balance = (formatter.string(from: NSDecimalNumber(decimal: Decimal(summary.balance)/100)) ?? "—") + " ₽"
            }
        }
    }
    private func stat(_ title:String,_ value:String,_ caption:String,_ icon:String) -> some View {
        HStack(alignment:.top,spacing:8) {
            Image(systemName:icon).font(.system(size:15)).foregroundColor(OpenFluxStyle.orange)
            VStack(alignment:.leading,spacing:3) {
                Text(title).font(.system(size:11)).foregroundColor(OpenFluxStyle.muted)
                Text(value).font(.system(size:19)).foregroundColor(Color(red:1,green:0.89,blue:0.77))
                Text(caption).font(.system(size:10)).foregroundColor(OpenFluxStyle.muted)
            }
            Spacer(minLength:0)
        }.padding(12).frame(maxWidth:.infinity).background(OpenFluxStyle.surface,in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(OpenFluxStyle.orange.opacity(0.17)))
    }
}
