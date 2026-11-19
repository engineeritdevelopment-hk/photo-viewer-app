import SwiftUI

struct AppInfoButton: View {
    @Environment(AppUpdateModel.self) private var appUpdate
    @State private var showAbout = false

    var body: some View {
        Button {
            showAbout = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: SidebarSectionToolbarMetrics.iconPointSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(
                    width: SidebarSectionToolbarMetrics.hitSide,
                    height: SidebarSectionToolbarMetrics.hitSide
                )
                .contentShape(RoundedRectangle(cornerRadius: SidebarSectionToolbarMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(SidebarSectionIconButtonStyle())
        .help("About Photo Viewer")
        .popover(isPresented: $showAbout, arrowEdge: .bottom) {
            AppAboutPopover {
                showAbout = false
                Task { await appUpdate.checkForUpdates(userInitiated: true) }
            }
        }
    }
}

private struct AppAboutPopover: View {
    let onCheckForUpdates: () -> Void

    private var marketingVersion: String {
        AppVersion.current()?.displayString ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Photo Viewer")
                    .font(.headline)
                Text("Browse and organize local photo libraries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Version")
                        .foregroundStyle(.secondary)
                    Text(marketingVersion)
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("Build")
                        .foregroundStyle(.secondary)
                    Text(buildNumber)
                        .textSelection(.enabled)
                }
            }
            .font(.callout)

            HStack {
                Spacer()
                Button("Check for Updates…", action: onCheckForUpdates)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }
}