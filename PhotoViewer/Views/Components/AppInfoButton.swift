import SwiftUI

struct AppInfoButton: View {
    enum Style {
        case compact
        case prominent
    }

    @Environment(AppUpdateModel.self) private var appUpdate
    @State private var showAbout = false
    var style: Style = .prominent

    private var iconSize: CGFloat {
        style == .prominent ? 15 : SidebarSectionToolbarMetrics.iconPointSize
    }

    private var hitSide: CGFloat {
        style == .prominent ? 26 : SidebarSectionToolbarMetrics.hitSide
    }

    var body: some View {
        Button {
            showAbout = true
        } label: {
            Image(systemName: "info.circle.fill")
                .font(.system(size: iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(style == .prominent ? Color.accentColor : Color.secondary)
                .frame(width: hitSide, height: hitSide)
                .contentShape(RoundedRectangle(cornerRadius: SidebarSectionToolbarMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(AppInfoButtonStyle(prominent: style == .prominent))
        .help("About Photo Viewer — version and updates")
        .popover(isPresented: $showAbout, arrowEdge: .bottom) {
            AppAboutPopover {
                showAbout = false
                Task { await appUpdate.checkForUpdates(userInitiated: true) }
            }
        }
    }
}

private struct AppInfoButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: SidebarSectionToolbarMetrics.cornerRadius, style: .continuous)
                        .fill(
                            configuration.isPressed
                                ? Color.accentColor.opacity(0.18)
                                : Color.accentColor.opacity(0.1)
                        )
                } else {
                    RoundedRectangle(cornerRadius: SidebarSectionToolbarMetrics.cornerRadius, style: .continuous)
                        .fill(configuration.isPressed ? Color.primary.opacity(0.1) : Color.clear)
                }
            }
    }
}

struct AppInfoSidebarHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            AppInfoButton(style: .prominent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Photo Viewer")
                    .font(.subheadline.weight(.semibold))
                if let version = AppVersion.current()?.displayString {
                    Text("Version \(version)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
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