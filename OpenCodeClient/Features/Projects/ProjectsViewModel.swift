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
    private(set) var chronologyReferenceDate: Date
    var searchText = ""
    var organization: SessionOrganization = .project

    @ObservationIgnored private var client: (any OpenCodeClientProtocol)?
    @ObservationIgnored private var profile: ServerProfile?
    @ObservationIgnored private var loadGeneration = UUID()
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: @Sendable () -> Date

    init(
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.calendar = calendar
        self.now = now
        chronologyReferenceDate = now()
    }

    var filteredSections: [ProjectSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sections }

        return sections.compactMap { section in
            let projectMatches =
                section.project.name.localizedStandardContains(query)
                || section.project.worktree.localizedStandardContains(query)
            if projectMatches {
                return section
            }
            let sessions = section.sessions.filter { $0.title.localizedStandardContains(query) }
            guard !sessions.isEmpty else { return nil }
            return ProjectSection(project: section.project, sessions: sessions)
        }
    }

    var chronologySections: [SessionChronologySection] {
        chronologySections(
            for: filteredSections.flatMap { section in
                section.sessions.map { SessionListItem(project: section.project, session: $0) }
            }
        )
    }

    var projectChronologySections: [ProjectChronologySection] {
        filteredSections.map { section in
            ProjectChronologySection(
                project: section.project,
                chronology: chronologySections(
                    for: section.sessions.map {
                        SessionListItem(project: section.project, session: $0)
                    }
                )
            )
        }
    }

    func prepareForConnection(to profile: ServerProfile) {
        loadGeneration = UUID()
        self.profile = profile
        client = nil
        sections = []
        statuses = [:]
        health = nil
        searchText = ""
        phase = .loading
    }

    func refreshChronologyReferenceDate() {
        chronologyReferenceDate = now()
    }

    func connect(profile: ServerProfile, client: any OpenCodeClientProtocol) async {
        let identityChanged = self.profile?.id != profile.id
        self.profile = profile
        self.client = client
        if identityChanged {
            sections = []
            statuses = [:]
            health = nil
            searchText = ""
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
        sections = []
        statuses = [:]
        health = nil
        phase = .failed(error.localizedDescription)
    }

    func route(for session: OpenCodeSession, in project: OpenCodeProject) -> ConversationRoute? {
        guard let profile else { return nil }
        return ConversationRoute(
            destination: .session(
                SessionRoute(profileID: profile.id, project: project, session: session)
            )
        )
    }

    func upsertSession(_ route: SessionRoute) {
        guard profile?.id == route.profileID else { return }
        if let sectionIndex = sections.firstIndex(where: { $0.project.id == route.project.id }) {
            if let sessionIndex = sections[sectionIndex].sessions.firstIndex(where: {
                $0.id == route.session.id
            }) {
                sections[sectionIndex].sessions[sessionIndex] = route.session
            } else {
                sections[sectionIndex].sessions.append(route.session)
            }
            sections[sectionIndex].sessions.sort(by: Self.sessionOrder)
        } else {
            sections.append(ProjectSection(project: route.project, sessions: [route.session]))
            sections.sort { lhs, rhs in
                lhs.project.name.localizedStandardCompare(rhs.project.name) == .orderedAscending
            }
        }
    }

    private func chronologySections(for items: [SessionListItem]) -> [SessionChronologySection] {
        var grouped: [SessionChronologyBucket: [SessionListItem]] = [:]
        for item in items.sorted(by: Self.sessionListOrder) {
            grouped[bucket(for: item.session.updatedAt), default: []].append(item)
        }
        return SessionChronologyBucket.allCases.compactMap { bucket in
            guard let items = grouped[bucket], !items.isEmpty else { return nil }
            return SessionChronologySection(bucket: bucket, items: items)
        }
    }

    private func bucket(for date: Date) -> SessionChronologyBucket {
        let startOfToday = calendar.startOfDay(for: chronologyReferenceDate)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfPreviousSevenDays =
            calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfYesterday

        if date >= startOfToday {
            return .today
        }
        if date >= startOfYesterday {
            return .yesterday
        }
        if date >= startOfPreviousSevenDays {
            return .previousSevenDays
        }
        return .earlier
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
                sections.append(
                    ProjectSection(project: project, sessions: sessions.sorted(by: Self.sessionOrder))
                )
                allStatuses.merge(statuses) { _, new in new }
            }
            sections.sort { lhs, rhs in
                let nameOrder = lhs.project.name.localizedStandardCompare(rhs.project.name)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return lhs.project.worktree.localizedStandardCompare(rhs.project.worktree)
                    == .orderedAscending
            }
            return (sections, allStatuses)
        }
    }

    private static func sessionOrder(_ lhs: OpenCodeSession, _ rhs: OpenCodeSession) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    private static func sessionListOrder(_ lhs: SessionListItem, _ rhs: SessionListItem) -> Bool {
        sessionOrder(lhs.session, rhs.session)
    }
}
