import SwiftUI
@main struct GlowPreviewApp:App {
 var body:some Scene {WindowGroup {
  VStack(spacing:24) {
   Text("OPENFLUX").font(.headline).foregroundColor(.white).padding(.top,30)
   Spacer()
   SubscriptionGlowControl(level:1,status:"Подключено",days:"")
   Text("Нажмите на круг, чтобы отключить VPN").font(.caption).foregroundColor(.gray)
   Spacer()
  }.background(Color.black.ignoresSafeArea()).preferredColorScheme(.dark)
 }}
}
