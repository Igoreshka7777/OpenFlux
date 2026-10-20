import Foundation

// Cache schemas do not participate in profile settings. These placeholders
// let the command-line harness compile the actual AppConfig/ServerProfile.
struct CredCacheFile: Codable {}
struct VKProfileEntry: Codable {}

func imported(_ fields: [String: Any]) throws -> ServerProfile {
    var json: [String: Any] = ["peerAddress": "203.0.113.7:46000", "vkLink": ""]
    json.merge(fields) { _, value in value }
    let settings = try JSONDecoder().decode(ConnectionSettings.self,
        from: JSONSerialization.data(withJSONObject: json))
    return ServerProfile(link: settings)
}

let fresh = try imported(["useCsqtt": true, "csqttPassword": "test"])
precondition(fresh.useUDP && fresh.numConnections == 27)
precondition(!fresh.csqttDeviceID.isEmpty)
let explicit = try imported(["useCsqtt": true, "useUDP": false, "numConnections": 18])
precondition(!explicit.useUDP && explicit.numConnections == 18)
let ordinary = try imported([:])
precondition(!ordinary.useUDP && ordinary.numConnections == 30)

// A previously saved TCP profile must not be silently migrated on update.
let saved = Data(#"{"id":"00000000-0000-0000-0000-000000000001","serverName":"Existing","useCsqtt":true,"useUDP":false,"numConnections":30,"csqttPassword":"keep","csqttDeviceID":"keep-device"}"#.utf8)
var existing = try JSONDecoder().decode(ServerProfile.self, from: saved)
precondition(!existing.useUDP && existing.numConnections == 30)
let identity = existing.id
existing.applyRecommendedCsqttTransport()
precondition(existing.useUDP && existing.numConnections == 27)
precondition(existing.id == identity && existing.csqttPassword == "keep" && existing.csqttDeviceID == "keep-device")

// Profile JSON is the same format persisted by ServerStore. Both directions
// of the selector, the preset and explicit backup preferences must survive it.
let udpReload = try JSONDecoder().decode(ServerProfile.self, from: JSONEncoder().encode(existing))
precondition(udpReload == existing)
existing.useUDP = false
let tcpReload = try JSONDecoder().decode(ServerProfile.self, from: JSONEncoder().encode(existing))
precondition(!tcpReload.useUDP && tcpReload.numConnections == 27)
var unrelated = ordinary
unrelated.applyRecommendedCsqttTransport()
precondition(unrelated == ordinary)
let backup = ServerSettings(existing)
let restored = backup.profile
precondition(restored.useUDP == existing.useUDP && restored.numConnections == existing.numConnections)
print("OpenFlux transport checks passed: imports, saved profiles, preset, identities and persistence")
