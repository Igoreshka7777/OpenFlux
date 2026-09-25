import SwiftUI
import UIKit

private enum Theme {
    static let background = Color(red: 0.018, green: 0.016, blue: 0.018)
    static let card = Color(red: 0.085, green: 0.079, blue: 0.085)
    static let muted = Color(red: 0.58, green: 0.56, blue: 0.58)
    static let orange = Color(red: 1.0, green: 0.54, blue: 0.08)
    static let red = Color(red: 0.92, green: 0.16, blue: 0.13)
    static let ring = AngularGradient(
        colors: [orange, Color(red: 1.0, green: 0.36, blue: 0.05), red, orange],
        center: .center, startAngle: .degrees(-90), endAngle: .degrees(270))
}

struct ContentView: View {
    @StateObject private var vpn = VPNController()
    @AppStorage("wbSubscriptionURL") private var docURL = ""
    @State private var showSettings = false
    @State private var showSupport = false
    @State private var breathe = false

    private var canStart: Bool {
        !docURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isConnecting: Bool {
        vpn.active && vpn.status != "Connected"
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(colors: [Theme.red.opacity(vpn.active ? 0.11 : 0.045), .clear],
                           center: .center, startRadius: 30, endRadius: 300)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 30)
                connectionControl
                Spacer(minLength: 30)
                footer
            }
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
        .preferredColorScheme(.dark)
        .onAppear { breathe = true }
        .sheet(isPresented: $showSettings) {
            SettingsView(docURL: $docURL, vpn: vpn)
        }
        .sheet(isPresented: $showSupport) { SupportView() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.ring)
                .frame(width: 11, height: 11)
                .shadow(color: Theme.orange.opacity(0.7), radius: 8)
            Text("IGOR VPN")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .tracking(2.2)
                .foregroundColor(.white)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("Настройки")
        }
        .foregroundColor(Theme.muted)
        .buttonStyle(.plain)
    }

    private var connectionControl: some View {
        VStack(spacing: 0) {
            Button(action: toggleVPN) {
                ZStack {
                    Circle()
                        .stroke(Theme.ring, lineWidth: 15)
                        .frame(width: 160, height: 160)
                        .blur(radius: 19)
                        .opacity(vpn.active ? 0.38 : 0.20)
                    Circle()
                        .stroke(Theme.ring,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .frame(width: 150, height: 150)
                        .shadow(color: Theme.orange.opacity(0.32), radius: 15)
                    Circle()
                        .fill(Theme.background)
                        .frame(width: 136, height: 136)
                    Image(systemName: "power")
                        .font(.system(size: 31, weight: .ultraLight))
                        .foregroundColor(vpn.active ? Theme.orange : Theme.muted.opacity(0.72))
                }
                .frame(width: 190, height: 190)
                .contentShape(Circle())
                .scaleEffect(breathe ? 1.025 : 0.985)
                .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                           value: breathe)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(vpn.active ? "Отключить VPN" : "Подключить VPN")

            Text(vpn.status == "Connected" ? "ПОДКЛЮЧЕНО" :
                 (vpn.status == "Reconnecting…" ? "ПЕРЕПОДКЛЮЧЕНИЕ…" :
                  (isConnecting ? "ПОДКЛЮЧЕНИЕ…" : "НЕ ПОДКЛЮЧЕНО")))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .tracking(2.8)
                .foregroundColor(vpn.status == "Connected" ? Theme.orange : .white)
                .padding(.top, 32)
            Text(canStart ? "Нажмите на круг, чтобы \(vpn.active ? "отключить" : "подключить") VPN" :
                 "Добавьте ссылку подписки в настройках")
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 9)
            if vpn.status.hasPrefix("Error:") {
                Text(vpn.status)
                    .font(.footnote)
                    .foregroundColor(Theme.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 18) {
            HStack(spacing: 7) {
                Image(systemName: "lock.shield")
                Text("Трафик — через VPN")
            }
            .font(.system(size: 12))
            .foregroundColor(Theme.muted.opacity(0.82))
            Button { showSupport = true } label: {
                Label("Поддержать проект", systemImage: "heart")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleVPN() {
        if vpn.active {
            vpn.stop()
        } else if canStart {
            vpn.start(url: docURL)
        } else {
            showSettings = true
        }
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var docURL: String
    @ObservedObject var vpn: VPNController
    @State private var showDiagnostics = false

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        card {
                            Text("ПОДКЛЮЧЕНИЕ")
                                .font(.caption.bold()).tracking(1.8)
                                .foregroundColor(Theme.orange)
                            TextField("Ссылка подписки WB Stream", text: $docURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .textFieldStyle(.roundedBorder)
                                .disabled(vpn.active)
                            Text("Вставьте персональную ссылку подписки из веб-панели.")
                                .font(.caption)
                                .foregroundColor(Theme.muted)
                        }
                        card {
                            Text("ПОМОЩЬ")
                                .font(.caption.bold()).tracking(1.8)
                                .foregroundColor(Theme.orange)
                            Button {
                                vpn.refreshLog()
                                showDiagnostics = true
                            } label: {
                                Label("Диагностика и логи", systemImage: "waveform.path.ecg")
                            }
                            Text("Журнал VPN хранится на этом iPhone.")
                                .font(.caption)
                                .foregroundColor(Theme.muted)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .accentColor(Theme.orange)
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView(vpn: vpn)
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vpn: VPNController

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Text(vpn.status == "Connected" ? "VPN подключён" : "VPN выключен")
                            .foregroundColor(Theme.muted)
                        Spacer()
                        Button { vpn.refreshLog() } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Обновить логи")
                        Button { UIPasteboard.general.string = vpn.log } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel("Скопировать логи")
                    }
                    .font(.footnote)
                    ScrollViewReader { reader in
                        ScrollView {
                            Text(vpn.log.isEmpty ? "Пока нет событий VPN" : vpn.log)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(vpn.log.isEmpty ? Theme.muted : .white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id("logEnd")
                        }
                        .onChange(of: vpn.log) { _ in
                            reader.scrollTo("logEnd", anchor: .bottom)
                        }
                    }
                    .padding(14)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    Button("Очистить журнал") { vpn.clearLog() }
                        .font(.footnote)
                        .foregroundColor(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .navigationTitle("Диагностика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
            .accentColor(Theme.orange)
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
        .onAppear {
            vpn.setVerboseLogging(true)
            vpn.refreshLog()
        }
        .onDisappear { vpn.setVerboseLogging(false) }
    }
}

private struct SupportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    private let phone = "89126438781"

    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 18) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.red)
                    Text("Поддержать проект")
                        .font(.title2.bold())
                    Text("ОТП Банк")
                        .foregroundColor(Theme.muted)
                    Button {
                        UIPasteboard.general.string = phone
                        copied = true
                    } label: {
                        Label(phone, systemImage: "doc.on.doc")
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(Theme.ring)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    if copied { Text("Номер скопирован").foregroundColor(Theme.orange) }
                    Spacer()
                }
                .padding(.top, 56)
            }
            .navigationTitle("Поддержка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .accentColor(Theme.orange)
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }
}

#Preview { ContentView() }
