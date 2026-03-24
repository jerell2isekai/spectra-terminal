import Foundation

/// Persists and restores named split layouts as JSON files in ~/.config/spectra/layouts/.
enum SplitLayoutStore {
    /// A serializable split layout tree — includes ratio for each split.
    struct Layout: Codable {
        enum Node {
            case terminal(workingDirectory: String? = nil)
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

// MARK: - Custom Codable (backward compatible with old layouts without workingDirectory)

extension SplitLayoutStore.Layout.Node: Codable {
    private enum TopKeys: String, CodingKey {
        case terminal, split
    }
    private enum TerminalKeys: String, CodingKey {
        case workingDirectory
    }
    private enum SplitKeys: String, CodingKey {
        case direction, ratio, children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TopKeys.self)
        if container.contains(.terminal) {
            if let nested = try? container.nestedContainer(keyedBy: TerminalKeys.self, forKey: .terminal),
               let wd = try? nested.decodeIfPresent(String.self, forKey: .workingDirectory) {
                self = .terminal(workingDirectory: wd)
            } else {
                self = .terminal()
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
        case .terminal(let wd):
            var nested = container.nestedContainer(keyedBy: TerminalKeys.self, forKey: .terminal)
            try nested.encodeIfPresent(wd, forKey: .workingDirectory)
        case .split(let direction, let ratio, let children):
            var nested = container.nestedContainer(keyedBy: SplitKeys.self, forKey: .split)
            try nested.encode(direction, forKey: .direction)
            try nested.encode(ratio, forKey: .ratio)
            try nested.encode(children, forKey: .children)
        }
    }
}
