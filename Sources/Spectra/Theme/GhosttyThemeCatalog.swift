import Foundation

enum GhosttyThemeCatalog {
    static func bundledThemeNames() -> [String] {
        guard let baseURL = Bundle.spectraResources.resourceURL?.appendingPathComponent("ghostty/themes", isDirectory: true) else {
            return []
        }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return items
            .filter { ((try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false) }
            .map(\.lastPathComponent)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
