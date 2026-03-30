import Foundation

final class GuideSyncService {
    static let shared = GuideSyncService()

    private init() {}

    var templateKinds: [GuideTemplateKind] {
        GuideTemplateKind.allCases
    }

    func loadGuideTemplate(_ kind: GuideTemplateKind) throws -> String {
        try ensureGuideTemplatesExist()
        let url = SpectraConfig.guideTemplateFile(kind)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func templateFileURL(for kind: GuideTemplateKind) -> URL {
        SpectraConfig.guideTemplateFile(kind)
    }

    func saveGuideTemplate(_ kind: GuideTemplateKind, content: String) throws {
        try ensureGuideTemplatesExist()
        try content.write(to: SpectraConfig.guideTemplateFile(kind), atomically: true, encoding: .utf8)
    }

    func ensureGuideTemplatesExist() throws {
        try FileManager.default.createDirectory(at: SpectraConfig.guideTemplatesDir, withIntermediateDirectories: true)

        for kind in GuideTemplateKind.allCases {
            let destination = SpectraConfig.guideTemplateFile(kind)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }

            let content = try loadDefaultTemplate(kind)
            try content.write(to: destination, atomically: true, encoding: .utf8)
        }
    }

    func syncGuides(to target: GuideSyncTarget,
                    guides: [GuideTemplateKind] = GuideTemplateKind.allCases) -> GuideTargetSyncResult {
        let targetURL = URL(fileURLWithPath: target.path, isDirectory: true)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDirectory)

        guard exists, isDirectory.boolValue else {
            let error = "Target directory does not exist"
            return GuideTargetSyncResult(
                target: target,
                fileResults: guides.map { GuideFileSyncResult(fileName: $0.fileName, status: .failed(error)) }
            )
        }

        let fileResults = guides.map { guide in
            syncSingleGuide(guide, to: targetURL)
        }

        return GuideTargetSyncResult(target: target, fileResults: fileResults)
    }

    func syncGuides(toTargets targets: [GuideSyncTarget],
                    guides: [GuideTemplateKind] = GuideTemplateKind.allCases) -> [GuideTargetSyncResult] {
        targets.filter(\.isEnabled).map { syncGuides(to: $0, guides: guides) }
    }

    func summaryText(for results: [GuideTargetSyncResult]) -> String {
        guard !results.isEmpty else { return "No targets were synced." }

        var lines: [String] = []
        let totalTargets = results.count
        let successfulTargets = results.filter(\.isSuccess).count
        lines.append("Synced \(successfulTargets)/\(totalTargets) targets")

        for result in results {
            let icon = result.isSuccess ? "✓" : "⚠"
            lines.append("\n\(icon) \(result.target.displayName)")
            for file in result.fileResults {
                switch file.status {
                case .written:
                    lines.append("  • \(file.fileName): written")
                case .unchanged:
                    lines.append("  • \(file.fileName): unchanged")
                case .failed(let error):
                    lines.append("  • \(file.fileName): failed — \(error)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private func syncSingleGuide(_ guide: GuideTemplateKind, to targetURL: URL) -> GuideFileSyncResult {
        do {
            let content = try loadGuideTemplate(guide)
            let destination = targetURL.appendingPathComponent(guide.fileName)

            if let existing = try? String(contentsOf: destination, encoding: .utf8), existing == content {
                return GuideFileSyncResult(fileName: guide.fileName, status: .unchanged)
            }

            try content.write(to: destination, atomically: true, encoding: .utf8)
            return GuideFileSyncResult(fileName: guide.fileName, status: .written)
        } catch {
            return GuideFileSyncResult(fileName: guide.fileName, status: .failed(error.localizedDescription))
        }
    }

    private func loadDefaultTemplate(_ kind: GuideTemplateKind) throws -> String {
        guard let url = Bundle.spectraResources.url(forResource: kind.resourceName,
                                          withExtension: kind.resourceExtension,
                                          subdirectory: "Guides") else {
            throw NSError(domain: "GuideSyncService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Default template not found: \(kind.fileName)"
            ])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
