import Foundation
import Observation

@MainActor
@Observable
final class ChangesViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var changes: [OpenCodeFileDiff] = []

    let sessionID: String
    let directory: String

    @ObservationIgnored private let client: any OpenCodeClientProtocol
    @ObservationIgnored private var generation = UUID()

    init(sessionID: String, directory: String, client: any OpenCodeClientProtocol) {
        self.sessionID = sessionID
        self.directory = directory
        self.client = client
    }

    func loadIfNeeded() async {
        guard phase == .idle else { return }
        await load()
    }

    func load() async {
        let requestedGeneration = UUID()
        generation = requestedGeneration
        phase = .loading

        do {
            let changes = try await client.sessionDiff(sessionID: sessionID, directory: directory)
            guard generation == requestedGeneration, !Task.isCancelled else { return }
            self.changes = changes.sorted(by: Self.changeOrder)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch let error as NetworkError where error == .cancelled {
            return
        } catch {
            guard generation == requestedGeneration else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private static func changeOrder(_ lhs: OpenCodeFileDiff, _ rhs: OpenCodeFileDiff) -> Bool {
        lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
    }
}
