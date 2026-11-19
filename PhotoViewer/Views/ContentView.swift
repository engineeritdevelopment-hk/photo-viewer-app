import SwiftUI

struct ContentView: View {
    @State private var projects = ProjectsViewModel()
    @State private var selectedProjectId: String?
    @State private var libraryModels: [String: LibraryViewModel] = [:]

    var body: some View {
        NavigationSplitView {
            ProjectListView(
                model: projects,
                selectedProjectId: $selectedProjectId
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            Group {
                if let id = selectedProjectId,
                   let project = projects.projects.first(where: { $0.id == id }) {
                    LibraryView(
                        model: libraryModel(for: project),
                        onBackToProjects: { selectedProjectId = nil }
                    )
                    .id(id)
                } else {
                    ProjectOnboardingView {
                        selectedProjectId = projects.create(name: "My Photos")?.id
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1080, minHeight: 640)
        .onAppear {
            projects.load()
            openLastProjectIfNeeded()
        }
        .onChange(of: selectedProjectId) { oldValue, newValue in
            AppPreferences.lastOpenedProjectId = newValue
            if let oldValue, oldValue != newValue {
                libraryModels[oldValue]?.close()
            }
        }
    }

    private func libraryModel(for project: LibraryProject) -> LibraryViewModel {
        if let cached = libraryModels[project.id] {
            cached.project = project
            return cached
        }
        let model = LibraryViewModel(project: project, projects: projects)
        libraryModels[project.id] = model
        return model
    }

    private func openLastProjectIfNeeded() {
        guard selectedProjectId == nil else { return }
        guard let last = AppPreferences.lastOpenedProjectId else { return }
        guard projects.projects.contains(where: { $0.id == last }) else {
            AppPreferences.lastOpenedProjectId = nil
            return
        }
        selectedProjectId = last
    }
}

private struct ProjectOnboardingView: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
            Text("Photo Viewer")
                .font(.largeTitle.bold())
            Text("Create a project, add source folders, and browse locally. Nothing leaves your Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Create Project", action: onCreate)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}