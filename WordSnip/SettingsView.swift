import ServiceManagement
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var shortcut: CaptureShortcut
    @Published var showMenuBarIcon: Bool
    @Published var launchAtLogin: Bool
    @Published var message: String?

    var onShortcutChange: ((CaptureShortcut) -> Bool)?
    var onMenuBarChange: ((Bool) -> Void)?

    init() {
        shortcut = CaptureShortcut(rawValue: UserDefaults.standard.integer(forKey: "captureShortcut")) ?? .controlShift2
        showMenuBarIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setShortcut(_ value: CaptureShortcut) {
        guard onShortcutChange?(value) == true else {
            message = "That shortcut is unavailable. Choose another."
            return
        }
        shortcut = value
        UserDefaults.standard.set(value.rawValue, forKey: "captureShortcut")
        message = nil
    }

    func setMenuBarIcon(_ value: Bool) {
        showMenuBarIcon = value
        UserDefaults.standard.set(value, forKey: "showMenuBarIcon")
        onMenuBarChange?(value)
    }

    func setLaunchAtLogin(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            message = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            message = "Could not change Login Items: \(error.localizedDescription)"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var onCapture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Word Snip").font(.title2.bold())
                    Text("Select text anywhere on your screen and copy it.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Text("Capture shortcut")
                Spacer()
                Picker("Capture shortcut", selection: Binding(
                    get: { model.shortcut },
                    set: { model.setShortcut($0) }
                )) {
                    ForEach(CaptureShortcut.allCases) { shortcut in
                        Text(shortcut.title).tag(shortcut)
                    }
                }
                .labelsHidden()
                .frame(width: 125)
            }

            Toggle("Show menu bar icon", isOn: Binding(
                get: { model.showMenuBarIcon },
                set: { model.setMenuBarIcon($0) }
            ))

            Toggle("Launch at login", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            Text("Open settings anytime with ⌃⌥, even if the menu bar icon is hidden.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message = model.message {
                Text(message).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Capture Text Now", action: onCapture)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460)
    }
}
