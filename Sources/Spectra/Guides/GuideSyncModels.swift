import Foundation

enum GuideTemplateKind: String, CaseIterable {
    case agents = "AGENTS.md"
    case claude = "CLAUDE.md"

    var fileName: String { rawValue }

    var resourceName: String {
        (rawValue as NSString).deletingPathExtension
    }

    var resourceExtension: String {
        (rawValue as NSString).pathExtension
    }
}

struct GuideSyncTarget: Codable, Equatable {
    var id: UUID
    var path: String
    var alias: String?
    var isEnabled: Bool

    init(id: UUID = UUID(), path: String, alias: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.path = GuideSyncTarget.normalizedPath(path)
        self.alias = alias
        self.isEnabled = isEnabled
    }

    var displayName: String {
        if let alias, !alias.isEmpty { return alias }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

enum GuideFileSyncStatus: Equatable {
    case written
    case unchanged
    case failed(String)
}

struct GuideFileSyncResult {
    let fileName: String
    let status: GuideFileSyncStatus
}

struct GuideTargetSyncResult {
    let target: GuideSyncTarget
    let fileResults: [GuideFileSyncResult]

    var isSuccess: Bool {
        !fileResults.contains { if case .failed = $0.status { return true } else { return false } }
    }
}
