import DoubleTakeCore
import SwiftUI
import UniformTypeIdentifiers

struct ShortcutEditor: View {
    @Environment(AppState.self) private var state
    @Binding var shortcut: Shortcut
    let onDelete: () -> Void
    @State private var testResult: (ok: Bool, message: String)?

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $shortcut.name)
                Toggle("Enabled", isOn: $shortcut.enabled)
            }

            Section {
                ForEach($shortcut.triggers) { $trigger in
                    TriggerEditor(
                        trigger: $trigger,
                        conflicts: state.conflicts(for: trigger, in: shortcut),
                        onDelete: shortcut.triggers.count > 1 ? { remove(trigger.id) } : nil
                    )
                }
                Button("Add Another Trigger", systemImage: "plus") {
                    shortcut.triggers.append(Trigger())
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Triggers")
            } footer: {
                Text("Any of these runs the action. Taps must be quick and on their own — using a key as part of a normal shortcut never counts as a tap.")
                    .foregroundStyle(.secondary)
            }

            Section("Action") {
                ActionEditor(action: $shortcut.action)
                HStack {
                    Button("Test Action") {
                        testResult = nil
                        ActionRunner.run(shortcut.action) { error in
                            testResult = error.map { (false, $0) } ?? (true, "Ran successfully.")
                        }
                    }
                    if let testResult {
                        Label(testResult.message, systemImage: testResult.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(testResult.ok ? .green : .orange)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                Button("Delete Shortcut", role: .destructive, action: onDelete)
            }
        }
        .formStyle(.grouped)
        .onDisappear { state.cancelRecording() }
    }

    private func remove(_ id: UUID) {
        shortcut.triggers.removeAll { $0.id == id }
    }
}

struct TriggerEditor: View {
    @Binding var trigger: Trigger
    let conflicts: [String]
    let onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Kind", selection: $trigger.kind) {
                    Text("Tap").tag(TriggerKind.tap)
                    Text("Key Combo").tag(TriggerKind.combo)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                if trigger.kind == .tap {
                    Picker("Taps", selection: $trigger.tapCount) {
                        Text("Double").tag(2)
                        Text("Triple").tag(3)
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                RecorderButton(id: trigger.id, mode: trigger.kind == .tap ? .tap : .combo, title: recordedTitle) { result in
                    switch result {
                    case .tap(let code):
                        trigger.keyCode = code
                        trigger.eitherSide = false
                    case .combo(let modifiers, let keys):
                        trigger.modifiers = modifiers
                        trigger.keys = keys
                    case .keystroke:
                        break
                    }
                }

                Spacer()
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this trigger")
                }
            }

            if trigger.kind == .tap, KeyCode.hasSides(trigger.keyCode), let family = KeyCode.family(of: trigger.keyCode) {
                Toggle("Either \(KeyNames.familyName(family)) key (left or right)", isOn: $trigger.eitherSide)
                    .controlSize(.small)
            }
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !conflicts.isEmpty {
                Label("Also used by \(conflicts.joined(separator: ", ")). Only one will run.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private var recordedTitle: String? {
        guard trigger.isComplete else { return nil }
        switch trigger.kind {
        case .tap: return KeyNames.tapKeyName(trigger)
        case .combo: return KeyNames.comboName(trigger.modifiers, trigger.keys)
        }
    }

    private var hint: String? {
        switch trigger.kind {
        case .tap:
            guard trigger.isComplete, !KeyCode.isModifier(trigger.keyCode) else { return nil }
            return "The first press types normally; the second is used by DoubleTake."
        case .combo:
            if trigger.keys.count > 1 {
                return "Press these keys at the same moment. Each one waits a split second before typing, in case the other follows."
            }
            if trigger.keys.isEmpty && trigger.isComplete {
                return "Press and release these modifiers together without any other key."
            }
            return trigger.isComplete ? nil : "Click Record, then press the keys together and let go."
        }
    }
}

/// A button that captures the next key press (or combination) the user makes.
struct RecorderButton: View {
    @Environment(AppState.self) private var state
    let id: UUID
    let mode: KeyRecorder.Mode
    let title: String?
    let onResult: (KeyRecorder.Result) -> Void

    private var isRecording: Bool { state.recordingID == id }

    var body: some View {
        Button {
            if isRecording {
                state.cancelRecording()
            } else {
                state.startRecording(id: id, mode: mode, completion: onResult)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                    .foregroundStyle(isRecording ? .red : .secondary)
                Text(isRecording ? prompt : (title ?? "Record"))
                    .monospacedDigit()
            }
            .frame(minWidth: 150)
        }
        .disabled(!state.isTrusted)
        .help(state.isTrusted ? "Click, then press keys. Click again to cancel." : "Grant Accessibility access first.")
    }

    private var prompt: String {
        switch mode {
        case .tap: return "Tap a key…"
        case .combo: return "Press keys together…"
        case .keystroke: return "Press a shortcut…"
        }
    }
}

struct ActionEditor: View {
    @Binding var action: Action
    @State private var keystrokeRecorderID = UUID()
    @State private var availableShortcuts: [String] = []

    var body: some View {
        Picker("Do", selection: $action.type) {
            ForEach(ActionType.allCases, id: \.self) { Text($0.title).tag($0) }
        }

        switch action.type {
        case .system:
            Picker("Action", selection: $action.system) {
                ForEach(SystemAction.groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.actions, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
            if action.system == .dictation {
                Text("Starts dictation in whichever app is in front, through its Edit › Start Dictation menu item.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .openApp:
            LabeledContent("App") {
                HStack {
                    if !action.target.isEmpty {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: action.target))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(FileManager.default.displayName(atPath: action.target))
                    }
                    Button(action.target.isEmpty ? "Choose App…" : "Change…") { chooseApp() }
                }
            }
            Toggle("Hide the app instead if it's already in front", isOn: $action.toggleApp)

        case .openURL:
            TextField("URL or file", text: $action.target, prompt: Text("https://example.com or ~/Documents/notes.txt"))
            Button("Choose File or Folder…") { chooseFile() }

        case .shellScript:
            scriptEditor(placeholder: "Runs in zsh as a login shell, so your usual PATH and tools are available.")

        case .appleScript:
            scriptEditor(placeholder: "Example: tell application \"Music\" to playpause")

        case .runShortcut:
            HStack {
                TextField("Shortcut name", text: $action.target, prompt: Text("Name from the Shortcuts app"))
                Menu("Pick") {
                    ForEach(availableShortcuts, id: \.self) { name in
                        Button(name) { action.target = name }
                    }
                }
                .fixedSize()
                .disabled(availableShortcuts.isEmpty)
            }
            .task { availableShortcuts = await Self.loadShortcuts() }

        case .keystroke:
            LabeledContent("Keystroke") {
                RecorderButton(id: keystrokeRecorderID, mode: .keystroke, title: KeyNames.keystrokeName(action.keystroke)) { result in
                    if case .keystroke(let k) = result { action.keystroke = k }
                }
            }
            Text("Sends this key combination to the front app, as if you typed it.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .menuItem:
            TextField("Menu item", text: $action.target, prompt: Text("Edit > Start Dictation"))
            Text("Clicks a menu item in whichever app is in front. Give the full path with > between levels, or just the item's name.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func scriptEditor(placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $action.script)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
            Text(placeholder)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            action.target = url.path
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            action.target = url.path
        }
    }

    private static func loadShortcuts() async -> [String] {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .map(String.init)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }.value
    }
}
