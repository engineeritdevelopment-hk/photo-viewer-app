import SwiftUI

struct ProjectListView: View {
    var model: ProjectsViewModel
    @Binding var selectedProjectId: String?
    @State private var isEditingProjects = false
    @State private var editingProjectId: String?
    @State private var editingName = ""
    @State private var renameClickTargetId: String?
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        List(selection: $selectedProjectId) {
            Section {
                if model.isLoading {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Loading projects…")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(model.projects) { project in
                    projectRow(project)
                        .tag(project.id)
                }
            } header: {
                projectsSectionHeader
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let error = model.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Projects", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Try again") { model.load() }
                            .controlSize(.small)
                        Button("Dismiss") { model.clearError() }
                            .controlSize(.small)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
    }

    private var projectsSectionHeader: some View {
        HStack(spacing: 6) {
            Text("Projects")
            Spacer(minLength: 4)
            Button {
                isEditingProjects.toggle()
            } label: {
                Image(systemName: isEditingProjects ? "checkmark.circle" : "pencil")
            }
            .buttonStyle(.borderless)
            .help(isEditingProjects ? "Done editing projects" : "Edit projects")
            Button {
                addProject()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New project")
        }
        .textCase(nil)
    }

    @ViewBuilder
    private func projectRow(_ project: LibraryProject) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Group {
                if editingProjectId == project.id {
                    TextField("Project name", text: $editingName)
                        .textFieldStyle(.plain)
                        .focused($renameFieldFocused)
                        .onSubmit { commitRename(for: project.id) }
                        .onAppear {
                            editingName = project.name
                            renameFieldFocused = true
                        }
                        .onChange(of: renameFieldFocused) { _, focused in
                            if !focused, editingProjectId == project.id {
                                commitRename(for: project.id)
                            }
                        }
                } else {
                    Text(project.name)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .gesture(
                            TapGesture(count: 2).onEnded {
                                beginRename(project)
                            }
                        )
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                handleRenameClick(project)
                            }
                        )
                }
            }

            if isEditingProjects, editingProjectId != project.id {
                Button(role: .destructive) {
                    deleteProjects(ids: [project.id])
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete project")
            }
        }
        .contextMenu {
            Button("Rename") {
                beginRename(project)
            }
            if isEditingProjects {
                Button("Delete Project", role: .destructive) {
                    deleteProjects(ids: [project.id])
                }
            }
        }
    }

    private func addProject() {
        guard let project = model.create(name: "Untitled") else { return }
        selectedProjectId = project.id
        beginRename(project)
    }

    private func beginRename(_ project: LibraryProject) {
        renameClickTargetId = nil
        selectedProjectId = project.id
        editingName = project.name
        editingProjectId = project.id
    }

    private func handleRenameClick(_ project: LibraryProject) {
        let id = project.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard selectedProjectId == id else { return }
            if renameClickTargetId == id {
                beginRename(project)
                renameClickTargetId = nil
            } else {
                renameClickTargetId = id
            }
        }
    }

    private func commitRename(for projectId: String) {
        guard editingProjectId == projectId else { return }
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            model.rename(projectId: projectId, to: trimmed)
        }
        editingProjectId = nil
        editingName = ""
    }

    private func deleteProjects(ids: Set<String>) {
        if let editing = editingProjectId, ids.contains(editing) {
            editingProjectId = nil
        }
        let removedSelection = ids.contains(selectedProjectId ?? "")
        model.delete(projectIds: ids)
        guard removedSelection else { return }
        selectedProjectId = model.projects.first?.id
    }
}