import SwiftUI

struct PermissionsChecklistView: View {
    @State private var snapshot = PermissionManager.current()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Permissions", systemImage: "lock.shield")
                    .font(.headline)
                Spacer()
                if snapshot.allGranted {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label("Action needed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }

            permissionRow(
                title: "Microphone",
                granted: snapshot.microphone,
                actionTitle: "Open Settings",
                action: PermissionManager.openMicrophoneSettings
            )

            permissionRow(
                title: "Accessibility",
                granted: snapshot.accessibility,
                actionTitle: "Open Settings",
                action: PermissionManager.openAccessibilitySettings
            )

            permissionRow(
                title: "Input Monitoring",
                granted: snapshot.inputMonitoring,
                actionTitle: "Open Settings",
                action: PermissionManager.openInputMonitoringSettings
            )

            if !snapshot.inputMonitoring {
                Text("If LocalVoice does not appear here, click + and add /Applications/LocalVoice.app manually, then relaunch the app.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Button("Request Missing Permissions") {
                    PermissionManager.requestMissingPermissions()
                }
                .buttonStyle(.bordered)

                Button("Refresh") {
                    refresh()
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            refresh()
        }
    }

    private func permissionRow(title: String, granted: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(granted ? .green : .red)
            Text(title)
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.borderless)
        }
    }

    private func refresh() {
        snapshot = PermissionManager.current()
    }
}
