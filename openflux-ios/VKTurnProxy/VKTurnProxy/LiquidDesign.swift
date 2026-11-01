import SwiftUI
import NetworkExtension

struct LiquidCabinetButton: View {
    var body: some View {
        Link(destination: URL(string: "https://open-flux.ru/account")!) {
            HStack { Image(systemName: "person"); Text("Личный кабинет"); Spacer(); Image(systemName: "chevron.right") }
                .font(.system(size: 14, weight: .medium)).foregroundColor(Color(red: 1, green: 0.89, blue: 0.77))
                .padding(16).frame(maxWidth: .infinity)
                .background(LiquidTheme.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(OpenFluxStyle.border))
        }.buttonStyle(.plain)
    }
}

struct LiquidNavigation: View {
    var body: some View {
        HStack {
            navIcon("Главная", "house.fill").foregroundColor(OpenFluxStyle.orange)
            NavigationLink(destination: LiquidSection(kind: "Подписка")) { navIcon("Подписка", "crown") }
            NavigationLink(destination: LiquidSection(kind: "Рефералы")) { navIcon("Рефералы", "person.2") }
            NavigationLink(destination: LiquidSettingsView()) { navIcon("Настройки", "gearshape") }
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
                    LiquidReferralsView(password: store.activeServer.csqttPassword)
                } else {
                    OpenFluxCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("OpenFlux для Android и iPhone").font(.title2)
                            Text("Установка приложения и управление устройствами доступны на сайте.").foregroundColor(OpenFluxStyle.muted)
                            LiquidCabinetButton()
                        }
                    }
                    NavigationLink("Ссылка подключения →", destination: LiquidSettingsView())
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
        ZStack {
            LiquidGlass(level: fill)
            VStack(spacing: 7) {
                Image(systemName:"power").font(.system(size:43,weight:.light))
                Text(status).font(.system(size:17,weight:.medium))
                Text(daysLabel).font(.system(size:22,weight:.semibold))
            }.foregroundColor(Color(red:1,green:235/255,blue:213/255)).offset(y:30)
        }.frame(maxWidth:370).aspectRatio(1,contentMode:.fit)
            .contentShape(Circle()).accessibilityLabel(connected ? "Отключить VPN" : "Подключить VPN")
            .task(id:store.activeServer.csqttPassword) { _ = await monitor.refresh(password:store.activeServer.csqttPassword) }
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
        VStack(alignment:.leading,spacing:5) {
            Image(systemName:icon).font(.system(size:23)).foregroundColor(OpenFluxStyle.orange).padding(.bottom,3)
            Text(title).font(.system(size:13)).foregroundColor(.white)
            Text(value).font(.system(size:24,weight:.medium)).foregroundColor(Color(red:1,green:235/255,blue:213/255))
            Text(caption).font(.system(size:11)).foregroundColor(OpenFluxStyle.muted)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(16)
            .background(LiquidTheme.card,in:RoundedRectangle(cornerRadius:17))
            .overlay(RoundedRectangle(cornerRadius:17).stroke(OpenFluxStyle.border,lineWidth:0.8))
    }
}
