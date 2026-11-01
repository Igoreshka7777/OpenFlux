import SwiftUI
import UIKit
import NetworkExtension

enum LiquidTheme {
    static let card = LinearGradient(colors:[Color(red:53/255,green:19/255,blue:3/255),Color(red:22/255,green:9/255,blue:3/255),Color(red:44/255,green:16/255,blue:3/255)],startPoint:.topLeading,endPoint:.bottomTrailing)
    static let text = Color(red:1,green:235/255,blue:213/255)
}

struct LiquidGlass: View, Animatable {
    var level: Double
    var animatableData: Double { get { level } set { level = newValue } }
    var body: some View {
        Canvas { context,size in
            let image=context.resolve(Image("LiquidOrb"))
            let full=CGRect(origin:.zero,size:size)
            context.draw(image,in:full)
            let inner=CGRect(x:size.width*0.115,y:size.height*0.115,width:size.width*0.77,height:size.height*0.77)
            context.clip(to:Path(ellipseIn:inner))
            let split=size.height*0.36
            let target=size.height*(0.12+0.76*(1-min(1,max(0,level))))
            var upper=context
            upper.clip(to:Path(CGRect(x:0,y:0,width:size.width,height:target)))
            upper.draw(image,in:CGRect(x:0,y:0,width:size.width,height:size.height*target/split))
            var lower=context
            lower.clip(to:Path(CGRect(x:0,y:target,width:size.width,height:size.height-target)))
            let scale=(size.height-target)/(size.height-split)
            lower.draw(image,in:CGRect(x:0,y:target-split*scale,width:size.width,height:size.height*scale))
        }.animation(.easeInOut(duration:1.1),value:level)
    }
}

struct LiquidPanel<Content:View>: View {
    @ViewBuilder let content:Content
    var body:some View { VStack(alignment:.leading,spacing:13){content}.padding(16).frame(maxWidth:.infinity,alignment:.leading)
        .background(LiquidTheme.card,in:RoundedRectangle(cornerRadius:17)).overlay(RoundedRectangle(cornerRadius:17).stroke(OpenFluxStyle.border,lineWidth:0.8)) }
}

struct LiquidSettingsView: View {
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
                HStack { Button {presentation.wrappedValue.dismiss()} label:{Image(systemName:"chevron.left")};Text("Настройки").font(.system(size:23));Spacer();OpenFluxSupportButton() }.padding(.vertical,12)
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
                Text("OpenFlux 2.0 · 483").font(.caption).foregroundColor(OpenFluxStyle.muted).padding(.vertical,12)
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
