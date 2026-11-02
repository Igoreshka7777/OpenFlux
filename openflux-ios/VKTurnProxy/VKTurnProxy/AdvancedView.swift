// AdvancedView.swift
//
// The "Advanced" screen, pushed from SettingsView. Home for settings that are
// opt-in, experimental, or otherwise not part of the everyday flow. Only the
// Live Activity switch lives here for now; more are expected.
//
// 🚨 Read reference: "SwiftUI pop rule" before adding anything here.
//
// This screen is PUSHED (Content → Settings → Advanced), and writing an
// @AppStorage key from a pushed screen is harmless — re-rendering a pushed view
// does not disturb the navigation stack. What is NOT harmless is letting
// ContentView observe the same key: ContentView hosts the NavigationView, and
// any re-render of it tears down whatever is pushed. That is exactly how build
// 177 and GitHub #65 happened.
//
// So the rule for every key added here: declare it on THIS screen (and wherever
// it is consumed below the navigation links), never in ContentView. Consumers
// that are not views read it through UserDefaults.standard instead.

import SwiftUI

struct AdvancedView: View {
    /// The DIRECT switch reads its state from the profile via TunnelManager;
    /// nothing here is @AppStorage, so the pop rule does not apply to it.
    @ObservedObject private var tunnel = TunnelManager.shared

    /// Live Activity master switch (GitHub issue #64). Default OFF — the feature
    /// is opt-in: it puts a persistent card on the Lock Screen and, on iOS 17+,
    /// controls that can disconnect the tunnel or switch servers from there.
    /// Deliberately NOT declared in ContentView (see the file header).
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = false

    /// Session clock in the COLLAPSED Dynamic Island. Default OFF because it is
    /// not free: the collapsed island is sized by its content and shares the top
    /// of the screen with the status bar, so a clock there costs one status-bar
    /// item. Same rule as above — declared HERE, never in ContentView.
    @AppStorage("liveActivityCompactClock") private var liveActivityCompactClock = false

    /// The uplink pacer, as a RATE in KiB/s where 0 means off — the same value
    /// the Go side stores, so the switch and the tunnel cannot disagree. Default
    /// OFF; see UplinkPace.swift for what it buys and what it costs. Declared
    /// HERE and nowhere near ContentView, per the file header.
    @AppStorage(UplinkPace.key) private var uplinkPaceKiB = UplinkPace.off

    /// Tunnel MTU. `TunnelMTU.automatic` (0) means "don't override", which is
    /// both the default and what every pre-209 install has — see TunnelMTU.swift
    /// for where the bounds come from. One key, not two: a separate "override?"
    /// boolean would be a second thing to keep in sync, in the backup as well.
    @AppStorage("tunnelMTU") private var tunnelMTU = TunnelMTU.automatic

    /// The switch is a view onto the sentinel: on = start from the standard
    /// 1280, off = back to automatic.
    private var mtuIsManual: Binding<Bool> {
        Binding(get: { tunnelMTU != TunnelMTU.automatic },
                set: { tunnelMTU = $0 ? TunnelMTU.standard : TunnelMTU.automatic })
    }

    /// Diagnostic: skip the captcha-free VK Calls path so credential fetching
    /// falls through to the legacy solver. Existed since build 149 but only
    /// reachable by hand-editing a backup; surfaced here in build 212 because a
    /// switch nobody can find is a switch nobody tests.
    @AppStorage("forceLegacyCaptcha") private var forceLegacyCaptcha = false

    /// Force the 1 s memstats cadence (build 229). Until now 1 s was reachable
    /// only by tripping an ALLOC-SPIKE — i.e. at moments the garbage collector
    /// picked, not the person measuring — which is why of three A/B logs taken
    /// on 2026-08-11 one had 1 s ticks over the burst, one over the dead gap
    /// between runs, and one had none. Same rule as the keys above: declared
    /// HERE, never in ContentView.
    @AppStorage("memstatsFastTicks") private var memstatsFastTicks = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Circle().fill(OpenFluxStyle.accent).frame(width: 11, height: 11)
                    Text("OPENFLUX").font(.system(size: 17, weight: .bold)).tracking(2)
                }
                .padding(.top, 12)
                Text("Дополнительно")
                    .font(.system(size: 30, weight: .bold))

                OpenFluxCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("На экране блокировки", systemImage: "iphone.gen3")
                            .font(.system(size: 18, weight: .bold))
                        Toggle("Показывать VPN", isOn: $liveActivityEnabled)
                            .onChange(of: liveActivityEnabled) { _ in
                                TunnelManager.shared.refreshLiveActivity()
                            }
                        Toggle("Время сеанса в Dynamic Island", isOn: $liveActivityCompactClock)
                            .disabled(!liveActivityEnabled)
                            .onChange(of: liveActivityCompactClock) { _ in
                                TunnelManager.shared.refreshLiveActivity()
                            }
                    }
                }

                OpenFluxCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Сеть", systemImage: "network")
                            .font(.system(size: 18, weight: .bold))
                        Toggle("Настроить MTU вручную", isOn: mtuIsManual)
                        if tunnelMTU != TunnelMTU.automatic {
                            Stepper("MTU: \(tunnelMTU)", value: $tunnelMTU,
                                    in: TunnelMTU.range, step: TunnelMTU.step)
                        }
                        Text("Меняйте MTU, если крупные файлы не загружаются через VPN.")
                            .font(.caption).foregroundColor(OpenFluxStyle.muted)
                        Toggle("Равномерная отдача", isOn: Binding(
                            get: { uplinkPaceKiB != UplinkPace.off },
                            set: { uplinkPaceKiB = $0 ? UplinkPace.onKiB : UplinkPace.off }
                        ))
                        .onChange(of: uplinkPaceKiB) { _ in
                            TunnelManager.shared.applyUplinkPaceFromSettings()
                        }
                    }
                }

                OpenFluxCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Прямой доступ", systemImage: "arrow.triangle.branch")
                            .font(.system(size: 18, weight: .bold))
                        Toggle("Пускать трафик напрямую", isOn: Binding(
                            get: { tunnel.directMode },
                            set: { on in Task { await tunnel.setDirectMode(on, from: .advancedSwitch) } }
                        ))
                        .disabled(tunnel.directModeBusy || tunnel.status != .connected)
                        if let problem = tunnel.directModeError {
                            Text(problem).font(.caption).foregroundColor(OpenFluxStyle.red)
                        }
                        Text("Когда включено, трафик идёт в обход VPN. Переподключение вернёт обычный режим.")
                            .font(.caption).foregroundColor(OpenFluxStyle.muted)
                    }
                }

                OpenFluxCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Диагностика", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 18, weight: .bold))
                        Toggle("Подробный журнал каждую секунду", isOn: $memstatsFastTicks)
                            .onChange(of: memstatsFastTicks) { _ in
                                TunnelManager.shared.applyMemstatsFastTicks()
                            }
                        Text("Включайте на время проверки соединения. Журнал будет заполняться быстрее.")
                            .font(.caption).foregroundColor(OpenFluxStyle.muted)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .foregroundColor(.white)
        .tint(OpenFluxStyle.orange)
        .background(OpenFluxStyle.background.ignoresSafeArea())
        .navigationTitle("Дополнительно")
    }
}
