import Foundation

/// Persists and restores window/tab state across app restarts.
struct SessionState: Codable {
    var windows: [WindowState]

    struct WindowState: Codable {
        var frame: FrameState
        var tabs: [TabState]
        var activeTabIndex: Int
    }

    struct TabState: Codable {
        var title: String
        var workingDirectory: String?
    }

    struct FrameState: Codable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    // MARK: - File path

    static var stateFile: URL {
        SpectraConfig.configDir.appendingPathComponent("session.json")
    }

    // MARK: - Save / Load

    static func save(_ state: SessionState) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try FileManager.default.createDirectory(
                at: SpectraConfig.configDir, withIntermediateDirectories: true)
            try data.write(to: stateFile)
        } catch {
            print("[SessionState] Failed to save: \(error)")
        }
    }

    static func load() -> SessionState? {
        guard let data = try? Data(contentsOf: stateFile) else { return nil }
        return try? JSONDecoder().decode(SessionState.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: stateFile)
    }
}
