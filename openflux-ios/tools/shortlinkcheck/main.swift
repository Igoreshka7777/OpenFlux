import Foundation
let valid = "https://openfluxvpn.ru/s/abcdefghijklmnopqrstuv"
precondition(OpenFluxShortLink.accepts(valid))
for bad in [valid + "?x=1", valid + "#x", valid + "/", String(valid.dropLast()),
            valid.replacingOccurrences(of: "https", with: "http"),
            valid.replacingOccurrences(of: "openfluxvpn.ru", with: "openfluxvpn.ru.evil.test"),
            valid.replacingOccurrences(of: "/s/", with: "/r/"),
            valid.replacingOccurrences(of: "openfluxvpn.ru", with: "user@openfluxvpn.ru")] {
    precondition(!OpenFluxShortLink.accepts(bad))
}
print("Short URL allowlist passed")

let current = valid.replacingOccurrences(of: "openfluxvpn.ru", with: "open-flux.ru")
precondition(OpenFluxShortLink.accepts(current))
precondition(OpenFluxShortLink.accepts("  " + current + "\n"))
for bad in [current + "?x=1", current + "#x", current + "/", String(current.dropLast()), current.replacingOccurrences(of: "open-flux.ru", with: "open-flux.ru.evil.test"), current.replacingOccurrences(of: "open-flux.ru", with: "user@open-flux.ru"), current.replacingOccurrences(of: "https:", with: "http:")] {
    precondition(!OpenFluxShortLink.accepts(bad))
}
print("Current and legacy domain boundaries passed")
