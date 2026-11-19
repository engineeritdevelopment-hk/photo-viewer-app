import SwiftUI

struct LibraryHeaderBar: View {
    @Bindable var model: LibraryViewModel
    @Binding var excludedNames: String
    var onExport: () -> Void
    @State private var showFilenameRules = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.project.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(photoCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            gridToolbar
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var gridToolbar: some View {
        HStack(spacing: 2) {
            sortMenu
            toolbarDivider
            toolbarAction(
                title: "Export",
                systemImage: "square.and.arrow.up",
                help: "Export the selected sidebar album"
            ) {
                onExport()
            }
        }
        .padding(3)
        .background(toolbarChrome)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: Binding(
                get: { model.photoSort },
                set: { model.setPhotoSort($0) }
            )) {
                ForEach(LibraryPhotoSort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Divider()
            Button("Hide matching filenames…") {
                showFilenameRules = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Sort")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(model.photoSort.shortTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort order: \(model.photoSort.title)")
        .popover(isPresented: $showFilenameRules, arrowEdge: .bottom) {
            filenameRulesPopover
        }
    }

    private func toolbarAction(
        title: String,
        systemImage: String,
        help: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .help(help)
    }

    private var toolbarDivider: some View {
        Divider()
            .frame(height: 22)
    }

    private var toolbarChrome: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
    }

    private var filenameRulesPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hide filenames containing")
                .font(.headline)
            Text("Comma-separated fragments. Applies when indexing sources (e.g. thumb, copy).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("thumb, copy", text: $excludedNames)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { showFilenameRules = false }
                Button("Apply") {
                    model.setNameFilter(excludedNames: excludedNames)
                    showFilenameRules = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var photoCountLabel: String {
        let count = model.visiblePaths.count
        if model.activity.isCataloging {
            return "\(count) photos · indexing…"
        }
        return "\(count) photos"
    }
}