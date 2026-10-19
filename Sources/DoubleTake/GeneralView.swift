import SwiftUI

struct GeneralView: View {
    @Environment(AppState.self) private var state
    @State private var confirmRestore = false
    @State private var cliInstalled = Installer.isCLIInstalled
    @State private var cliError: String?
    @State private var approvedScripts = AdminScripts.approvedCount()
    private let updates = UpdateController.shared

    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                Toggle("Enable DoubleTake", isOn: $state.settings.isEnabled)
                Toggle("Start at login", isOn: $state.launchAtLogin)
            } footer: {
                Text("DoubleTake runs in the background. Close this window and your shortcuts keep working; open DoubleTake from Applications (or run `doubletake open`) to get back here.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Double-tap speed") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Slider(value: $state.settings.doubleTapInterval, in: 0.15...0.6) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("Fast")
                        } maximumValueLabel: {
                            Text("Slow")
                        }
                        Text("Up to \(Int(state.settings.doubleTapInterval * 1000)) ms between taps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 320)
                }
                LabeledContent("Simultaneous-key window") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Slider(value: $state.settings.chordWindow, in: 0.03...0.2) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("Tight")
                        } maximumValueLabel: {
                            Text("Loose")
                        }
                        Text("Keys within \(Int(state.settings.chordWindow * 1000)) ms count as pressed together (J + K style combos)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(maxWidth: 320)
                }
            } header: {
                Text("Timing")
            }

            Section {
                LabeledContent("Command-line tool") {
                    if cliInstalled {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Install `doubletake`") {
                            do {
                                try Installer.installCLI()
                                cliError = nil
                            } catch {
                                cliError = error.localizedDescription
                            }
                            cliInstalled = Installer.isCLIInstalled
                        }
                        .disabled(Installer.appBundleURL == nil)
                    }
                }
                if let cliError {
                    Text(cliError).font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Command Line")
            } footer: {
                Text("Manage shortcuts from Terminal or let an AI assistant do it: run `doubletake help`, or `doubletake help --llm` for the full reference.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Version \(CLI.version)") {
                    HStack {
                        updateStatus
                        Button("Check for Updates") {
                            Task { await updates.checkAndInstall() }
                        }
                        .disabled(updates.isBusy)
                    }
                }
                Toggle("Check for updates when DoubleTake opens", isOn: $state.settings.checkForUpdatesOnLaunch)
            } header: {
                Text("Updates")
            } footer: {
                Text("Checking for updates is the only time DoubleTake connects to the internet. It asks GitHub for the latest release; if there's a newer one, it downloads and installs it, then reopens."
                     + (Updater.isAdHocSigned ? " macOS then asks you to switch on Accessibility for it again." : ""))
                    .foregroundStyle(.secondary)
            }

            Section("Status") {
                LabeledContent("Accessibility access") {
                    if state.isTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") { state.requestPermission() }
                    }
                }
                LabeledContent("Administrator scripts") {
                    HStack {
                        Text(approvedScripts == 0 ? "None approved" : "\(approvedScripts) approved")
                            .foregroundStyle(.secondary)
                        if approvedScripts > 0 {
                            Button("Revoke All…") {
                                try? AdminScripts.revokeAll()
                                approvedScripts = AdminScripts.approvedCount()
                            }
                        }
                    }
                }
                LabeledContent("Last triggered") {
                    if let last = state.lastFired {
                        Text("\(last.name), \(last.date.formatted(.relative(presentation: .named)))")
                    } else {
                        Text("Nothing yet").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Show Config File in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppState.configURL])
                }
                Button("Restore Default Shortcuts…", role: .destructive) { confirmRestore = true }
                Button("Quit DoubleTake (stops all shortcuts)") { NSApp.terminate(nil) }
                Button("Uninstall DoubleTake…", role: .destructive) { confirmUninstall() }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Replace all shortcuts with the defaults?", isPresented: $confirmRestore) {
            Button("Restore Defaults", role: .destructive) { state.restoreDefaults() }
        } message: {
            Text("Your current shortcuts will be deleted.")
        }
    }

    private func confirmUninstall() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall DoubleTake?"
        let keep = Installer.uninstallPlan(deleteSettings: false)
        alert.informativeText = keep.map { "• " + $0 }.joined(separator: "\n")
        let deleteSettings = NSButton(checkboxWithTitle: "Also delete my shortcuts and settings", target: nil, action: nil)
        alert.accessoryView = deleteSettings
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try Installer.uninstall(deleteSettings: deleteSettings.state == .on)
            NSApp.terminate(nil)
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = "Couldn't finish uninstalling DoubleTake."
            failure.runModal()
        }
    }

    @ViewBuilder private var updateStatus: some View {
        switch updates.phase {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
            Text("Checking…").foregroundStyle(.secondary)
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .downloading(let version):
            ProgressView().controlSize(.small)
            Text("Downloading \(version.description)…").foregroundStyle(.secondary)
        case .installing(let version):
            ProgressView().controlSize(.small)
            Text("Installing \(version.description)…").foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .lineLimit(3)
                .help(message)
        }
    }
}
