import SwiftUI

enum SidebarListMetrics {
    static let rowInsets = EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 6)
    static let compactRowInsets = EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 6)
    static let iconWidth: CGFloat = 16
    static let rowHorizontalPadding: CGFloat = 5
    static let rowVerticalPadding: CGFloat = 3
    static let compactRowHorizontalPadding: CGFloat = 4
    static let compactRowVerticalPadding: CGFloat = 2
}

enum SidebarRowDensity {
    case standard
    case compact
}

/// Filter, albums, and bin rows share one label layout so icons and titles line up.
struct SidebarStandardLabel: View {
    let title: String
    let systemImage: String
    var iconForeground: Color = .secondary
    var titleForeground: Color = .primary

    var body: some View {
        Label {
            Text(title)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(titleForeground)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconForeground)
                .frame(width: SidebarListMetrics.iconWidth, alignment: .center)
        }
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum SidebarRowEmphasis {
    case standard
    /// Delete bin — orange tint, primary text when selected (readable on tinted background).
    case warning
}

/// macOS sidebar row chrome; List(selection:) does not highlight plain `Button` rows.
struct SidebarListRowButtonStyle: ButtonStyle {
    var isSelected: Bool
    var emphasis: SidebarRowEmphasis = .standard
    var density: SidebarRowDensity = .standard

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(foregroundColor)
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowFill(isPressed: configuration.isPressed))
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var verticalPadding: CGFloat {
        density == .compact ? SidebarListMetrics.compactRowVerticalPadding : SidebarListMetrics.rowVerticalPadding
    }

    private var horizontalPadding: CGFloat {
        density == .compact ? SidebarListMetrics.compactRowHorizontalPadding : SidebarListMetrics.rowHorizontalPadding
    }

    private var foregroundColor: Color {
        switch emphasis {
        case .standard:
            return isSelected ? Color.accentColor : Color.primary
        case .warning:
            return Color.primary
        }
    }

    private func rowFill(isPressed: Bool) -> Color {
        if isSelected {
            switch emphasis {
            case .standard:
                return Color.accentColor.opacity(0.22)
            case .warning:
                return Color.orange.opacity(0.32)
            }
        }
        if isPressed {
            return Color.primary.opacity(0.08)
        }
        return Color.clear
    }
}

extension View {
    func sidebarListRowInsets(compact: Bool = false) -> some View {
        listRowInsets(compact ? SidebarListMetrics.compactRowInsets : SidebarListMetrics.rowInsets)
    }

    /// Non-button placeholder row (e.g. “New album…”) aligned with selectable rows.
    func sidebarPlaceholderRowStyle() -> some View {
        padding(.vertical, SidebarListMetrics.rowVerticalPadding)
            .padding(.horizontal, SidebarListMetrics.rowHorizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sidebarListRowInsets()
    }
}