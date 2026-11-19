import Foundation
import Observation

@MainActor
@Observable
final class ProjectsViewModel {
    var projects: [LibraryProject] = []
    var isLoading = false
    var errorMessage: String?

    func load() {
        isLoading = true
        errorMessage = nil
        do {
            projects = try ProjectStore.load()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func clearError() {
        errorMessage = nil
    }

    func create(name: String) -> LibraryProject? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let project = LibraryProject(
            id: UUID().uuidString,
            name: trimmed
        )
        projects.append(project)
        persist()
        return project
    }

    func delete(at offsets: IndexSet) {
        let ids = Set(offsets.map { projects[$0].id })
        delete(projectIds: ids)
    }

    func delete(projectIds: Set<String>) {
        guard !projectIds.isEmpty else { return }
        projects.removeAll { projectIds.contains($0.id) }
        for id in projectIds {
            removeProjectData(projectId: id)
        }
        if let last = AppPreferences.lastOpenedProjectId, projectIds.contains(last) {
            AppPreferences.lastOpenedProjectId = nil
        }
        persist()
    }

    private func removeProjectData(projectId: String) {
        let indexURL = ApplicationPaths.indexDatabase(projectId: projectId)
        try? FileManager.default.removeItem(at: indexURL)
    }

    func persist() {
        do {
            try ProjectStore.save(projects)
            if errorMessage?.contains("projects.json") == true {
                errorMessage = nil
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func update(_ project: LibraryProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        persist()
    }

    func rename(projectId: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[index].name = trimmed
        persist()
    }
}