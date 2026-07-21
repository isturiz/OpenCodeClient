import Foundation
import Observation

@MainActor
@Observable
final class ProjectsViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var health: OpenCodeHealth?
    private(set) var sections: [ProjectSection] = []
    private(set) var statuses: [String: OpenCodeSessionStatus] = [:]
    private(set) var isCreatingSession = false
    var searchText = ""

    @ObservationIgnored private var client: (any OpenCodeClientProtocol)?
    @ObservationIgnored private var profile: ServerProfile?
    @ObservationIgnored private var loadGeneration = UUID()

    var filteredSections: [ProjectSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sections }

        return sections.compactMap { section in
            let projectMatches =
                section.project.name.localizedStandardContains(query)
                || section.project.worktree.localizedStandardContains(query)
            let sessions =
                projectMatches
                ? section.sessions
                : section.sessions.filter { $0.title.localizedStandardContains(query) }
            guard !sessions.isEmpty else { return nil }
            return ProjectSection(project: section.project, sessions: sessions)
        }
    }

    func connect(profile: ServerProfile, client: any OpenCodeClientProtocol) async {
        let identityChanged = self.profile?.id != profile.id
        self.profile = profile
        self.client = client
        if identityChanged {
            sections = []
            statuses = [:]
            health = nil
        }
        await refresh()
    }

    func refresh() async {
        guard let client else { return }
        let generation = UUID()
        loadGeneration = generation
        phase = .loading

        do {
            async let healthRequest = client.health()
            async let projectsRequest = client.projects()
            let (health, projects) = try await (healthRequest, projectsRequest)
            let loadedSections = try await loadSections(projects: projects, client: client)

            guard loadGeneration == generation else { return }
            self.health = health
            sections = loadedSections.sections
            statuses = loadedSections.statuses
            phase = .loaded
        } catch {
            guard loadGeneration == generation else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    func fail(_ error: Error) {
        phase = .failed(error.localizedDescription)
    }

    func createSession(in project: OpenCodeProject) async throws -> SessionRoute {
        guard let client, let profile else { throw NetworkError.invalidResponse }
        isCreatingSession = true
        defer { isCreatingSession = false }
        let session = try await client.createSession(directory: project.worktree, title: nil)
        await refresh()
        return SessionRoute(profileID: profile.id, project: project, session: session)
    }

    func route(for session: OpenCodeSession, in project: OpenCodeProject) -> SessionRoute? {
        guard let profile else { return nil }
        return SessionRoute(profileID: profile.id, project: project, session: session)
    }

    private func loadSections(
        projects: [OpenCodeProject],
        client: any OpenCodeClientProtocol
    ) async throws -> (sections: [ProjectSection], statuses: [String: OpenCodeSessionStatus]) {
        try await withThrowingTaskGroup(
            of: (OpenCodeProject, [OpenCodeSession], [String: OpenCodeSessionStatus]).self
        ) { group in
            for project in projects {
                group.addTask {
                    async let sessions = client.sessions(directory: project.worktree)
                    async let statuses = client.sessionStatuses(directory: project.worktree)
                    return try await (project, sessions, statuses)
                }
            }

            var sections: [ProjectSection] = []
            var allStatuses: [String: OpenCodeSessionStatus] = [:]
            for try await (project, sessions, statuses) in group {
                sections.append(ProjectSection(project: project, sessions: sessions))
                allStatuses.merge(statuses) { _, new in new }
            }
            sections.sort { $0.project.name.localizedStandardCompare($1.project.name) == .orderedAscending }
            return (sections, allStatuses)
        }
    }
}
