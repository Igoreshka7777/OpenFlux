import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let stateLock = NSLock()
    private var stoppedStorage = false

    private var stopped: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return stoppedStorage }
        set { stateLock.lock(); stoppedStorage = newValue; stateLock.unlock() }
    }

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        let conf = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let url = (conf["url"] as? String) ?? ""
        stopped = false

        guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completionHandler(NSError(domain: "IgorVPN", code: 100,
                userInfo: [NSLocalizedDescriptionKey: "Добавьте ссылку Mail.ru в настройках."]))
            return
        }

        setTunnelNetworkSettings(makeSettings()) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                completionHandler(error)
                return
            }
            let rc = url.withCString { value in
                OpenFluxStartPacketTunnel(UnsafeMutablePointer(mutating: value))
            }
            if rc != 0 {
                completionHandler(NSError(domain: "IgorVPN", code: Int(rc),
                    userInfo: [NSLocalizedDescriptionKey: "Не удалось запустить Mail.ru (\(rc)). Откройте диагностику."]))
                return
            }
            self.startReadLoop()
            self.startWriteLoop()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        stopped = true
        OpenFluxStopPacketTunnel()
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data,
                                   completionHandler: ((Data?) -> Void)?) {
        guard String(data: messageData, encoding: .utf8) == "logs" else {
            completionHandler?(nil)
            return
        }
        guard let value = OpenFluxReadLog() else {
            completionHandler?(Data())
            return
        }
        let message = String(cString: value)
        OpenFluxFreeString(value)
        completionHandler?(Data(message.utf8))
    }

    private func makeSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        let ipv4 = NEIPv4Settings(addresses: ["10.10.10.2"],
                                  subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4

        // The exit currently supports IPv4 TCP only. Capture IPv6 so IPv6
        // literals cannot bypass the VPN; AAAA DNS answers are suppressed.
        let ipv6 = NEIPv6Settings(addresses: ["fd00:10:10:10::2"],
                                  networkPrefixLengths: [64])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        settings.mtu = 1500
        let dns = NEDNSSettings(servers: ["198.18.0.1"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        return settings
    }

    private func startReadLoop() {
        packetFlow.readPackets { [weak self] packets, _ in
            guard let self = self, !self.stopped else { return }
            for packet in packets {
                packet.withUnsafeBytes { raw in
                    if let base = raw.bindMemory(to: CChar.self).baseAddress {
                        OpenFluxTunWritePacket(UnsafeMutablePointer(mutating: base),
                                               Int32(packet.count))
                    }
                }
            }
            self.startReadLoop()
        }
    }

    private func startWriteLoop() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let maxLen: Int32 = 4096
            let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(maxLen))
            defer { buffer.deallocate() }
            while true {
                let length = OpenFluxTunReadPacket(buffer, maxLen)
                if length <= 0 { break }
                let data = Data(bytes: buffer, count: Int(length))
                self.packetFlow.writePackets([data],
                    withProtocols: [NSNumber(value: AF_INET)])
            }
        }
    }
}
