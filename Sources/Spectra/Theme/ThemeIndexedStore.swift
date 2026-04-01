import Foundation

struct InstalledUIThemeRecord: Codable, Hashable {
    let id: String
    let title: String
    let source: SpectraUIThemeSource
    let kind: SpectraUIThemeKind
    let fileName: String
    let installedAt: String
}

enum ThemeIndexedStore {
    private static var themesDir: URL {
        SpectraConfig.configDir.appendingPathComponent("themes/ui", isDirectory: true)
    }

    private static var indexFile: URL {
        themesDir.appendingPathComponent("index.json")
    }

    static func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
    }

    static func loadRecords() -> [InstalledUIThemeRecord] {
        do {
            try ensureDirectories()
            guard FileManager.default.fileExists(atPath: indexFile.path) else { return [] }
            let data = try Data(contentsOf: indexFile)
            let decoder = JSONDecoder()
            let records = try decoder.decode([InstalledUIThemeRecord].self, from: data)
            return repair(records)
        } catch {
            print("[ThemeIndexedStore] Failed to load index: \(error)")
            return []
        }
    }

    static func themeFileURL(for record: InstalledUIThemeRecord) -> URL {
        themesDir.appendingPathComponent(record.fileName)
    }

    @discardableResult
    static func installUserTheme(theme: SpectraUITheme, normalizedContent: String, installedAt: String) throws -> InstalledUIThemeRecord {
        try ensureDirectories()
        let themeID = "user-\(theme.id)"
        let fileName = "\(themeID).json"
        let targetURL = themesDir.appendingPathComponent(fileName)
        try writeAtomically(normalizedContent, to: targetURL)

        // Remove existing record with same ID or same title (migrates legacy hash-based IDs)
        let allRecords = loadRecords()
        let staleRecords = allRecords.filter { $0.source == .user && ($0.id == themeID || $0.title == theme.title) }
        for stale in staleRecords where stale.fileName != fileName {
            let staleURL = themesDir.appendingPathComponent(stale.fileName)
            try? FileManager.default.removeItem(at: staleURL)
        }
        var records = allRecords.filter { !($0.source == .user && ($0.id == themeID || $0.title == theme.title)) }
        let record = InstalledUIThemeRecord(
            id: themeID,
            title: theme.title,
            source: .user,
            kind: theme.kind,
            fileName: fileName,
            installedAt: installedAt
        )
        records.append(record)
        try saveRecords(records)
        return record
    }

    static func saveRecords(_ records: [InstalledUIThemeRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ThemeIndexedStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode index as UTF-8"])
        }
        try writeAtomically(content, to: indexFile)
    }

    private static func repair(_ records: [InstalledUIThemeRecord]) -> [InstalledUIThemeRecord] {
        let repaired = records.filter { FileManager.default.fileExists(atPath: themeFileURL(for: $0).path) }
        if repaired.count != records.count {
            try? saveRecords(repaired)
        }
        return repaired
    }

    private static func writeAtomically(_ content: String, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        try content.write(to: tmp, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }

}
