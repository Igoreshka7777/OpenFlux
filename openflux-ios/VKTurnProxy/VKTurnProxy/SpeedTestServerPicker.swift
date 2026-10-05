import SwiftUI

/// Choosing the server, and saying WHOSE neighbourhood the list describes.
///
/// 🚨 The header text is the point, not decoration. Ookla builds this list from
/// the device's APPARENT address, so with the tunnel up it is servers near the
/// EXIT and with it down servers near the user. The same "Auto" therefore
/// measures two different paths, silently — and comparing "with VPN" against
/// "without" is the first thing anyone does. Pinning one server is what makes
/// that pair mean anything, which is why the pin survives the tunnel state.
struct SpeedTestServerPicker: View {
    @Binding var serverID: String
    @Binding var serverLabel: String

    @ObservedObject private var runner = SpeedTestRunner.shared
    @ObservedObject private var tunnel = TunnelManager.shared
    @Environment(\.presentationMode) private var presentation

    @State private var query = ""

    /// The route RIGHT NOW — used only to ask the list whether it is stale, never
    /// to describe the rows.
    private var livePath: SpeedTestPath {
        .current(connected: tunnel.status == .connected, directMode: tunnel.directMode)
    }

    /// 🚨 Asked of the LIST, which knows what it was fetched under. This used to
    /// be computed from the live tunnel state while the rows below were whatever
    /// had been fetched earlier, so after a VPN → DIRECT switch the header
    /// described a neighbourhood the rows did not come from.
    private var neighbourhood: String {
        runner.serverList?.header(now: livePath) ?? "Серверы"
    }

    private var filtered: [SpeedTestServer] {
        guard !query.isEmpty else { return runner.servers }
        let q = query.lowercased()
        return runner.servers.filter {
            $0.name.lowercased().contains(q)
                || $0.sponsor.lowercased().contains(q)
                || $0.country.lowercased().contains(q)
                || $0.id == query
        }
    }

    @ViewBuilder
    private func row(_ server: SpeedTestServer) -> some View {
        Button {
            serverID = server.id
            serverLabel = server.label
            presentation.wrappedValue.dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.label)
                    // Latency first — it is the measured one. The distance is
                    // Ookla's guess about where YOU are, and is labelled "est."
                    // for that reason.
                    Text("id \(server.id) · \(server.proximity)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if serverID == server.id { Image(systemName: "checkmark") }
            }
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    serverID = ""
                    serverLabel = ""
                    presentation.wrappedValue.dismiss()
                } label: {
                    HStack {
                        Text("Автоматически (ближайший)")
                        Spacer()
                        if serverID.isEmpty { Image(systemName: "checkmark") }
                    }
                }
            }

            Section {
                if runner.serversLoading {
                    HStack { ProgressView(); Text("Загружаем…").foregroundColor(.secondary) }
                } else if let err = runner.serversError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Button("Повторить") { runner.loadServers() }
                } else {
                    if let latency = runner.serverList?.latencyNotice(now: livePath) {
                        Label(latency, systemImage: "arrow.triangle.branch")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    if let notice = runner.serverList?.staleNotice(now: livePath) {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(notice, systemImage: "arrow.triangle.branch")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Button("Обновить для этого маршрута") { runner.loadServers() }
                                .font(.caption)
                        }
                    }
                    ForEach(filtered) { server in
                        row(server)
                    }
                    // 🚨 The local filter can only narrow rows we already have,
                    // and the nearby list is built from the apparent IP — so the
                    // server in your own city may simply not be in it. This asks
                    // Ookla.
                    if !query.isEmpty {
                        Button {
                            runner.searchServers(query)
                        } label: {
                            Label(filtered.isEmpty
                                  ? "Нет совпадений — найти в Ookla: “\(query)”"
                                  : "Найти в Ookla: “\(query)”",
                                  systemImage: "magnifyingglass.circle")
                                .font(.caption)
                        }
                    }
                }
            } header: {
                Text(neighbourhood)
            }

            if runner.search != .idle {
                Section {
                    // Every branch names the query it is about, because the
                    // state carries it — the heading cannot describe one search
                    // while the rows below answer another.
                    switch runner.search {
                    case .idle:
                        EmptyView()
                    case let .searching(query):
                        HStack {
                            ProgressView()
                            Text("Ищем в Ookla: “\(query)”…").foregroundColor(.secondary)
                        }
                    case let .failed(query, message):
                        Label("Ошибка поиска “\(query)”: \(message)",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Button("Повторить поиск") { runner.searchServers(query) }
                            .font(.caption)
                    case let .results(query, list):
                        if list.servers.isEmpty {
                            Text("По запросу “\(query)” ничего не найдено.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        // The latencies below were measured on the route the
                        // search ran on. Say so when that is no longer the route.
                        if let notice = list.latencyNotice(now: livePath) {
                            Label(notice, systemImage: "arrow.triangle.branch")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        ForEach(list.servers) { server in
                            row(server)
                        }
                    }
                    if !runner.search.isSearching {
                        Button("Очистить поиск") { runner.clearSearch() }
                            .font(.caption)
                    }
                } header: {
                    Text("Результаты поиска Ookla")
                } footer: {
                    Text("Расстояние оценивает Ookla. Ориентируйтесь на измеренную задержку.")
                }
            }

            Section {
                EmptyView()
            } footer: {
                Text("Для сравнения скорости с VPN и без него выберите один и тот же сервер.")
            }
        }
        .openFluxEditorBackground()
        .background(OpenFluxStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(OpenFluxStyle.orange)
        .searchable(text: $query, prompt: "Название или город")
        .navigationTitle("Сервер")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if runner.servers.isEmpty { runner.loadServers() } }
    }
}
