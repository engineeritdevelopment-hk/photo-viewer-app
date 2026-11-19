import SwiftUI

enum SidebarSectionToolbarMetrics {
    static let iconPointSize: CGFloat = 11
    static let hitSide: CGFloat = 22
    static let cornerRadius: CGFloat = 5
    static let padding: CGFloat = 2
}

/// Edit / add controls in sidebar section headers — larger hit target and padding.
struct SidebarSectionIconButton: View {
    let systemImage: String
    var isEmphasized: Bool = false
    var role: ButtonRole?
    let help: String
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: SidebarSectionToolbarMetrics.iconPointSize, weight: .medium))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(foregroundColor)
                .frame(
                    width: SidebarSectionToolbarMetrics.hitSide,
                    height: SidebarSectionToolbarMetrics.hitSide
                )
                .contentShape(RoundedRectangle(cornerRadius: SidebarSectionToolbarMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(SidebarSectionIconButtonStyle())
        .help(help)
    }

    private var foregroundColor: Color {
        if role == .destructive { return Color.red }
        return isEmphasized ? Color.accentColor : Color.secondary
    }
}

struct SidebarSectionIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: SidebarSectionToolbarMetrics.cornerRadius, style: .continuous)
                    .fill(backgroundFill(isPressed: configuration.isPressed))
            }
    }

    private func backgroundFill(isPressed: Bool) -> Color {
        if isPressed {
            return Color.primary.opacity(0.1)
        }
        return Color.clear
    }
}

extension View {
    func sidebarSectionHeaderActionsLayout() -> some View {
        padding(.vertical, 3)
            .padding(.trailing, 2)
    }
}