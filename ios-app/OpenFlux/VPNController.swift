import Foundation
import NetworkExtension
import Combine

@MainActor
final class VPNController: ObservableObject {
    @Published var status = "Disconnected"
    @Published var active = false
    @Published var lastError: String?
    @Published var log = UserDefaults.standard.string(forKey: "vpnDiagnosticLog") ?? ""

    private var manager: NETunnelProviderManager?
    private var extensionBundleId: String? {
        guard let plugins = Bundle.main.builtInPlugInsURL else { return nil }
        return Bundle(url: plugins.appendingPathComponent("OpenFluxTunnel.appex"))?.bundleIdentifier
    }
    private var logTimer: Timer?
    private var logRequestInFlight = false
    private var logRequestID = 0
    private var lastStatus: NEVPNStatus?
    private var manualStopPending = false
    private var diagnosticsOpen = false
    private var desiredRunning = false
    private var subscriptionURL = ""
    private var reconnectAttempts = 0
    private var reconnectTask: Task<Void, Never>?
    private var reconnectGeneration = 0
    private var connectionGeneration = 0
    private var connecting = false

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
        let loadingGeneration = connectionGeneration
        guard let extensionBundleId else {
            appendLog("[app] VPN extension missing from installed app")
            lastError = "Расширение VPN отсутствует. Проверьте подпись приложения."
            refreshStatus()
            return
        }
        appendLog("[app] VPN extension ID: \(extensionBundleId)")
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            manager = managers.first { ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                .providerBundleIdentifier == extensionBundleId }
            if connectionGeneration == loadingGeneration {
                desiredRunning = manager?.isOnDemandEnabled == true
                subscriptionURL = UserDefaults.standard.string(forKey: "wbSubscriptionURL") ?? ""
            }
            appendLog("[app] Настройки VPN загружены")
        } catch {
            appendLog("[app] Ошибка загрузки настроек VPN: \(error.localizedDescription)")
        }
        refreshStatus()
        if desiredRunning && manager?.connection.status == .disconnected {
            scheduleReconnect()
        }
    }

    func start(url: String) {
        manualStopPending = false
        desiredRunning = true
        subscriptionURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        reconnectAttempts = 0
        reconnectGeneration += 1
        connectionGeneration += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        lastError = nil
        active = true
        status = "Connecting…"
        appendLog("[app] Подключение запрошено")
        guard extensionBundleId != nil else {
            status = "Error: VPN extension missing"
            active = false
            desiredRunning = false
            lastError = "Расширение VPN отсутствует. Проверьте подпись приложения."
            appendLog("[app] Check signature and OpenFluxTunnel.appex installation")
            return
        }
        Task { await connectFromSubscription() }
    }

    private func connectFromSubscription() async {
        guard desiredRunning, !connecting else { return }
        connecting = true
        defer { connecting = false }
        let generation = connectionGeneration
        do {
            let directLink = subscriptionURL.hasPrefix("olcrtc://wbstream?")
            appendLog(directLink ? "[app] Проверка прямой ссылки WB Stream" :
                "[app] Загрузка HTTPS-подписки WB Stream")
            let node = try await WBSubscription.load(subscriptionURL)
            guard desiredRunning, generation == connectionGeneration else { return }
            appendLog("[app] Ссылка WB Stream принята; сохраняю настройки VPN")
            let m = manager ?? NETunnelProviderManager()
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = extensionBundleId
            proto.serverAddress = "WB Stream / OpenFlux"
            proto.disconnectOnSleep = false
            proto.providerConfiguration = [
                "configurationVersion": 3,
                "nodes": [node],
                "selectedNodeIndex": 0
            ]
            m.protocolConfiguration = proto
            m.localizedDescription = "Igor VPN"
            m.isEnabled = true
            m.onDemandRules = [NEOnDemandRuleConnect()]
            m.isOnDemandEnabled = true
            try await m.saveToPreferences()
            try await m.loadFromPreferences()
            guard desiredRunning, generation == connectionGeneration else { return }
            manager = m
            try m.connection.startVPNTunnel()
            appendLog("[app] Запуск расширения VPN через WB Stream")
        } catch {
            guard desiredRunning, generation == connectionGeneration else { return }
            appendLog("[app] Ошибка подключения: \(error.localizedDescription)")
            lastError = error.localizedDescription
            if error is WBSubscriptionError {
                desiredRunning = false
                active = false
                status = "Error: \(error.localizedDescription)"
                return
            }
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard desiredRunning, reconnectTask == nil else { return }
        reconnectAttempts = min(reconnectAttempts + 1, 7)
        let seconds = min(60, 1 << min(reconnectAttempts, 6))
        reconnectGeneration += 1
        let generation = reconnectGeneration
        status = "Reconnecting…"
        active = true
        appendLog("[app] Повторное подключение через \(seconds) с")
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard reconnectGeneration == generation else { return }
            reconnectTask = nil
            guard !Task.isCancelled, desiredRunning else { return }
            let state = manager?.connection.status
            if state == .connected || state == .connecting || state == .reasserting { return }
            if connecting {
                scheduleReconnect()
            } else {
                await connectFromSubscription()
            }
        }
    }

    func stop() {
        manualStopPending = true
        desiredRunning = false
        reconnectGeneration += 1
        connectionGeneration += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        active = false
        status = "Disconnected"
        lastError = nil
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

    func setVerboseLogging(_ enabled: Bool) {
        diagnosticsOpen = enabled
        if enabled { refreshLog() }
    }

    func clearLog() {
        log = ""
        UserDefaults.standard.removeObject(forKey: "vpnDiagnosticLog")
    }

    private func appendLog(_ chunk: String) {
        let combined = log.isEmpty ? chunk : log + "\n" + chunk
        let lines = combined.split(separator: "\n", omittingEmptySubsequences: true)
        log = lines.suffix(2000).joined(separator: "\n")
        UserDefaults.standard.set(log, forKey: "vpnDiagnosticLog")
    }

    @objc private func statusChanged() { refreshStatus() }

    private func refreshStatus() {
        guard let conn = manager?.connection else {
            active = desiredRunning
            status = desiredRunning ? "Connecting…" : "Disconnected"
            return
        }
        switch conn.status {
        case .connected: status = "Connected"; active = true
        case .connecting: status = "Connecting…"; active = true
        case .disconnecting: status = "Disconnecting…"; active = true
        case .reasserting: status = "Reconnecting…"; active = true
        default:
            status = desiredRunning ? "Reconnecting…" : "Disconnected"
            active = desiredRunning
        }
        if lastStatus != conn.status {
            let previousStatus = lastStatus
            lastStatus = conn.status
            appendLog("[app] Состояние VPN: \(status)")
            if conn.status == .connected {
                lastError = nil
                manualStopPending = false
                reconnectAttempts = 0
                reconnectTask?.cancel()
                reconnectTask = nil
                if diagnosticsOpen { setVerboseLogging(true) }
                refreshLog()
            } else if conn.status == .disconnected || conn.status == .invalid {
                let unexpected = !manualStopPending &&
                    (previousStatus == .connecting || previousStatus == .connected ||
                     previousStatus == .reasserting || previousStatus == .disconnecting)
                manualStopPending = false
                if unexpected { readLastDisconnectError(from: conn) }
                if desiredRunning { scheduleReconnect() }
            }
        }
    }

    private func readLastDisconnectError(from connection: NEVPNConnection) {
        guard #available(iOS 16.0, *) else {
            appendLog("[system] VPN disconnected; detailed system error requires iOS 16")
            return
        }
        connection.fetchLastDisconnectError { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    let nsError = error as NSError
                    self.appendLog("[system] VPN disconnected: \(nsError.domain) " +
                                   "code=\(nsError.code): \(nsError.localizedDescription)")
                    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                        self.appendLog("[system] Underlying: \(underlying.domain) " +
                                       "code=\(underlying.code): \(underlying.localizedDescription)")
                    }
                } else {
                    self.appendLog("[system] VPN disconnected without a reported error")
                }
            }
        }
    }
}
