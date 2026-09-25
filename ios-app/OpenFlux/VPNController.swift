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
    private var logRequestInFlight = false
    private var logRequestID = 0
    private var lastStatus: NEVPNStatus?

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
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == extensionBundleId }
            appendLog("[app] Настройки VPN загружены")
        } catch {
            appendLog("[app] Ошибка загрузки настроек VPN: \(error.localizedDescription)")
        }
        refreshStatus()
    }

    func start(url: String) {
        appendLog("[app] Подключение запрошено")
        Task {
            let m = manager ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = extensionBundleId
            proto.serverAddress = "Mail.ru / OpenFlux"
            proto.disconnectOnSleep = false
            proto.providerConfiguration = [
                "transport": "mailru",
                "url": url.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
            m.protocolConfiguration = proto
            m.localizedDescription = "Igor VPN"
            m.isEnabled = true
            m.onDemandRules = [NEOnDemandRuleConnect()]
            m.isOnDemandEnabled = true
            do {
                try await m.saveToPreferences()
                try await m.loadFromPreferences()
                manager = m
                try m.connection.startVPNTunnel()
                appendLog("[app] Запуск расширения VPN")
            } catch {
                status = "Error: \(error.localizedDescription)"
                appendLog("[app] Ошибка запуска VPN: \(error.localizedDescription)")
            }
        }
    }

    func stop() {
        refreshLog()
        appendLog("[app] Отключение запрошено")
        Task {
            guard let m = manager else { return }
            m.isOnDemandEnabled = false
            do {
                try await m.saveToPreferences()
                try await m.loadFromPreferences()
            } catch {
                appendLog("[app] Не удалось отключить автоподключение: \(error.localizedDescription)")
            }
            m.connection.stopVPNTunnel()
        }
    }

    func refreshLog() {
        guard let session = manager?.connection as? NETunnelProviderSession,
              (session.status == .connected || session.status == .connecting ||
               session.status == .reasserting),
              !logRequestInFlight else { return }
        logRequestInFlight = true
        logRequestID += 1
        let requestID = logRequestID
        do {
            try session.sendProviderMessage(Data("logs".utf8)) { [weak self] response in
                Task { @MainActor in
                    guard let self = self else { return }
                    if self.logRequestID == requestID { self.logRequestInFlight = false }
                    if let response = response,
                       let chunk = String(data: response, encoding: .utf8),
                       !chunk.isEmpty { self.appendLog(chunk) }
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if logRequestInFlight && logRequestID == requestID {
                    logRequestInFlight = false
                    appendLog("[app] Расширение VPN не ответило на запрос журнала")
                }
            }
        } catch {
            logRequestInFlight = false
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
        if lastStatus != conn.status {
            lastStatus = conn.status
            appendLog("[app] Состояние VPN: \(status)")
            if conn.status == .connected { refreshLog() }
        }
    }
}
