import SwiftUI

struct PermissionsChecklistView: View {
    @State private var snapshot = PermissionManager.current()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Permissions")
                        .font(.headline)
                    Text("Required for recording, global hotkey detection, and direct insertion.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                LVBadge(
                    snapshot.allGranted ? "Ready" : "Action needed",
                    systemImage: snapshot.allGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tint: snapshot.allGranted ? LVStyle.ready : LVStyle.warning
                )
            }

            permissionRow(
                title: "Microphone",
                subtitle: "Capture your voice locally.",
                granted: snapshot.microphone,
                action: PermissionManager.openMicrophoneSettings
            )

            permissionRow(
                title: "Accessibility",
                subtitle: "Insert text into the active app.",
                granted: snapshot.accessibility,
                action: PermissionManager.openAccessibilitySettings
            )

            permissionRow(
                title: "Input Monitoring",
                subtitle: "Detect the Right Command hotkey globally.",
                granted: snapshot.inputMonitoring,
                action: PermissionManager.openInputMonitoringSettings
            )

            if !snapshot.inputMonitoring {
                Text("If LocalVoice does not appear in Input Monitoring, click +, add /Applications/LocalVoice.app manually, then relaunch the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LVStyle.warning.opacity(0.10))
                    )
            }

            HStack(spacing: 8) {
                Button {
                    PermissionManager.requestMissingPermissions()
                    refresh()
                } label: {
                    Label("Request Missing", systemImage: "hand.raised")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear { refresh() }
    }

    private func permissionRow(title: String, subtitle: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? LVStyle.ready : LVStyle.error)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                LVBadge("Granted", tint: LVStyle.ready)
            } else {
                Button("Open Settings", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LVStyle.groupedBackground.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(LVStyle.separator, lineWidth: 0.5)
        )
    }

    private func refresh() {
        snapshot = PermissionManager.current()
    }
}
