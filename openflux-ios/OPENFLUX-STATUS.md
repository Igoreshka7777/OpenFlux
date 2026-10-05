# OpenFlux iOS handoff (build 452)

This is the iOS source project, not an installable IPA.

Recent changes:
- Settings now show remaining subscription days and the exact expiration date in the device timezone. Partial days round up; unlimited access and unavailable status are shown separately.
- A verified expired subscription opens the renewal page inside a full-screen app view. Telegram and VK buttons contact the administrator; the recheck button checks renewed access with the existing connection link.
- Subscription status is checked before connection and every 15 seconds while the app is open. While the VPN extension runs, it also checks every 20 seconds and schedules a local notification on confirmed expiry, subject to notification permission. When both the app and VPN are closed, the check resumes on the next launch; this is not a push-notification service.
- Only an explicit expired status with a passed server deadline triggers renewal. Network failures, disabled access and traffic quota errors are not interpreted as subscription expiry. A confirmed expired tunnel is stopped so ordinary internet can be used for renewal.
- The server retains expiry metadata after automatic cleanup of expired VPN credentials. Renewed live records take precedence over this metadata.
- The first screen has a compact logo, centered ring, the settings gear in the top corner, and a plain dark background. The duplicate bottom navigation and receive/transmit readout were removed.
- The iOS settings screen now follows Android's order: saved connection link, parallel-stream slider, VPN log, and full-screen support chat. Legacy setup cards were removed from the main settings screen.
- The first launch shows a native access screen with the 250 ₽ monthly price, the Get Link page, and a path for clients who already have a link. Existing configured clients can continue with their saved access.
- Support opens as a full-screen conversation directly from Settings and works over ordinary internet access even while VPN is disconnected.
- A CSQTT password already bound to another device displays a short Russian explanation and asks for a separate iPhone access link. The server's one-device credential binding remains enforced.
- Connection setup, support, logs and speed test use the same dark cards, orange accents and Russian controls.
- The old developer's Apple team ID was removed. App, tunnel and widget identifiers now use `org.igoreshka7777.openflux` and the matching App Group.
- The initial “Get link” page opens inside a full-screen in-app WebView without browser controls.
- The support chat opens full screen from the log screen and has a Back button.
- The main background stays plain dark, as requested. The power button uses the glowing halo.
- The iOS app icon is the same 1024×1024 OpenFlux orange-red ring used by the Android launcher.
- The Android release package 1.0.13 is available separately in `outputs/`.

Open `VKTurnProxy/VKTurnProxy.xcodeproj` on a Mac with Xcode. First build the Go bridge:

```sh
cd WireGuardBridge
make xcframework
```

Then generate the project if XcodeGen is installed (recommended after any `project.yml` changes):

```sh
cd ../VKTurnProxy
xcodegen generate
```

The app, packet-tunnel extension, and widget require an Apple Developer team with Network Extension and App Groups capabilities. Select that team in Xcode and register `group.org.igoreshka7777.openflux` for it before signing. If your account does not own the new bundle identifiers, choose available identifiers and update the app, extension, widget, App Group and shared-keychain references together. Do not distribute an unsigned build as a working VPN app.

This source has not yet been compiled or tested on a Mac or iPhone. Complete Xcode signing and test link import, VPN connect/reconnect, in-app access page, and support chat before distribution. For build 451, also test expiry while connected in the foreground and background, opening the notification, and reconnecting after renewal. Use a separate test client, not a paying user's connection.

Source is a GPL-3.0 derivative of `anton48/vk-turn-proxy-ios`; see LICENSE and README.md.
