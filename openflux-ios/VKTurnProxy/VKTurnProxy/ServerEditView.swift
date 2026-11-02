// ServerEditView.swift
//
// Edit screen for a single named ServerProfile (M2). Reached from SettingsView
// via a NavigationLink. It edits a local `draft` copy and persists every change
// through ServerStore.update() (which projects onto the flat @AppStorage keys
// when the edited server is the active one). New / Copy / Delete manage the set;
// the last remaining server cannot be deleted.
//
// vkLink and VK account auth are GLOBAL (edited on SettingsView), not here.

import SwiftUI

struct ServerEditView: View {
    @ObservedObject private var store = ServerStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ServerProfile

    // Global (not per-server) — read only to compute the cookie-mode conn cap.
    @AppStorage("vkLink") private var vkLink = ""
    @AppStorage("VKAuth") private var vkAuthEnabled = false

    init(serverId: UUID) {
        let s = ServerStore.shared.servers.first { $0.id == serverId }
                ?? ServerStore.shared.activeServer
        _draft = State(initialValue: s)
    }

    // Mode <-> draft flags, mutually exclusive (mirrors serverModeBinding).
    private var mode: Binding<ServerMode> {
        Binding(
            get: {
                if draft.useCsqtt { return .csqtt }
                if draft.useWrapS { return .srtpWrapS }
                if draft.useWrapA { return .srtpWrapA }
                if draft.useSrtp { return .srtp }
                if draft.useWrap { return .srtpWrap }
                return .legacy
            },
            set: { m in
                draft.useCsqtt = (m == .csqtt)
                draft.useWrapS = (m == .srtpWrapS)
                draft.useWrapA = (m == .srtpWrapA)
                draft.useSrtp  = (m == .srtp)
                draft.useWrap  = (m == .srtpWrap)
                // csqtt binds the password to ONE device identity: mint it the
                // first time the mode is chosen and keep it from then on.
                if m == .csqtt && draft.csqttDeviceID.isEmpty {
                    draft.csqttDeviceID = UUID().uuidString
                }
                if m == .srtpWrapS && draft.clientID.isEmpty {
                    draft.clientID = UUID().uuidString
                }
                // Same idea for SRTP-WRAP-A's device ID, except a server
                // switched into WRAP-A on build ≤180 would have connected with
                // this install's single hidden App-Group ID — so adopt that one
                // while it is still unclaimed (keeps the WireGuard peer the
                // server already minted) and mint a fresh one otherwise.
                if m == .srtpWrapA && draft.deviceID.isEmpty {
                    draft.deviceID = store.unclaimedLegacyWrapADeviceID() ?? UUID().uuidString
                }
            }
        )
    }

    @ViewBuilder
    private func hint(_ issue: ConfigValidation.Issue?) -> some View {
        if let issue {
            Text(issue.message)
                .font(.caption)
                .foregroundColor(issue.severity == .error ? .red : .orange)
        }
    }

    // Cookie-mode connection cap (mirrors SettingsView), from the same helper
    // connect() clamps with, so the label always states what really happens.
    private var vkLinkLines: [String] {
        vkLink.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    private var cookieConnCap: Int { TunnelConfig.cookieConnCap(callLinks: vkLinkLines.count) }
    private var connectionsUpperBound: Int {
        vkAuthEnabled ? max(cookieConnCap, draft.numConnections) : max(TunnelConfig.anonConnCap, draft.numConnections)
    }
    private var connectionsLabel: String {
        if vkAuthEnabled && draft.numConnections > cookieConnCap {
            return "Connections: \(draft.numConnections) → \(cookieConnCap) (add call links)"
        }
        if vkAuthEnabled { return "Connections: \(draft.numConnections) (max \(cookieConnCap))" }
        return "Connections: \(draft.numConnections)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Circle().fill(OpenFluxStyle.accent).frame(width: 11, height: 11)
                    Text("OPENFLUX").font(.system(size: 17, weight: .bold)).tracking(2)
                }
                .padding(.top, 12)
                Text("Сервер")
                    .font(.system(size: 30, weight: .bold))

                OpenFluxCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("НАЗВАНИЕ").font(.caption.bold()).foregroundColor(OpenFluxStyle.muted)
                        TextField("Название сервера", text: $draft.serverName)
                            .padding(14)
                            .background(OpenFluxStyle.background, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(OpenFluxStyle.border))
                            .disableAutocorrection(true)
                    }
                }

                OpenFluxCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Подключение CSQTT", systemImage: "network")
                            .font(.system(size: 18, weight: .bold))
                        Text("АДРЕС СЕРВЕРА")
                            .font(.caption.bold()).foregroundColor(OpenFluxStyle.muted)
                        TextField("Адрес сервера:порт", text: $draft.peerAddress)
                            .padding(14)
                            .background(OpenFluxStyle.background, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(OpenFluxStyle.border))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        hint(ConfigValidation.peerAddress(draft.peerAddress))
                        Text("ПАРОЛЬ ДОСТУПА")
                            .font(.caption.bold()).foregroundColor(OpenFluxStyle.muted)
                        SecureField("Пароль", text: $draft.csqttPassword)
                            .padding(14)
                            .background(OpenFluxStyle.background, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(OpenFluxStyle.border))
                        hint(ConfigValidation.csqttPassword(draft.csqttPassword))
                        Text("ID УСТРОЙСТВА")
                            .font(.caption.bold()).foregroundColor(OpenFluxStyle.muted)
                        TextField("ID устройства", text: $draft.csqttDeviceID)
                            .padding(14)
                            .background(OpenFluxStyle.background, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(OpenFluxStyle.border))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        hint(ConfigValidation.csqttDeviceID(draft.csqttDeviceID, onEditScreen: true))
                    }
                }

                OpenFluxCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Скорость и устойчивость", systemImage: "speedometer")
                            .font(.system(size: 18, weight: .bold))
                        Stepper("Параллельные потоки: \(draft.numConnections)",
                                value: $draft.numConnections, in: 1...connectionsUpperBound)
                        Toggle("Перезапускать зависший поток", isOn: $draft.csqttBoundedWrites)
                        Text("Измените число потоков после отключения VPN.")
                            .font(.caption).foregroundColor(OpenFluxStyle.muted)
                    }
                }

                OpenFluxCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Управление", systemImage: "square.on.square")
                            .font(.system(size: 18, weight: .bold))
                        Button {
                            draft = store.addNew()
                            draft.useCsqtt = true
                            draft.useWrapA = false
                            draft.useWrapS = false
                            draft.useSrtp = false
                            draft.useWrap = false
                            if draft.csqttDeviceID.isEmpty { draft.csqttDeviceID = UUID().uuidString }
                            store.update(draft)
                        } label: { Label("Добавить сервер", systemImage: "plus") }
                        Button {
                            if let copy = store.copy(draft.id) { draft = copy }
                        } label: { Label("Копировать сервер", systemImage: "doc.on.doc") }
                        Button(role: .destructive) {
                            store.delete(draft.id)
                            dismiss()
                        } label: { Label("Удалить сервер", systemImage: "trash") }
                            .disabled(store.servers.count <= 1)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .foregroundColor(.white)
        .tint(OpenFluxStyle.orange)
        .background(OpenFluxStyle.background.ignoresSafeArea())
        .dismissKeyboardOnDrag()
        // A csqtt server without a Device ID (a restored backup, an older
        // blob) gets a VISIBLE one here, so what connects is what is shown.
        // Cleared by hand it stays empty — and Connect stays blocked — until
        // this screen is opened again.
        .onAppear {
            if draft.useCsqtt && draft.csqttDeviceID.isEmpty {
                draft.csqttDeviceID = UUID().uuidString
            }
        }
        .navigationTitle(draft.serverName.isEmpty ? "Server" : draft.serverName)
        .navigationBarTitleDisplayMode(.inline)
        // Persist every edit through the store (projects onto the flat keys when
        // this is the active server). onChange does not fire on first render.
        .onChange(of: draft) { store.update($0) }
    }
}
