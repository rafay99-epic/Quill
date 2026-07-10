import SwiftUI
import Cocoa
import Carbon.HIToolbox
import LaunchAtLogin
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var updaterViewModel: UpdaterViewModel
    @EnvironmentObject private var menuBarManager: MenuBarManager
    @EnvironmentObject private var recordingShortcutManager: RecordingShortcutManager
    @EnvironmentObject private var recorderUIManager: RecorderUIManager
    // Recording/data retention — same keys the History panel and AudioCleanupManager use,
    // surfaced here so the setting is reachable from Settings, not only History.
    @AppStorage(CleanupSettingsKeys.isAudioCleanupEnabled) private var isAudioCleanupEnabled = true
    @AppStorage(CleanupSettingsKeys.audioRetentionPeriod) private var audioRetentionPeriod = 10
    @State private var showEraseAllConfirmation = false
    @State private var isErasingAllData = false
    @State private var eraseResultMessage: String?
    @AppStorage("hasCompletedOnboardingV2") private var hasCompletedOnboardingV2 = true
    @AppStorage("ShowMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("PrewarmModelOnWake") private var prewarmModelOnWake = false
    @AppStorage("restoreClipboardAfterPaste") private var restoreClipboardAfterPaste = true
    @AppStorage("clipboardRestoreDelay") private var clipboardRestoreDelay = 2.0
    @AppStorage("keepTranscriptOnClipboard") private var keepTranscriptOnClipboard = true
    @AppStorage(PasteMethod.userDefaultsKey) private var pasteMethodRawValue = PasteMethod.standard.rawValue
    @AppStorage(AppAppearancePreference.userDefaultsKey) private var appAppearancePreference = AppAppearancePreference.system
    @AppStorage(AppLanguagePreference.userDefaultsKey) private var appLanguagePreference = AppLanguagePreference.systemValue
    @State private var showResetOnboardingAlert = false
    @State private var showLanguageRestartAlert = false
    @State private var hasCancelRecordingShortcut = ShortcutStore.shortcut(for: .cancelRecorder) != nil
    @State private var cancelRecordingShortcutRecorderResetID = 0

    @State private var isMiddleClickExpanded = false
    @State private var isRestoreClipboardExpanded = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Primary Shortcut") {
                    HStack(spacing: 8) {
                        Spacer()
                        shortcutModePicker(binding: $recordingShortcutManager.primaryRecordingShortcutMode)
                        ShortcutRecorder(action: .primaryRecording) {
                            recordingShortcutManager.primaryRecordingShortcut = .custom
                            recordingShortcutManager.updateShortcutStatus()
                        }
                        .controlSize(.small)
                    }
                }

                if recordingShortcutManager.secondaryRecordingShortcut != .none {
                    LabeledContent("Secondary Shortcut") {
                        HStack(spacing: 8) {
                            Spacer()
                            shortcutModePicker(binding: $recordingShortcutManager.secondaryRecordingShortcutMode)
                            ShortcutRecorder(action: .secondaryRecording) {
                                recordingShortcutManager.secondaryRecordingShortcut = .custom
                                recordingShortcutManager.updateShortcutStatus()
                            }
                            .controlSize(.small)
                            Button {
                                withAnimation { recordingShortcutManager.secondaryRecordingShortcut = .none }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if recordingShortcutManager.secondaryRecordingShortcut == .none {
                    Button("Add Second Shortcut") {
                        withAnimation { recordingShortcutManager.secondaryRecordingShortcut = .custom }
                    }
                }
            } header: {
                Text("Shortcuts")
            }

            Section("Additional Shortcuts") {
                LabeledContent("Paste Last Transcription (Original)") {
                    ShortcutRecorder(action: .pasteLastTranscription) {
                        recordingShortcutManager.updateShortcutStatus()
                    }
                        .controlSize(.small)
                }

                LabeledContent("Paste Last Transcription (Enhanced)") {
                    ShortcutRecorder(action: .pasteLastEnhancement) {
                        recordingShortcutManager.updateShortcutStatus()
                    }
                        .controlSize(.small)
                }

                LabeledContent("Retry Last Transcription") {
                    ShortcutRecorder(action: .retryLastTranscription) {
                        recordingShortcutManager.updateShortcutStatus()
                    }
                        .controlSize(.small)
                }

                LabeledContent("Cancel Recording") {
                    HStack(spacing: 8) {
                        ShortcutRecorder(
                            action: .cancelRecorder,
                            defaultShortcut: Self.defaultCancelRecordingShortcut
                        ) {
                            hasCancelRecordingShortcut = true
                        }
                            .id(cancelRecordingShortcutRecorderResetID)
                            .controlSize(.small)

                        Button {
                            ShortcutStore.setShortcut(nil, for: .cancelRecorder)
                            hasCancelRecordingShortcut = false
                            cancelRecordingShortcutRecorderResetID += 1
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.plain)
                        .help("Reset to default")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.shortcutDidChange)) { notification in
                    guard let action = notification.object as? ShortcutAction, action == .cancelRecorder else { return }
                    hasCancelRecordingShortcut = ShortcutStore.shortcut(for: .cancelRecorder) != nil
                }

                ExpandableSettingsRow(
                    isExpanded: $isMiddleClickExpanded,
                    isEnabled: $recordingShortcutManager.isMiddleClickToggleEnabled,
                    label: "Middle-Click Recording"
                ) {
                    LabeledContent("Activation Delay") {
                        HStack {
                            TextField("", value: $recordingShortcutManager.middleClickActivationDelay, formatter: {
                                let formatter = NumberFormatter()
                                formatter.minimum = 0
                                return formatter
                            }())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                            Text("ms")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section("Pasting") {
                Toggle(isOn: $keepTranscriptOnClipboard) {
                    HStack(spacing: 4) {
                        Text("Copy Transcript to Clipboard")
                        InfoTip("Keeps every transcription on the clipboard after pasting, so you can paste it manually with Cmd+V if automatic pasting fails. While enabled, your previous clipboard content is not restored.")
                    }
                }

                ExpandableSettingsRow(
                    isExpanded: $isRestoreClipboardExpanded,
                    isEnabled: $restoreClipboardAfterPaste,
                    label: "Keep Clipboard Content",
                    infoMessage: "Quill temporarily uses the clipboard to paste transcription. When enabled, it restores your previous clipboard content after the selected delay. When disabled, the pasted transcription stays on your clipboard. Has no effect while Copy Transcript to Clipboard is on."
                ) {
                    Picker("Restore Delay", selection: $clipboardRestoreDelay) {
                        Text("250ms").tag(0.25)
                        Text("500ms").tag(0.5)
                        Text("1s").tag(1.0)
                        Text("2s").tag(2.0)
                        Text("3s").tag(3.0)
                        Text("4s").tag(4.0)
                        Text("5s").tag(5.0)
                    }
                }

                Picker(selection: $pasteMethodRawValue) {
                    ForEach(PasteMethod.allCases) { method in
                        Text(method.displayName).tag(method.rawValue)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Paste Method")
                        InfoTip("Default uses simulated Cmd+V key events. AppleScript can help when custom keyboard layouts do not paste correctly.")
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: pasteMethodRawValue) { _, newValue in
                    guard let method = PasteMethod(rawValue: newValue) else {
                        pasteMethodRawValue = PasteMethod.standard.rawValue
                        return
                    }
                    PasteMethod.setCurrent(method)
                }
            }

            Section("Interface") {
                Picker("Appearance", selection: $appAppearancePreference) {
                    ForEach(AppAppearancePreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: appAppearancePreference) { _, newValue in
                    newValue.apply()
                }

                Picker("Language", selection: $appLanguagePreference) {
                    ForEach(AppLanguagePreference.availableOptions) { option in
                        Text(option.displayName).tag(option.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: appLanguagePreference) { oldValue, newValue in
                    guard oldValue != newValue else { return }
                    let normalizedValue = AppLanguagePreference.normalizedRawValue(newValue)
                    if normalizedValue != newValue {
                        appLanguagePreference = normalizedValue
                        return
                    }
                    AppLanguagePreference.apply(rawValue: normalizedValue)
                    showLanguageRestartAlert = true
                }

                Picker("Recorder Style", selection: $recorderUIManager.recorderPanelStyle) {
                    ForEach(RecorderPanelStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)

            }

            Section("General") {
                Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
                    .onChange(of: showMenuBarIcon) { _, newValue in
                        // Never let the user hide both the menu bar icon and the
                        // dock icon — that strands the app with no way back. If the
                        // menu bar icon is going away while the dock is hidden,
                        // bring the dock icon back so Settings stays reachable.
                        if !newValue && menuBarManager.isMenuBarOnly {
                            menuBarManager.isMenuBarOnly = false
                        }
                    }

                Toggle("Hide Dock Icon", isOn: $menuBarManager.isMenuBarOnly)
                    .disabled(!showMenuBarIcon)
                    .help(showMenuBarIcon ? "" : "Show the menu bar icon first — hiding both would leave no way to open the app.")

                LaunchAtLogin.Toggle("Launch at Login")

                Toggle("Prewarm Model on Wake", isOn: $prewarmModelOnWake)
                    .help("Runs a quick local transcription right after your Mac wakes so your first dictation is faster. This uses some battery on every wake — leave it off for the best battery life.")

                HStack {
                    Button("Check for Updates") {
                        updaterViewModel.checkForUpdates()
                    }
                    .disabled(!updaterViewModel.canCheckForUpdates)

                    Button("Reset Onboarding") {
                        showResetOnboardingAlert = true
                    }
                }
            }

            Section {
                Toggle("Auto-delete Audio Files", isOn: $isAudioCleanupEnabled)

                if isAudioCleanupEnabled {
                    Picker("Delete Recordings After", selection: $audioRetentionPeriod) {
                        Text("Immediately").tag(0)
                        Text("1 day").tag(1)
                        Text("3 days").tag(3)
                        Text("7 days").tag(7)
                        Text("10 days").tag(10)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                }

                Button(role: .destructive) {
                    showEraseAllConfirmation = true
                } label: {
                    Text(isErasingAllData ? "Erasing…" : "Erase All Data…")
                }
                .disabled(isErasingAllData)
            } header: {
                Text("Recordings & Data")
            } footer: {
                Text("Auto-delete old recordings while keeping transcripts. “Erase All Data” permanently deletes every transcript, statistic, and audio recording.")
            }

            Section("Diagnostics") {
                DiagnosticsSettingsView()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .alert("Reset Onboarding", isPresented: $showResetOnboardingAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                DispatchQueue.main.async {
                    hasCompletedOnboardingV2 = false
                }
            }
        } message: {
            Text("You'll see the introduction screens again the next time you launch the app.")
        }
        .alert("Restart Quill to Apply Language", isPresented: $showLanguageRestartAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your language change will take full effect after you quit and reopen Quill.")
        }
        .alert("Erase All Data?", isPresented: $showEraseAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Erase Everything", role: .destructive) { eraseAllData() }
        } message: {
            Text("This permanently deletes every transcript, statistic, and saved audio recording. This cannot be undone.")
        }
        .alert("Data Erased", isPresented: Binding(
            get: { eraseResultMessage != nil },
            set: { if !$0 { eraseResultMessage = nil } }
        )) {
            Button("OK", role: .cancel) { eraseResultMessage = nil }
        } message: {
            Text(eraseResultMessage ?? "")
        }
    }

    /// Permanently deletes every transcript, session metric, and saved recording.
    private func eraseAllData() {
        guard !isErasingAllData else { return }
        isErasingAllData = true
        Task { @MainActor in
            defer { isErasingAllData = false }
            var deletedTranscripts = 0
            var deletedMetrics = 0
            do {
                let transcriptions = try modelContext.fetch(FetchDescriptor<Transcription>())
                deletedTranscripts = transcriptions.count
                for transcription in transcriptions { modelContext.delete(transcription) }

                let metrics = try modelContext.fetch(FetchDescriptor<SessionMetric>())
                deletedMetrics = metrics.count
                for metric in metrics { modelContext.delete(metric) }

                try modelContext.save()
            } catch {
                eraseResultMessage = "Could not erase the database: \(error.localizedDescription)"
                return
            }

            // Drop every saved recording by removing and recreating the folder.
            let recordings = QuillPaths.recordings
            try? FileManager.default.removeItem(at: recordings)
            try? FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)

            // Recompute the dashboard (it reads from SessionMetric).
            NotificationCenter.default.post(name: .sessionMetricsDidChange, object: nil)

            eraseResultMessage = "Deleted \(deletedTranscripts) transcripts, \(deletedMetrics) statistics, and all audio recordings."
        }
    }

    private static let defaultCancelRecordingShortcut = Shortcut.key(
        keyCode: UInt16(kVK_Escape),
        modifierFlags: []
    )

    @ViewBuilder
    private func shortcutModePicker(binding: Binding<RecordingShortcutManager.Mode>) -> some View {
        Picker("", selection: binding) {
            ForEach(RecordingShortcutManager.Mode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .labelsHidden()
        .fixedSize()
    }
}

extension Text {
    func settingsDescription() -> some View {
        self
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
