import NetworkExtension

var count = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    count += 1
    print("PASS \(message)")
}
check(HotspotCompatibility.includeAllNetworks(enabled: false), "Existing installations retain strict routing")
check(!HotspotCompatibility.includeAllNetworks(enabled: true), "Hotspot mode disables all-network capture")
check(!HotspotCompatibility.includeAllNetworks(enabled: true, direct: true), "Diagnostic direct mode stays direct")
check(!HotspotCompatibility.includeAllNetworks(enabled: false, direct: true), "Existing direct mode remains compatible")

let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "192.0.2.1")
let ip = NEIPv4Settings(addresses: ["10.66.67.39"], subnetMasks: ["255.255.255.255"])
ip.includedRoutes = [NEIPv4Route.default()]
settings.ipv4Settings = ip
settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "8.8.4.4"])
HotspotCompatibility.apply(to: settings, ipv4Only: true)
check(settings.ipv4Settings?.addresses == ["10.66.67.39"], "Server-assigned address is preserved")
check(settings.ipv4Settings?.includedRoutes?.first?.destinationAddress == "0.0.0.0", "Phone internet remains routed to VPN")
check(settings.ipv4Settings?.excludedRoutes?.count == 1, "No broad public IPv4 bypass")
check(settings.ipv4Settings?.excludedRoutes?.first?.destinationAddress == "172.20.10.0", "Hotspot gateway has a local route")
check(settings.ipv4Settings?.excludedRoutes?.first?.destinationSubnetMask == "255.255.255.240", "Local exclusion is limited to hotspot subnet")
check(settings.dnsSettings?.servers == ["8.8.8.8", "8.8.4.4"], "Configured DNS remains unchanged")
check(settings.dnsSettings?.matchDomains == [""], "Phone DNS applies to all domains")
check(settings.ipv6Settings?.includedRoutes?.first?.destinationNetworkPrefixLength.intValue == 0, "Unsupported public IPv6 cannot bypass VPN")
check(settings.ipv6Settings?.excludedRoutes?.count == 2, "IPv6 exclusions are local only")

let other = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "192.0.2.2")
HotspotCompatibility.apply(to: other, ipv4Only: false)
check(other.ipv6Settings == nil, "Other transports are not assigned the CSQTT IPv6 sink")
print("Verified \(count) hotspot routing checks")
