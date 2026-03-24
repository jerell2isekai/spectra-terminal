import Foundation

/// Per-tab metadata for layout serialization.
struct TabInfo: Codable {
    var workingDirectory: String?
}

/// Persists and restores named split layouts as JSON files in ~/.config/spectra/layouts/.
enum SplitLayoutStore {
    /// A serializable split layout tree with per-pane tab support.
    struct Layout: Codable {
        enum Node {
            case terminal(tabs: [TabInfo], activeTabIndex: Int = 0)
            case split(direction: String, ratio: Double, children: [Node])
        }
        var root: Node
        /// Sidebar file/git manager root directory (optional).
        var sidebarDirectory: String?
        /// Whether the sidebar was open when saved.
        var sidebarOpen: Bool?
    }

    static var layoutsDir: URL {
        SpectraConfig.configDir.appendingPathComponent("layouts", isDirectory: true)
    }

    static func save(layout: Layout, name: String) {
        do {
            try FileManager.default.createDirectory(at: layoutsDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(layout)
            let url = layoutsDir.appendingPathComponent("\(name).json")
            try data.write(to: url)
        } catch {
            print("[SplitLayoutStore] Failed to save layout '\(name)': \(error)")
        }
    }

    static func load(name: String) -> Layout? {
        let url = layoutsDir.appendingPathComponent("\(name).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Layout.self, from: data)
    }

    static func list() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: layoutsDir, includingPropertiesForKeys: nil
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    static func delete(name: String) {
        let url = layoutsDir.appendingPathComponent("\(name).json")
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Custom Codable (backward compatible with old single-terminal layouts)

extension SplitLayoutStore.Layout.Node: Codable {
    private enum TopKeys: String, CodingKey {
        case terminal, split
    }
    // Old format keys
    private enum OldTerminalKeys: String, CodingKey {
        case workingDirectory
    }
    // New format keys
    private enum NewTerminalKeys: String, CodingKey {
        case tabs, activeTabIndex
    }
    private enum SplitKeys: String, CodingKey {
        case direction, ratio, children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TopKeys.self)
        if container.contains(.terminal) {
            // Try new format first (tabs array)
            if let nested = try? container.nestedContainer(keyedBy: NewTerminalKeys.self, forKey: .terminal),
               let tabs = try? nested.decode([TabInfo].self, forKey: .tabs) {
                let activeIndex = (try? nested.decode(Int.self, forKey: .activeTabIndex)) ?? 0
                self = .terminal(tabs: tabs, activeTabIndex: activeIndex)
            }
            // Fall back to old format (single workingDirectory)
            else if let nested = try? container.nestedContainer(keyedBy: OldTerminalKeys.self, forKey: .terminal) {
                let wd = try? nested.decodeIfPresent(String.self, forKey: .workingDirectory)
                self = .terminal(tabs: [TabInfo(workingDirectory: wd)], activeTabIndex: 0)
            }
            // Empty terminal
            else {
                self = .terminal(tabs: [TabInfo()], activeTabIndex: 0)
            }
        } else if container.contains(.split) {
            let nested = try container.nestedContainer(keyedBy: SplitKeys.self, forKey: .split)
            let direction = try nested.decode(String.self, forKey: .direction)
            let ratio = try nested.decode(Double.self, forKey: .ratio)
            let children = try nested.decode([SplitLayoutStore.Layout.Node].self, forKey: .children)
            self = .split(direction: direction, ratio: ratio, children: children)
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown node type"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: TopKeys.self)
        switch self {
        case .terminal(let tabs, let activeTabIndex):
            var nested = container.nestedContainer(keyedBy: NewTerminalKeys.self, forKey: .terminal)
            try nested.encode(tabs, forKey: .tabs)
            try nested.encode(activeTabIndex, forKey: .activeTabIndex)
        case .split(let direction, let ratio, let children):
            var nested = container.nestedContainer(keyedBy: SplitKeys.self, forKey: .split)
            try nested.encode(direction, forKey: .direction)
            try nested.encode(ratio, forKey: .ratio)
            try nested.encode(children, forKey: .children)
        }
    }
}
