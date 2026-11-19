import SwiftUI

struct AppInfoButton: View {
    enum Style {
        case compact
        case prominent
        /// Plain chrome in the system title bar (no tint or badge-like fill).
        case titlebar
    }

    @Bindable var appUpdate: AppUpdateModel
    @State private var showAbout = false
    var style: Style = .prominent

    private var iconSize: CGFloat {
        switch style {
        case .prominent: return 15
        case .titlebar: return 14
        case .compact: return SidebarSectionToolbarMetrics.iconPointSize
        }
    }

    private var hitSide: CGFloat {
        switch style {
        case .titlebar: return 22
        case .prominent: return 26
        case .compact: return SidebarSectionToolbarMetrics.hitSide
        }
    }

    private var iconName: String {
        style == .titlebar ? "info.circle" : "info.circle.fill"
    }

    var body: some View {
        Button {
            showAbout = true
        } label: {
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .medium))
                .symbolRenderingMode(style == .titlebar ? .monochrome : .hierarchical)
                .foregroundStyle(foregroundStyle)
                .frame(width: hitSide, height: hitSide)
                .contentShape(RoundedRectangle(cornerRadius: SidebarSectionToolbarMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(AppInfoButtonStyle(style: style))
        .help("About Photo Viewer — version and updates")
        .popover(isPresented: $showAbout, arrowEdge: .bottom) {
            AppAboutPopover {
                showAbout = false
                Task { await appUpdate.checkForUpdates(userInitiated: true) }
            }
        }
    }

    private var foregroundStyle: Color {
        switch style {
        case .titlebar, .compact:
            return Color.secondary
        case .prominent:
            return Color.accentColor
        }
    }
}

private struct AppInfoButtonStyle: ButtonStyle {
    var style: AppInfoButton.Style

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                switch style {
                case .titlebar:
                    EmptyView()
                case .prominent:
                    RoundedRectangle(cornerRadius: SidebarSectionToolbarMetrics.cornerRadius, style: .continuous)
                        .fill(
                            configuration.isPressed
                                ? Color.accentColor.opacity(0.18)
                                : Color.accentColor.opacity(0.1)
                        )
                case .compact:
                    RoundedRectangle(cornerRadius: SidebarSectionToolbarMetrics.cornerRadius, style: .continuous)
                        .fill(configuration.isPressed ? Color.primary.opacity(0.1) : Color.clear)
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