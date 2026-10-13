import Foundation

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), name)
}
let policy = IOSUpdatePolicy(schema: 1, applicationID: "org.igoreshka7777.openflux", latestBuild: 459, minimumBuild: 459, message: "Обновление")
check(policy.required(for: 458), "Old build blocked")
check(!policy.required(for: 459), "Current build allowed")
check(!policy.available(for: 460), "No downgrade")
let optional = IOSUpdatePolicy(schema: 1, applicationID: policy.applicationID, latestBuild: 459, minimumBuild: 458, message: "Update")
check(optional.available(for: 458) && !optional.required(for: 458), "Optional update")
check(!IOSUpdatePolicy(schema: 1, applicationID: "other", latestBuild: 459, minimumBuild: 459, message: "").valid, "Wrong application rejected")
check(!IOSUpdatePolicy(schema: 1, applicationID: policy.applicationID, latestBuild: 458, minimumBuild: 459, message: "").valid, "Invalid version policy rejected")
let personal = "https://openfluxvpn.ru/ios/update/" + String(repeating: "a", count: 43)
check(IOSUpdateAPI.installationURL(personal).absoluteString == personal, "Personal update link")
for raw in ["http://openfluxvpn.ru/ios", "https://evil.example/ios", "https://openfluxvpn.ru@evil.example/ios", personal+"?redirect=evil"] {
    check(IOSUpdateAPI.installationURL(raw).absoluteString == "https://openfluxvpn.ru/ios", "Unsafe update destination")
}
let request = IOSCheckoutRequest.make(password: "abc+&=# test")
check(request.httpMethod == "POST", "Private credential uses body")
check(request.url?.query == nil, "No credential in URL")
check(String(data: request.httpBody!, encoding: .utf8) == "password=abc%2B%26%3D%23%20test", "Form encoding")
print("iOS update and payment checks passed")
