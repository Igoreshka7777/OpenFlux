import Foundation
import NetworkExtension
import Combine

@MainActor
final class VPNController: ObservableObject {
    @Published var status = "Disconnected"
    @Published var active = false
    @Published var log = UserDefaults.standard.string(forKey: "vpnDiagnosticLog") ?? ""

    private var manager: NETunnelProviderManager?
    private let extensionBundleId = "com.p1neapplexpress-saharev.openflux.tunnel"
    private var logTimer: Timer?

    init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(statusChanged),
            name: .NEVPNStatusDidChange, object: nil)
        Task { await load() }
        logTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLog() }
        }
    }

    deinit { logTimer?.invalidate() }

    private func load() async {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        manager = managers.first
        refreshStatus()
    }

    func start(url: String, autoDetect: Bool, vpnDomains: String, directDomains: String) {
        Task {
            let m = manager ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = extensionBundleId
            proto.serverAddress = "Mail.ru / OpenFlux"
            proto.providerConfiguration = [
                "transport": "mailru",
                "url": url.trimmingCharacters(in: .whitespacesAndNewlines),
                "autoDetect": autoDetect,
                "vpnDomains": vpnDomains,
                "directDomains": directDomains
            ]
            m.protocolConfiguration = proto
            m.localizedDescription = "Igor VPN"
            m.isEnabled = true
            do {
                try await m.saveToPreferences()
                try await m.loadFromPreferences()
                manager = m
                try m.connection.startVPNTunnel()
            } catch {
                status = "Error: \(error.localizedDescription)"
            }
        }
    }

    func stop() {
        refreshLog()
        manager?.connection.stopVPNTunnel()
    }

    func refreshLog() {
        guard let session = manager?.connection as? NETunnelProviderSession,
              session.status == .connected || session.status == .connecting ||
              session.status == .reasserting else { return }
        do {
            try session.sendProviderMessage(Data("logs".utf8)) { [weak self] response in
                guard let response = response,
                      let chunk = String(data: response, encoding: .utf8),
                      !chunk.isEmpty else { return }
                Task { @MainActor in self?.appendLog(chunk) }
            }
        } catch {
            let message = "[app] Не удалось прочитать журнал VPN: \(error.localizedDescription)"
            if !log.hasSuffix(message) { appendLog(message) }
        }
    }

    func clearLog() {
        log = ""
        UserDefaults.standard.removeObject(forKey: "vpnDiagnosticLog")
    }

    private func appendLog(_ chunk: String) {
        let lines = (log + chunk + "\n").split(separator: "\n", omittingEmptySubsequences: true)
        log = lines.suffix(300).joined(separator: "\n")
        UserDefaults.standard.set(log, forKey: "vpnDiagnosticLog")
    }

    @objc private func statusChanged() { refreshStatus() }

    private func refreshStatus() {
        guard let conn = manager?.connection else {
            active = false
            status = "Disconnected"
            return
        }
        switch conn.status {
        case .connected: status = "Connected"; active = true
        case .connecting: status = "Connecting…"; active = true
        case .disconnecting: status = "Disconnecting…"; active = true
        case .reasserting: status = "Reasserting…"; active = true
        default: status = "Disconnected"; active = false
        }
    }
}
