import NetworkExtension

/// Opt-in routing for Personal Hotspot. It does not share the iPhone's VPN.
enum HotspotCompatibility {
    static let preferenceKey = "openFluxHotspotCompatibility"
    static let configurationKey = "hotspot_compatibility"

    static func includeAllNetworks(enabled: Bool, direct: Bool = false) -> Bool {
        !enabled && !direct
    }

    static func apply(to settings: NEPacketTunnelNetworkSettings, ipv4Only: Bool) {
        // Keep the tethering gateway reachable without sending it to the VPS.
        // Connected local routes on iOS continue to take precedence elsewhere.
        settings.ipv4Settings?.excludedRoutes = [
            NEIPv4Route(destinationAddress: "172.20.10.0", subnetMask: "255.255.255.240")
        ]
        settings.dnsSettings?.matchDomains = [""]
        settings.dnsSettings?.matchDomainsNoSearch = true

        if ipv4Only {
            // CSQTT currently provisions IPv4 only. Capture unsupported IPv6
            // instead of letting public IPv6 traffic silently bypass this VPN.
            let ipv6 = NEIPv6Settings(addresses: ["fd6f:7065:6e66::1"], networkPrefixLengths: [128])
            ipv6.includedRoutes = [NEIPv6Route.default()]
            ipv6.excludedRoutes = [
                NEIPv6Route(destinationAddress: "fe80::", networkPrefixLength: 10),
                NEIPv6Route(destinationAddress: "ff00::", networkPrefixLength: 8)
            ]
            settings.ipv6Settings = ipv6
        }
    }
}
