import SwiftUI
import UIKit
import NetworkExtension

enum LiquidTheme {
    static let card = LinearGradient(colors:[Color(red:53/255,green:19/255,blue:3/255),Color(red:22/255,green:9/255,blue:3/255),Color(red:44/255,green:16/255,blue:3/255)],startPoint:.topLeading,endPoint:.bottomTrailing)
    static let text = Color(red:1,green:235/255,blue:213/255)
}

private enum LiquidTexture {
    static let image:UIImage? = {
        guard let source=UIImage(named:"LiquidOrb")?.cgImage else {return nil}
        let rect=CGRect(x:Double(source.width)*0.22,y:Double(source.height)*0.48,width:Double(source.width)*0.56,height:Double(source.height)*0.30)
        guard let crop=source.cropping(to:rect) else {return nil}
        return UIImage(cgImage:crop)
    }()
}
struct LiquidGlass: View, Animatable {
    var level: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var animatableData: Double { get { level } set { level = newValue } }
    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/60,paused:reduceMotion || scenePhase != .active)) { timeline in
        let phase=reduceMotion ? 3.8 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:6.8) / 6.8 * .pi * 2
        Canvas { context,size in
            let shell=context.resolve(Image("LiquidEmpty"))
            let full=CGRect(origin:.zero,size:size)
            context.draw(shell,in:full)
            let inner=CGRect(x:size.width*0.14,y:size.height*0.115,width:size.width*0.72,height:size.height*0.72)
            context.clip(to:Path(ellipseIn:inner))
            guard level>0 else {return}
            let target=size.height*(0.115+0.72*(1-min(1,max(0,level))))
            let amplitude=size.height*0.025*min(1,level*8)
            var fluid=Path();var crest=Path()
            fluid.move(to:CGPoint(x:0,y:size.height))
            for step in 0...140 {
                let x=size.width*CGFloat(step)/140
                let y=target+sin(Double(step)/140 * .pi*2+phase)*amplitude
                let point=CGPoint(x:x,y:y)
                fluid.addLine(to:point)
                if step==0 {crest.move(to:point)} else {crest.addLine(to:point)}
            }
            fluid.addLine(to:CGPoint(x:size.width,y:size.height));fluid.closeSubpath()
            context.fill(fluid,with:.radialGradient(Gradient(colors:[Color(red:82/255,green:27/255,blue:0),Color(red:190/255,green:69/255,blue:0),.orange]),center:CGPoint(x:size.width*0.5,y:size.height*0.55),startRadius:0,endRadius:size.width*0.5))
            if let texture=LiquidTexture.image {
                var liquid=context;liquid.clip(to:fluid);liquid.opacity=0.7
                liquid.draw(liquid.resolve(Image(uiImage:texture)),in:full)
            }
            context.stroke(crest,with:.color(.orange.opacity(0.35)),lineWidth:10)
            context.stroke(crest,with:.color(.orange),lineWidth:4)
            context.stroke(crest,with:.color(Color(red:1,green:0.93,blue:0.67)),lineWidth:1)

        }
        }.animation(reduceMotion ? nil : .easeInOut(duration:1.1),value:level)
    }
}

struct LiquidPanel<Content:View>: View {
    @ViewBuilder let content:Content
    var body:some View { VStack(alignment:.leading,spacing:13){content}.padding(16).frame(maxWidth:.infinity,alignment:.leading)
        .background(LiquidTheme.card,in:RoundedRectangle(cornerRadius:17)).overlay(RoundedRectangle(cornerRadius:17).stroke(OpenFluxStyle.border,lineWidth:0.8)) }
}

struct LiquidDiagnosticsView: View {
    @ObservedObject private var store=ServerStore.shared
    @ObservedObject private var tunnel=TunnelManager.shared
    @AppStorage("showVKCommunityCard") private var community=true
    @Environment(\.presentationMode) private var presentation
    @State private var link=""
    @State private var message=""
    @State private var saving=false
    private var editable:Bool { tunnel.status == .disconnected || tunnel.status == .invalid }
    private var workers:Binding<Double> { Binding(get:{Double(store.activeServer.numConnections)},set:{v in
        guard editable else{return};var server=store.activeServer;server.numConnections=Int(v);store.update(server)
    }) }
    private var udp:Binding<Bool> { Binding(get:{store.activeServer.useUDP},set:{v in
        guard editable else{return};var server=store.activeServer;server.useUDP=v;store.update(server)
    }) }
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                HStack { Button {presentation.wrappedValue.dismiss()} label:{Image(systemName:"chevron.left")};Text("Диагностика").font(.system(size:23));Spacer();OpenFluxSupportButton() }.padding(.vertical,12)
                LiquidPanel {
                    Text("Ссылка подключения").font(.system(size:16))
                    TextEditor(text:$link).openFluxEditorBackground().frame(height:90).autocapitalization(.none).disableAutocorrection(true)
                        .padding(8).background(OpenFluxStyle.background,in:RoundedRectangle(cornerRadius:12))
                    HStack {
                        Button("Вставить") {link=UIPasteboard.general.string ?? ""}
                        Spacer()
                        Button(saving ? "Сохраняем…" : "Сохранить") {save()}.disabled(saving || link.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    }.font(.system(size:14))
                    if !message.isEmpty {Text(message).font(.caption).foregroundColor(OpenFluxStyle.muted)}
                }
                LiquidPanel {
                    HStack {Text("Потоки подключения");Spacer();Text("\(store.activeServer.numConnections)").foregroundColor(OpenFluxStyle.orange)}
                    Slider(value:workers,in:9...Double(max(9,max(store.activeServer.numConnections,TunnelConfig.anonConnCap))),step:1).disabled(!editable)
                    Text("Изменения применятся при следующем подключении").font(.caption).foregroundColor(OpenFluxStyle.muted)
                    Toggle("Использовать UDP",isOn:udp).disabled(!editable)
                }
                LiquidPanel { Toggle("Группа ВКонтакте",isOn:$community) }
                NavigationLink(destination:LiquidJournalView()){LiquidPanel{HStack{Label("Журнал приложения",systemImage:"doc.text");Spacer();Image(systemName:"chevron.right")}}}.buttonStyle(.plain)
                LiquidCabinetButton()
                Text("OpenFlux 2.0 · 484").font(.caption).foregroundColor(OpenFluxStyle.muted).padding(.vertical,12)
            }.padding(.horizontal,20)
        }.background(OpenFluxBackdrop()).foregroundColor(LiquidTheme.text).tint(OpenFluxStyle.orange).navigationBarHidden(true)
            .onAppear {link=UserDefaults.standard.string(forKey:"openFluxConnectionLink") ?? ""}
    }
    private func save() {
        saving=true;message="Получаем настройки…"
        Task { @MainActor in
            defer{saving=false}
            do {
                let resolved=try await OpenFluxShortLink.resolve(link.trimmingCharacters(in:.whitespacesAndNewlines))
                let parsed=try BackupManager.parseConnectionLinkString(resolved)
                _ = ConnectionLinkPrompt.apply(parsed)
                UserDefaults.standard.set(resolved,forKey:"openFluxConnectionLink");link=resolved;message="Ссылка сохранена"
            } catch {message="Не удалось сохранить. Проверьте ссылку и интернет."}
        }
    }
}

struct LiquidReferralsView:View {
    let password:String
    @State private var summary:ReferralSummary?
    @State private var message=""
    @State private var sharing=false
    var body:some View {
        VStack(spacing:14) {
            LiquidPanel {
                Text("Бонусный баланс").font(.system(size:13)).foregroundColor(OpenFluxStyle.muted)
                Text(summary.map{NSDecimalNumber(decimal:Decimal($0.balance)/100).stringValue+" ₽"} ?? "— ₽").font(.system(size:34))
                Text("Приглашено друзей: \(summary.map{String($0.count)} ?? "—")").font(.system(size:14))
                if !message.isEmpty {Text(message).font(.caption).foregroundColor(OpenFluxStyle.muted)}
            }
            if let data=summary {
                LiquidPanel {Text(data.url).font(.system(size:12)).textSelection(.enabled)}
                Button {UIPasteboard.general.string=data.url;message="Ссылка скопирована"} label:{LiquidPanel{Text("Копировать ссылку")}}
                Button {sharing=true} label:{LiquidPanel{Text("Пригласить друга")}}
            }
        }.foregroundColor(LiquidTheme.text).buttonStyle(.plain)
            .task(id:password) {guard !password.isEmpty else{return};do{summary=try await ReferralAPI.fetch(password:password)}catch{message="Не удалось обновить данные"}}
            .sheet(isPresented:$sharing){ShareSheet(activityItems:[summary?.url ?? ""])}
    }
}


struct LiquidMiniOrb: View {
    @ObservedObject private var store=ServerStore.shared
    @ObservedObject private var monitor=SubscriptionMonitor.shared
    private var access:SubscriptionAccess? {monitor.entries[store.activeServer.csqttPassword]?.status}
    private var fill:Double {guard let access=access,access.state=="active" else{return 0};return access.daysRemaining.map{min(1,max(0,Double($0)/30))} ?? 1}
    var body:some View {
        ZStack {
            LiquidGlass(level:fill)
            VStack(spacing:5) {
                Text(access == nil ? "—" : "\(Int(fill*100))%").font(.system(size:25,weight:.semibold))
                Text(access?.daysRemaining.map{"\($0) дн."} ?? "Срок уточняется").font(.system(size:13))
            }.foregroundColor(LiquidTheme.text).offset(y:12)
        }.frame(width:168,height:168)
            .task(id:store.activeServer.csqttPassword){_ = await monitor.refresh(password:store.activeServer.csqttPassword)}
    }
}

struct LiquidSettingsView:View {
    @Environment(\.presentationMode) private var presentation
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                HStack {Text("OPENFLUX").font(.system(size:20,weight:.bold));Spacer();OpenFluxSupportButton()}
                LiquidMiniOrb().frame(maxWidth:.infinity)
                Text("Настройки").font(.system(size:29,weight:.semibold)).padding(.bottom,8)
                NavigationLink(destination:LiquidDiagnosticsView()){row("Ссылка подключения","link")}
                NavigationLink(destination:LiquidDiagnosticsView()){row("Диагностика","stethoscope")}
                NavigationLink(destination:LiquidJournalView()){row("Журнал приложения","doc.text")}
                NavigationLink(destination:LiquidSection(kind:"Приложения")){row("Приложения","square.grid.2x2")}
                LiquidPanel {
                    Label("О приложении",systemImage:"info.circle")
                    Text("OpenFlux 2.0 · 484").font(.caption).foregroundColor(OpenFluxStyle.muted)
                }
                LiquidCabinetButton()
            }.padding(.horizontal,20).padding(.top,12).padding(.bottom,16)
        }.safeAreaInset(edge:.bottom) {
            HStack {
                Button {presentation.wrappedValue.dismiss()} label:{Label("Главная",systemImage:"house")}
                Spacer();Label("Настройки",systemImage:"gearshape.fill").foregroundColor(OpenFluxStyle.orange)
            }.font(.system(size:13)).padding(20).background(LiquidTheme.card)
        }.background(OpenFluxBackdrop()).foregroundColor(LiquidTheme.text).tint(OpenFluxStyle.orange).navigationBarHidden(true)
    }
    private func row(_ title:String,_ icon:String)->some View {
        LiquidPanel {HStack {Label(title,systemImage:icon);Spacer();Image(systemName:"chevron.right").foregroundColor(OpenFluxStyle.orange)}}
    }
}

struct LiquidApplicationsView:View {
    var body:some View {
        VStack(spacing:14) {
            app("iOS","apple.logo")
            app("Android","smartphone")
            NavigationLink(destination:LiquidDiagnosticsView()){LiquidPanel{Label("Ссылка подключения",systemImage:"link")}}
            Link(destination:URL(string:"https://open-flux.ru/account")!){LiquidPanel{Label("Инструкция",systemImage:"book")}}
        }.buttonStyle(.plain)
    }
    private func app(_ name:String,_ icon:String)->some View {
        Link(destination:URL(string:"https://open-flux.ru/account")!) {
            LiquidPanel {
                HStack {
                    VStack(alignment:.leading,spacing:12) {
                        Image(systemName:icon).font(.system(size:36))
                        Text("Установить для \(name)").font(.system(size:22,weight:.medium))
                        Text("Установка и ваши устройства").font(.caption).foregroundColor(OpenFluxStyle.muted)
                    };Spacer();Image(systemName:"chevron.right").foregroundColor(OpenFluxStyle.orange)
                }.padding(.vertical,10)
            }
        }
    }
}

struct LiquidSubscriptionView:View {
    @ObservedObject private var store=ServerStore.shared
    @ObservedObject private var monitor=SubscriptionMonitor.shared
    var body:some View {
        VStack(spacing:14) {
            LiquidPanel {
                HStack {
                    LiquidMiniOrb()
                    VStack(alignment:.leading,spacing:12) {
                        Text(monitor.entries[store.activeServer.csqttPassword]?.status.state == "active" ? "● Доступ активен" : "Статус доступа").font(.system(size:13)).foregroundColor(.green)
                        Text("Срок и продление вашей подписки OpenFlux").font(.system(size:13)).foregroundColor(OpenFluxStyle.muted)
                    }
                }
            }
            Link(destination:URL(string:"https://open-flux.ru/account")!) {
                HStack {Image(systemName:"creditcard");Text("Продлить подписку");Spacer();Image(systemName:"chevron.right")}
                    .padding(20).foregroundColor(Color(red:0.13,green:0.04,blue:0.01))
                    .background(LinearGradient(colors:[.orange,Color(red:1,green:0.38,blue:0.05)],startPoint:.top,endPoint:.bottom),in:RoundedRectangle(cornerRadius:17))
            }
            Link(destination:URL(string:"https://open-flux.ru/account")!){LiquidPanel{Label("История оплат",systemImage:"doc.text")}}
            Link(destination:URL(string:"https://open-flux.ru/account")!){LiquidPanel{Label("Мои заявки",systemImage:"text.bubble")}}
            NavigationLink(destination:LiquidSection(kind:"Приложения")){LiquidPanel{Label("Приложения",systemImage:"square.grid.2x2")}}
        }.buttonStyle(.plain)
    }
}
