import Foundation

/// Persists and restores named split layouts as JSON files in ~/.config/spectra/layouts/.
enum SplitLayoutStore {
    /// A serializable split layout tree — includes ratio for each split.
    struct Layout: Codable {
        enum Node: Codable {
            case terminal
            case split(direction: String, ratio: Double, children: [Node])
        }
        var root: Node
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
