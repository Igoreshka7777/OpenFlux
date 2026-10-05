import Foundation

let link = "csqtt://connect?v=2&host=203.0.113.7&peer=46000&password=example&token=vk1.a.example%2Bvalue%3D"
func recovered(_ raw: String = link, peer: String = "203.0.113.7:46000", password: String = "example") -> String {
    CsqttLinkToken.recover(from: raw, peer: peer, password: password)
}
precondition(recovered() == "vk1.a.example+value=")
precondition(recovered(link.replacingOccurrences(of: "&", with: "&amp;")) == "vk1.a.example+value=")
precondition(recovered(peer: "203.0.113.8:46000").isEmpty)
precondition(recovered(peer: "203.0.113.7:46001").isEmpty)
precondition(recovered(password: "different").isEmpty)
precondition(recovered(link.replacingOccurrences(of: "csqtt://", with: "https://")).isEmpty)
precondition(recovered(link.replacingOccurrences(of: "v=2", with: "v=3")).isEmpty)
precondition(recovered(link.replacingOccurrences(of: "vk1.a.example%2Bvalue%3D", with: "bad%0Atoken")).isEmpty)
precondition(recovered("csqtt://example@203.0.113.7:46000").isEmpty)
precondition(!CsqttLinkToken.valid(""))
precondition(!CsqttLinkToken.valid("invalid token"))
precondition(CsqttLinkToken.valid("vk1.a.example+value="))
print("12 connection token recovery checks passed")
