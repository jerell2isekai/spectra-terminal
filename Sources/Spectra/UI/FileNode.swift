import AppKit

/// Represents a file or directory in the sidebar file tree.
/// Supports lazy-loading children and git status indicators.
class FileNode: NSObject {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?
    var gitStatus: GitStatus = .unmodified

    enum GitStatus {
        case unmodified
        case modified
        case added
        case deleted
        case untracked
        case conflicted

        var color: NSColor {
            switch self {
            case .unmodified: return .labelColor
            case .modified:   return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 0.95, green: 0.65, blue: 0.15, alpha: 1.0)
                    : NSColor(red: 0.75, green: 0.40, blue: 0.0, alpha: 1.0)
            }
            case .added:      return .systemGreen
            case .deleted:    return .systemRed
            case .untracked:  return .secondaryLabelColor
            case .conflicted: return .systemYellow
            }
        }

        var indicator: String {
            switch self {
            case .unmodified: return ""
            case .modified:   return "M"
            case .added:      return "A"
            case .deleted:    return "D"
            case .untracked:  return "?"
            case .conflicted: return "U"
            }
        }
    }

    init(url: URL) {
        self.url = url
        self.name = url.lastPathComponent
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue
        super.init()
    }

    /// Load direct children (directories first, then alphabetical).
    func loadChildren(showHiddenFiles: Bool = false) {
        guard isDirectory else { children = nil; return }
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
                options: options
            )
            children = contents
                .sorted { lhs, rhs in
                    let lhsDir = (try? lhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    let rhsDir = (try? rhs.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if lhsDir != rhsDir { return lhsDir }
                    return lhs.lastPathComponent.localizedStandardCompare(
                        rhs.lastPathComponent) == .orderedAscending
                }
                .map { FileNode(url: $0) }
        } catch {
            children = []
        }
    }

    var isLoaded: Bool { children != nil }
}
