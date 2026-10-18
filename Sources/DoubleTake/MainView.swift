import DoubleTakeCore
import SwiftUI

enum SidebarItem: Hashable {
    case general
    case shortcut(UUID)
}

struct MainView: View {
    @Environment(AppState.self) private var state
    @State private var selection: SidebarItem? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape")
                    .tag(SidebarItem.general)
                Section("Shortcuts") {
                    ForEach(state.shortcuts) { s in
                        ShortcutRow(id: s.id)
                            .tag(SidebarItem.shortcut(s.id))
                            .contextMenu {
                                Button("Duplicate") { duplicate(s) }
                                Button("Delete", role: .destructive) { delete(s.id) }
                            }
                    }
                    .onMove { state.shortcuts.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .navigationSplitViewColumnWidth(min: 230, ideal: 260)
            .safeAreaInset(edge: .top) { addButton }
            .onDeleteCommand {
                if case .shortcut(let id) = selection { delete(id) }
            }
        } detail: {
            VStack(spacing: 0) {
                if !state.isTrusted {
                    PermissionBanner()
                }
                detail
            }
        }
        .frame(minWidth: 780, minHeight: 520)
        .onAppear { NSApp.activate() }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .shortcut(let id) where state.shortcut(withID: id) != nil:
            ShortcutEditor(shortcut: Binding(
                get: { state.shortcut(withID: id) ?? Shortcut(name: "", triggers: [], action: Action()) },
                set: { state.update($0) }
            ), onDelete: { delete(id) })
            .id(id)
        default:
            GeneralView()
        }
    }

    private var addButton: some View {
        Menu {
            Button("Blank Shortcut") {
                add(Shortcut(name: "New Shortcut", triggers: [Trigger()], action: Action()))
            }
            ForEach(Presets.groups) { group in
                Section(group.title) {
                    ForEach(group.presets) { preset in
                        Button(preset.title) { add(preset.make()) }
                    }
                }
            }
        } label: {
            Label("New Shortcut", systemImage: "plus.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .menuStyle(.button)
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
        .help("Add a blank shortcut or start from a preset")
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private func add(_ shortcut: Shortcut) {
        state.shortcuts.append(shortcut)
        selection = .shortcut(shortcut.id)
    }

    private func duplicate(_ shortcut: Shortcut) {
        var copy = shortcut
        copy.id = UUID()
        copy.name += " Copy"
        copy.enabled = false
        copy.triggers = copy.triggers.map { var t = $0; t.id = UUID(); return t }
        add(copy)
    }

    private func delete(_ id: UUID) {
        guard let index = state.shortcuts.firstIndex(where: { $0.id == id }) else { return }
        state.remove(id)
        if state.shortcuts.isEmpty {
            selection = .general
        } else {
            selection = .shortcut(state.shortcuts[min(index, state.shortcuts.count - 1)].id)
        }
    }
}

struct ShortcutRow: View {
    @Environment(AppState.self) private var state
    let id: UUID

    var body: some View {
        if let s = state.shortcut(withID: id) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name.isEmpty ? "Untitled" : s.name)
                    Text("\(KeyNames.summary(s)) → \(s.action.summary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("Enabled", isOn: Binding(
                    get: { s.enabled },
                    set: { var copy = s; copy.enabled = $0; state.update(copy) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
            .opacity(s.enabled ? 1 : 0.6)
        }
    }
}

struct PermissionBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("DoubleTake needs Accessibility access")
                    .font(.headline)
                Text("Turn on DoubleTake in System Settings › Privacy & Security › Accessibility so it can see your key presses. It starts working the moment you do.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Settings") { state.requestPermission() }
        }
        .padding(12)
        .background(.orange.opacity(0.12))
    }
}
