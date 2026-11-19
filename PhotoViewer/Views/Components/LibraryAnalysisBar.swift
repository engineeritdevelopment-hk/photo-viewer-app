import SwiftUI

/// Legacy wrapper — prefer `LibraryAnalysisSection`.
struct LibraryAnalysisBar: View {
    @Bindable var model: LibraryViewModel

    var body: some View {
        HStack {
            Text("Analysis")
                .font(.caption)
                .foregroundStyle(.secondary)
            LibraryAnalysisControls(model: model)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.35))
        .overlay(alignment: .bottom) { Divider() }
    }
}