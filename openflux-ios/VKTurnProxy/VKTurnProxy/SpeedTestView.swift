import SwiftUI

/// The in-app speed test.
///
/// 🚨 Every `@AppStorage` key below is declared HERE and nowhere else. An unused
/// `@AppStorage` is still SUBSCRIBED, so declaring one in ContentView — which
/// hosts the NavigationView — makes any write to it tear down whatever is
/// pushed. That is the build-177/195 pop trap; the check is
/// `grep -c speedTest ContentView.swift` = 0.
struct SpeedTestView: View {
    let tunnel: TunnelManager

    /// 🚨 ObservedObject, not StateObject: the runner outlives this screen on
    /// purpose. See SpeedTestRunner.
    @ObservedObject private var runner = SpeedTestRunner.shared

    @AppStorage("speedTestServerID") private var serverID = ""
    @AppStorage("speedTestServerLabel") private var serverLabel = ""
    @AppStorage("speedTestThreads") private var threads = 4
    @AppStorage("speedTestDirection") private var direction = "both"
    @AppStorage("speedTestDuration") private var durationSec = 15
    @AppStorage("speedTestResearch") private var research = false

    @State private var showParameters = false

    private let threadChoices = [1, 2, 4, 8, 16, 32]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Circle().fill(OpenFluxStyle.accent).frame(width: 11, height: 11)
                    Text("OPENFLUX").font(.system(size: 17, weight: .bold)).tracking(2)
                }
                Text("Скорость соединения")
                    .font(.system(size: 26, weight: .bold))
            }
            .listRowBackground(OpenFluxStyle.surface)
            serverSection
            testSection
            runSection
            if let run = runner.startedRun, runner.progress.state != "idle" {
                Section {
                    SpeedTestResultView(run: run,
                                        progress: runner.progress,
                                        path: runner.pathTrace,
                                        previousServerID: runner.previousServerID)
                } header: {
                    Text("Результат")
                }
                .listRowBackground(OpenFluxStyle.surface)
            }
        }
        .openFluxEditorBackground()
        .background(OpenFluxStyle.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(OpenFluxStyle.orange)
        .navigationTitle("Скорость")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Server

    private var serverSection: some View {
        Section {
            NavigationLink {
                SpeedTestServerPicker(serverID: $serverID, serverLabel: $serverLabel)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(serverLabel.isEmpty ? "Автоматически (ближайший)" : serverLabel)
                    if !serverID.isEmpty {
                        Text("id \(serverID)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        } header: {
            Text("Сервер")
        }
        .listRowBackground(OpenFluxStyle.surface)
    }

    // MARK: Parameters

    private var testSection: some View {
        Section {
            Picker("Направление", selection: $direction) {
                Text("Загрузка").tag("download")
                Text("Отдача").tag("upload")
                Text("Оба").tag("both")
            }
            .pickerStyle(.segmented)

            DisclosureGroup("Параметры", isExpanded: $showParameters) {
                Picker("Потоки", selection: $threads) {
                    ForEach(threadChoices, id: \.self) { Text("\($0)").tag($0) }
                }
                Stepper("Длительность: \(durationSec) с", value: $durationSec, in: 5...60, step: 5)
                Toggle("Точный замер", isOn: $research)
                Text("Точный замер исключает разогрев и позволяет сравнивать разное число потоков.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("Тест")
        } footer: {
            // 🚨 BOTH HALVES OF THIS USED TO BE FALSE.
            //   - "the engine stops early" is not true in Research mode, whose
            //     toggle is eleven lines above: two adjacent controls contradicting
            //     each other on screen. The sentence is now conditional.
            //   - "the test stops if you leave it" was implemented NOWHERE. iOS
            //     suspends the process; the phase's timer then fires on resume,
            //     the duration spans the suspended interval, and the result is a
            //     collapsed rate explained by a warning about the estimator —
            //     precisely the "true statement offered as the wrong reason" this
            //     screen's own warnings are split to avoid. Say what actually
            //     happens instead of promising a stop nothing performs.
            Text(research
                 ? "Держите приложение открытым до завершения теста. iOS приостанавливает его в фоне."
                 : "Тест завершится раньше, если скорость стабилизируется. Держите приложение открытым.")
        }
        .listRowBackground(OpenFluxStyle.surface)
    }

    // MARK: Run

    private var runSection: some View {
        Section {
            if runner.isRunning {
                HStack {
                    ProgressView()
                    Text(runner.progress.stage.isEmpty ? "Измеряем…" : "Измеряем: \(runner.progress.stage)")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Стоп") { runner.cancel() }
                        .foregroundColor(.red)
                }
                // Surfaced WHILE running, not only afterwards: if the route
                // moves now, the user can stop and re-run instead of finding out
                // at the end that the number belongs to neither path.
                if !runner.pathTrace.isAttributable {
                    Label(runner.pathTrace.label, systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else {
                if let refusal = runner.refusal {
                    Label(refusal, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                Button {
                    runner.start(serverID: serverID, serverLabel: serverLabel,
                                 threads: threads, direction: direction,
                                 durationSec: durationSec, research: research)
                } label: {
                    Text("НАЧАТЬ ТЕСТ").font(.system(size: 16, weight: .bold)).frame(maxWidth: .infinity)
                }
            }
        }
        .listRowBackground(OpenFluxStyle.surface)
    }

}
