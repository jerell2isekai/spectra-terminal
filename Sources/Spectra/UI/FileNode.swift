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
            let theme = SpectraThemeManager.shared
            switch self {
            case .unmodified: return theme.color(.sidebarForeground)
            case .modified:   return theme.color(.gitModified)
            case .added:      return theme.color(.gitAdded)
            case .deleted:    return theme.color(.gitDeleted)
            case .untracked:  return theme.color(.gitUntracked)
            case .conflicted: return theme.color(.gitConflict)
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
