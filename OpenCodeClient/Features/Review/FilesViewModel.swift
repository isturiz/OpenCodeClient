import Foundation
import Observation

@MainActor
@Observable
final class FilesViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var nodes: [OpenCodeFileNode] = []

    let directory: String
    let path: String

    @ObservationIgnored private let client: any OpenCodeClientProtocol
    @ObservationIgnored private var generation = UUID()

    init(directory: String, path: String = "", client: any OpenCodeClientProtocol) {
        self.directory = directory
        self.path = path
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
            let nodes = try await client.files(directory: directory, path: path)
            guard generation == requestedGeneration, !Task.isCancelled else { return }
            self.nodes = nodes.sorted(by: Self.nodeOrder)
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

    private static func nodeOrder(_ lhs: OpenCodeFileNode, _ rhs: OpenCodeFileNode) -> Bool {
        let lhsRank = lhs.type.sortRank
        let rhsRank = rhs.type.sortRank
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

@MainActor
@Observable
final class FileContentViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var fileContent: OpenCodeFileContent?

    let directory: String
    let path: String

    @ObservationIgnored private let client: any OpenCodeClientProtocol
    @ObservationIgnored private var generation = UUID()

    init(directory: String, path: String, client: any OpenCodeClientProtocol) {
        self.directory = directory
        self.path = path
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
            let content = try await client.fileContent(directory: directory, path: path)
            guard generation == requestedGeneration, !Task.isCancelled else { return }
            fileContent = content
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
}

private extension OpenCodeFileNodeType {
    var sortRank: Int {
        switch self {
        case .directory: 0
        case .file: 1
        case .unknown: 2
        }
    }
}
