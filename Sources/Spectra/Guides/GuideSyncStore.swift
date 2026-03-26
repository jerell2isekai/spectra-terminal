import Foundation

final class GuideSyncStore {
    static let shared = GuideSyncStore()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func loadTargets() -> [GuideSyncTarget] {
        let url = SpectraConfig.guideSyncTargetsFile
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let targets = try? decoder.decode([GuideSyncTarget].self, from: data) else { return [] }
        return deduped(targets)
    }

    func saveTargets(_ targets: [GuideSyncTarget]) throws {
        let normalized = deduped(targets)
        try FileManager.default.createDirectory(at: SpectraConfig.configDir, withIntermediateDirectories: true)
        let data = try encoder.encode(normalized)
        try data.write(to: SpectraConfig.guideSyncTargetsFile, options: .atomic)
    }

    private func deduped(_ targets: [GuideSyncTarget]) -> [GuideSyncTarget] {
        var seen = Set<String>()
        var result: [GuideSyncTarget] = []

        for target in targets {
            let normalizedPath = GuideSyncTarget.normalizedPath(target.path)
            guard !seen.contains(normalizedPath) else { continue }
            seen.insert(normalizedPath)
            result.append(GuideSyncTarget(
                id: target.id,
                path: normalizedPath,
                alias: target.alias,
                isEnabled: target.isEnabled
            ))
        }

        return result.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
