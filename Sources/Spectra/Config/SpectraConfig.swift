import AppKit
import Foundation

/// Spectra's config file in ghostty-compatible `key = value` format.
/// Stored at ~/.config/spectra/config. Can be directly loaded by ghostty_config_load_file().
/// Ghostty users can copy their config directly or use "Import from Ghostty".
enum SpectraConfig {

    // MARK: - Paths

    static var configDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/spectra", isDirectory: true)
    }

    static var configFile: URL {
        configDir.appendingPathComponent("config")
    }

    /// All known Ghostty config locations (macOS App Support, then XDG).
    static var ghosttyConfigCandidates: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            // macOS standard (Ghostty.app uses Application Support)
            home.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty/config"),
            // XDG (Linux, or if user set XDG_CONFIG_HOME)
            home.appendingPathComponent(".config/ghostty/config"),
        ]
    }

    static var ghosttyConfigFile: URL? {
        ghosttyConfigCandidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Default config content

    static let defaultConfig = """
    # Spectra Terminal Configuration
    # Uses Ghostty config format (key = value). See: https://ghostty.org/docs/config
    #
    # Font
    # font-family = JetBrains Mono
    font-size = 13

    # Appearance
    # theme = catppuccin-mocha
    background-opacity = 1
    # spectra-appearance = system  # system, light, or dark
    # split-divider-color = #A8C0B4
    # window-padding-x = 8
    # window-padding-y = 4

    # Cursor
    cursor-style = block
    cursor-style-blink = true
    cursor-opacity = 1

    # Shell integration
    shell-integration-features = no-cursor

    # Terminal
    scrollback-limit = 10000
    # command = /bin/zsh

    # Window size (in cell columns/rows, same as ghostty)
    # window-width = 120
    # window-height = 36
    """

    // MARK: - Ensure config exists

    static func ensureConfigExists() {
        let path = configFile.path
        guard !FileManager.default.fileExists(atPath: path) else { return }
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            try defaultConfig.write(to: configFile, atomically: true, encoding: .utf8)
        } catch {
            print("[SpectraConfig] Failed to create default config: \(error)")
        }
    }

    // MARK: - Read / Write raw config

    /// Parse config file into a key-value dictionary.
    static func readAll() -> [String: String] {
        guard let content = try? String(contentsOf: configFile, encoding: .utf8) else { return [:] }
        return parseKeyValue(content)
    }

    /// Read a single value from the config file.
    static func read(_ key: String) -> String? {
        readAll()[key]
    }

    /// Read a value with a default.
    static func read(_ key: String, default defaultValue: String) -> String {
        readAll()[key] ?? defaultValue
    }

    /// Window size from ghostty config. window-width/height are cell counts.
    /// Convert to pixel estimates using typical cell dimensions.
    static var windowWidth: Int {
        guard let v = read("window-width"), let cells = Int(v), cells > 0 else { return 800 }
        return min(cells * 8, 3840)  // cap at 4K width
    }
    static var windowHeight: Int {
        guard let v = read("window-height"), let rows = Int(v), rows > 0 else { return 600 }
        return min(rows * 18, 2160)  // cap at 4K height
    }
    static var backgroundOpacity: Double { Double(read("background-opacity") ?? "") ?? 1.0 }

    /// Appearance mode: "system" (follows macOS), "light", or "dark"
    static var appearanceMode: String { read("spectra-appearance", default: "system") }

    /// Divider color for split panes. Uses an opaque fallback so the divider
    /// remains visible even when the window background is translucent.
    static var splitDividerColor: NSColor {
        parseHexColor(read("split-divider-color")) ?? defaultSplitDividerColor
    }

    /// Write a set of key-value pairs to the config file.
    /// Preserves comments and unmodified keys.
    static func write(_ updates: [String: String]) {
        let content = (try? String(contentsOf: configFile, encoding: .utf8)) ?? defaultConfig
        var lines = content.components(separatedBy: .newlines)
        var updatedKeys = Set<String>()

        // Update existing lines
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
            if let newValue = updates[key] {
                lines[i] = "\(key) = \(newValue)"
                updatedKeys.insert(key)
            }
        }

        // Append new keys that weren't in the file
        for (key, value) in updates where !updatedKeys.contains(key) {
            lines.append("\(key) = \(value)")
        }

        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            try lines.joined(separator: "\n").write(to: configFile, atomically: true, encoding: .utf8)
        } catch {
            print("[SpectraConfig] Failed to write config: \(error)")
        }
    }

    // MARK: - Import from Ghostty

    /// Copy Ghostty's config file to Spectra's config location.
    /// Returns true if successful.
    @discardableResult
    static func importFromGhostty() -> Bool {
        guard let src = ghosttyConfigFile else { return false }
        return importFrom(url: src)
    }

    /// Check if any Ghostty config exists and can be imported.
    static var canImportFromGhostty: Bool {
        ghosttyConfigFile != nil
    }

    /// Import from any file URL. Replaces the entire config file.
    @discardableResult
    static func importFrom(url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let content = try String(contentsOf: url, encoding: .utf8)
            let header = "# Imported from: \(url.lastPathComponent)\n"
            let footer = "\n# Spectra-specific settings (added by import)\n"

            // Parse imported content to check which spectra keys are already present
            let existing = parseKeyValue(content)
            var extras: [String] = []
            if existing["scrollback-limit"] == nil {
                extras.append("scrollback-limit = 10000")
            }

            var result = header + content
            if !extras.isEmpty {
                result += footer + extras.joined(separator: "\n") + "\n"
            }

            try result.write(to: configFile, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("[SpectraConfig] Failed to import from \(url): \(error)")
            return false
        }
    }

    // MARK: - Parser

    private static var defaultSplitDividerColor: NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(srgbRed: 0.72, green: 0.78, blue: 0.75, alpha: 1.0)
            }
            return NSColor(srgbRed: 0.43, green: 0.49, blue: 0.46, alpha: 1.0)
        }
    }

    private static func parseHexColor(_ rawValue: String?) -> NSColor? {
        guard var hex = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return nil
        }

        if (hex.hasPrefix("\"") && hex.hasSuffix("\"")) ||
            (hex.hasPrefix("'") && hex.hasSuffix("'")) {
            hex.removeFirst()
            hex.removeLast()
        }

        if hex.hasPrefix("#") {
            hex.removeFirst()
        }

        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }

        guard hex.count == 6 || hex.count == 8,
              let value = UInt64(hex, radix: 16) else {
            return nil
        }

        let red: UInt64
        let green: UInt64
        let blue: UInt64
        let alpha: UInt64

        if hex.count == 8 {
            red = (value >> 24) & 0xFF
            green = (value >> 16) & 0xFF
            blue = (value >> 8) & 0xFF
            alpha = value & 0xFF
        } else {
            red = (value >> 16) & 0xFF
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
            alpha = 0xFF
        }

        return NSColor(
            srgbRed: CGFloat(red) / 255.0,
            green: CGFloat(green) / 255.0,
            blue: CGFloat(blue) / 255.0,
            alpha: CGFloat(alpha) / 255.0
        )
    }

    /// Parse ghostty `key = value` format into a dictionary.
    private static func parseKeyValue(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eqIdx = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[trimmed.startIndex..<eqIdx].trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
            // Strip inline comments, but preserve hex color values like #A8C0B4.
            if let hashIdx = value.firstIndex(of: "#"),
               hashIdx != value.startIndex,
               !value.hasPrefix("\""),
               value[value.index(before: hashIdx)].isWhitespace {
                value = value[value.startIndex..<hashIdx].trimmingCharacters(in: .whitespaces)
            }
            result[key] = value
        }
        return result
    }
}
