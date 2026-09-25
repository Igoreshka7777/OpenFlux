import Foundation
import NetworkExtension

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let routeQueue = DispatchQueue(label: "igorvpn.routes")
    private var routeTimer: DispatchSourceTimer?
    private var routedIPs = Set<String>()
    private var applyingRoute = false
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
        let vpnDomains = (conf["vpnDomains"] as? String) ?? ""
        let directDomains = (conf["directDomains"] as? String) ?? ""
        let autoDetect = (conf["autoDetect"] as? Bool) ?? true
        stopped = false
        routedIPs.removeAll()

        // The system route stays direct. Only the local DNS address and
        // confirmed VPN destination IPs are captured by this extension.
        setTunnelNetworkSettings(makeSettings()) { error in
            if let error = error {
                completionHandler(error)
                return
            }
            let rc = url.withCString { u in
                vpnDomains.withCString { vpn in
                    directDomains.withCString { direct in
                        OpenFluxStartPacketTunnel(
                            UnsafeMutablePointer(mutating: u),
                            UnsafeMutablePointer(mutating: vpn),
                            UnsafeMutablePointer(mutating: direct),
                            autoDetect ? 1 : 0)
                    }
                }
            }
            if rc != 0 {
                completionHandler(NSError(
                    domain: "IgorVPN", code: Int(rc),
                    userInfo: [NSLocalizedDescriptionKey: "Не удалось запустить Mail.ru (\(rc))"]))
                return
            }
            self.startReadLoop()
            self.startWriteLoop()
            self.startRoutePolling()
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        routeQueue.sync {
            stopped = true
            routeTimer?.cancel()
            routeTimer = nil
        }
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
        var routes = [NEIPv4Route(destinationAddress: "198.18.0.1",
                                  subnetMask: "255.255.255.255")]
        routes += routedIPs.sorted().map {
            NEIPv4Route(destinationAddress: $0, subnetMask: "255.255.255.255")
        }
        ipv4.includedRoutes = routes
        settings.ipv4Settings = ipv4
        settings.mtu = 1500
        let dns = NEDNSSettings(servers: ["198.18.0.1"])
        dns.matchDomains = [""]
        settings.dnsSettings = dns
        return settings
    }

    private func startRoutePolling() {
        let timer = DispatchSource.makeTimerSource(queue: routeQueue)
        timer.schedule(deadline: .now() + .milliseconds(100),
                       repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.takeNextRoute() }
        routeTimer = timer
        timer.resume()
    }

    private func takeNextRoute() {
        guard !stopped && !applyingRoute else { return }
        var buffer = [CChar](repeating: 0, count: 64)
        let count = buffer.withUnsafeMutableBufferPointer { ptr in
            OpenFluxTunNextRoute(ptr.baseAddress, Int32(ptr.count))
        }
        guard count > 0 else { return }
        let ip = String(cString: buffer)
        if routedIPs.contains(ip) {
            ackRoute(ip, success: true)
            return
        }
        applyingRoute = true
        routedIPs.insert(ip)
        setTunnelNetworkSettings(makeSettings()) { [weak self] error in
            guard let self = self else { return }
            self.routeQueue.async {
                if error != nil { self.routedIPs.remove(ip) }
                self.ackRoute(ip, success: error == nil)
                self.applyingRoute = false
            }
        }
    }

    private func ackRoute(_ ip: String, success: Bool) {
        ip.withCString { value in
            OpenFluxTunAckRoute(UnsafeMutablePointer(mutating: value), success ? 1 : 0)
        }
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
