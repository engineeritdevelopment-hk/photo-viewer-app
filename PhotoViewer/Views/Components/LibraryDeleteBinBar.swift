import SwiftUI

struct LibraryDeleteBinBar: View {
    @Bindable var model: LibraryViewModel
    @Binding var showDeleteConfirm: Bool
    var embeddedInBottomChrome: Bool = false

    var body: some View {
        if model.isViewingDeleteBin {
            HStack(spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete bin · \(model.deleteBinCount)")
                            .font(.subheadline.weight(.semibold))
                        if model.isViewingDeleteBin {
                            Text("Review before deleting from source")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Drag photos here to stage for deletion")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(.orange)
                }

                Spacer(minLength: 8)

                Button("Remove from bin") {
                    if model.selectedPaths.isEmpty {
                        model.emptyDeleteBin()
                    } else {
                        model.removeFromDeleteBin(paths: Array(model.selectedPaths))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.deleteBinCount == 0)

                Button("Delete from source…", role: .destructive) {
                    showDeleteConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.red)
                .disabled(model.deleteBinCount == 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Group {
                    if embeddedInBottomChrome {
                        ZStack {
                            Color.orange.opacity(0.12)
                        }
                        .background(.regularMaterial)
                    } else {
                        Color.orange.opacity(0.08)
                    }
                }
            }
            .overlay(alignment: .top) {
                if embeddedInBottomChrome { Divider() }
            }
            .overlay(alignment: .bottom) {
                if !embeddedInBottomChrome { Divider() }
            }
            .shadow(color: embeddedInBottomChrome ? .black.opacity(0.1) : .clear, radius: 8, y: -2)
            .photoPathsDropDestination(
                acceptsDrop: true,
                highlight: Color.orange.opacity(0.35)
            ) { paths in
                model.addToDeleteBin(paths: paths)
                return true
            }
        }
    }
}