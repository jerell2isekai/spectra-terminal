import Foundation

private struct VSCodeThemeDocument: Codable {
    let name: String?
    let type: String?
    let include: String?
    let colors: [String: String?]?

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case include
        case colors
    }

    init(name: String?, type: String?, include: String?, colors: [String: String?]?) {
        self.name = name
        self.type = type
        self.include = include
        self.colors = colors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        include = try container.decodeIfPresent(String.self, forKey: .include)

        if container.contains(.colors) {
            let colorsContainer = try container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .colors)
            var decodedColors: [String: String?] = [:]
            for key in colorsContainer.allKeys {
                decodedColors[key.stringValue] = try colorsContainer.decodeIfPresent(String.self, forKey: key)
            }
            colors = decodedColors
        } else {
            colors = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(include, forKey: .include)

        guard let colors else { return }
        var colorsContainer = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .colors)
        for (key, value) in colors.sorted(by: { $0.key < $1.key }) {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            if let value {
                try colorsContainer.encode(value, forKey: codingKey)
            } else {
                try colorsContainer.encodeNil(forKey: codingKey)
            }
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private struct VSCodeExtensionManifest: Decodable {
    struct Contributes: Decodable {
        struct Theme: Decodable {
            let path: String
            let uiTheme: String?
        }

        let themes: [Theme]?
    }

    let contributes: Contributes?
}

enum VSCodeThemeParser {
    private static let maxIncludeDepth = 8
    private static let maxParsedFiles = 16

    static func parseTheme(at url: URL,
                           source: SpectraUIThemeSource,
                           fallbackTitle: String? = nil,
                           fallbackKind: SpectraUIThemeKind? = nil) throws -> (theme: SpectraUITheme, normalizedContent: String) {
        let root = allowedRoot(for: url)
        var visited: Set<URL> = []
        var parsedCount = 0
        let resolved = try parseDocument(at: url, allowedRoot: root, visited: &visited, depth: 0, parsedCount: &parsedCount)

        let title = resolved.name ?? fallbackTitle ?? url.deletingPathExtension().lastPathComponent
        let kind = inferredKind(from: resolved.type, themeURL: url, allowedRoot: root, fallbackKind: fallbackKind)
        let mapped = mappedRoleHexColors(from: compactedColors(resolved.colors), kind: kind)
        let theme = SpectraUITheme(
            id: slugify(title),
            title: title,
            source: source,
            kind: kind,
            roleHexColors: mapped,
            fileName: url.lastPathComponent
        )
        let normalizedDocument = VSCodeThemeDocument(
            name: title,
            type: kind.rawValue,
            include: nil,
            colors: resolved.colors
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(normalizedDocument)
        guard let normalizedContent = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "VSCodeThemeParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to normalize theme JSON"])
        }
        return (theme, normalizedContent)
    }

    private static func parseDocument(at url: URL,
                                      allowedRoot: URL,
                                      visited: inout Set<URL>,
                                      depth: Int,
                                      parsedCount: inout Int) throws -> VSCodeThemeDocument {
        guard depth <= maxIncludeDepth else {
            throw NSError(domain: "VSCodeThemeParser", code: 2, userInfo: [NSLocalizedDescriptionKey: "Theme include depth exceeded"])
        }
        let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
        guard isDescendant(canonicalURL, of: allowedRoot) else {
            throw NSError(domain: "VSCodeThemeParser", code: 3, userInfo: [NSLocalizedDescriptionKey: "Theme path escapes allowed root"])
        }
        if !visited.insert(canonicalURL).inserted {
            throw NSError(domain: "VSCodeThemeParser", code: 4, userInfo: [NSLocalizedDescriptionKey: "Theme include cycle detected"])
        }
        parsedCount += 1
        guard parsedCount <= maxParsedFiles else {
            throw NSError(domain: "VSCodeThemeParser", code: 5, userInfo: [NSLocalizedDescriptionKey: "Theme include file count exceeded"])
        }

        let raw = try String(contentsOf: canonicalURL, encoding: .utf8)
        let stripped = stripComments(from: raw)
        let data = Data(stripped.utf8)
        let decoder = JSONDecoder()
        let document = try decoder.decode(VSCodeThemeDocument.self, from: data)

        guard let include = document.include, !include.isEmpty else {
            return document
        }
        guard !include.hasPrefix("/") else {
            throw NSError(domain: "VSCodeThemeParser", code: 6, userInfo: [NSLocalizedDescriptionKey: "Absolute include paths are not allowed"])
        }
        let includeURL = canonicalURL.deletingLastPathComponent().appendingPathComponent(include).resolvingSymlinksInPath().standardizedFileURL
        guard isDescendant(includeURL, of: allowedRoot) else {
            throw NSError(domain: "VSCodeThemeParser", code: 7, userInfo: [NSLocalizedDescriptionKey: "Included theme escapes allowed root"])
        }
        let parent = try parseDocument(at: includeURL, allowedRoot: allowedRoot, visited: &visited, depth: depth + 1, parsedCount: &parsedCount)
        let mergedColors = (parent.colors ?? [:]).merging(document.colors ?? [:]) { _, new in new }
        return VSCodeThemeDocument(
            name: document.name ?? parent.name,
            type: document.type ?? parent.type,
            include: nil,
            colors: mergedColors
        )
    }

    private static func compactedColors(_ colors: [String: String?]?) -> [String: String] {
        (colors ?? [:]).reduce(into: [String: String]()) { result, entry in
            if let value = entry.value {
                result[entry.key] = value
            }
        }
    }

    private static func mappedRoleHexColors(from colors: [String: String], kind: SpectraUIThemeKind) -> [String: String] {
        let defaults = SpectraUITheme.defaultHexColors(for: kind)
        func pick(_ keys: [String], fallback: SpectraUIColorRole) -> String {
            for key in keys {
                if let value = colors[key], SpectraUITheme.parseHexColor(value) != nil {
                    return value
                }
            }
            return defaults[fallback.rawValue] ?? "#FF00FF"
        }
        return [
            SpectraUIColorRole.accent.rawValue: pick(["focusBorder", "activityBarBadge.background", "badge.background"], fallback: .accent),
            SpectraUIColorRole.separator.rawValue: pick(["sideBar.border", "pickerGroup.border", "input.border"], fallback: .separator),
            SpectraUIColorRole.sidebarBackground.rawValue: pick(["sideBar.background"], fallback: .sidebarBackground),
            SpectraUIColorRole.sidebarForeground.rawValue: pick(["sideBar.foreground", "foreground"], fallback: .sidebarForeground),
            SpectraUIColorRole.sidebarSecondaryForeground.rawValue: pick(["sideBarSectionHeader.foreground", "descriptionForeground"], fallback: .sidebarSecondaryForeground),
            SpectraUIColorRole.sidebarTertiaryForeground.rawValue: pick(["descriptionForeground"], fallback: .sidebarTertiaryForeground),
            SpectraUIColorRole.activityBarBackground.rawValue: pick(["activityBar.background"], fallback: .activityBarBackground),
            SpectraUIColorRole.activityBarForeground.rawValue: pick(["activityBar.foreground", "foreground"], fallback: .activityBarForeground),
            SpectraUIColorRole.activityBarInactiveForeground.rawValue: pick(["activityBar.inactiveForeground", "descriptionForeground"], fallback: .activityBarInactiveForeground),
            SpectraUIColorRole.activityBarBadgeBackground.rawValue: pick(["activityBarBadge.background", "badge.background"], fallback: .activityBarBadgeBackground),
            SpectraUIColorRole.activityBarBadgeForeground.rawValue: pick(["activityBarBadge.foreground", "badge.foreground"], fallback: .activityBarBadgeForeground),
            SpectraUIColorRole.tabBarBackground.rawValue: pick(["editorGroupHeader.tabsBackground", "sideBar.background"], fallback: .tabBarBackground),
            SpectraUIColorRole.tabActiveBackground.rawValue: pick(["tab.activeBackground"], fallback: .tabActiveBackground),
            SpectraUIColorRole.tabActiveForeground.rawValue: pick(["tab.activeForeground", "foreground"], fallback: .tabActiveForeground),
            SpectraUIColorRole.tabInactiveBackground.rawValue: pick(["tab.inactiveBackground", "editorGroupHeader.tabsBackground"], fallback: .tabInactiveBackground),
            SpectraUIColorRole.tabInactiveForeground.rawValue: pick(["tab.inactiveForeground", "descriptionForeground"], fallback: .tabInactiveForeground),
            SpectraUIColorRole.tabInactiveCloseForeground.rawValue: pick(["tab.inactiveForeground", "descriptionForeground"], fallback: .tabInactiveCloseForeground),
            SpectraUIColorRole.overlayBackground.rawValue: pick(["quickInput.background", "input.background", "sideBar.background"], fallback: .overlayBackground),
            SpectraUIColorRole.overlayForeground.rawValue: pick(["quickInput.foreground", "foreground"], fallback: .overlayForeground),
            SpectraUIColorRole.overlaySecondaryForeground.rawValue: pick(["descriptionForeground"], fallback: .overlaySecondaryForeground),
            SpectraUIColorRole.commandPaletteBackground.rawValue: pick(["quickInput.background"], fallback: .commandPaletteBackground),
            SpectraUIColorRole.commandPaletteForeground.rawValue: pick(["quickInput.foreground", "foreground"], fallback: .commandPaletteForeground),
            SpectraUIColorRole.commandPaletteSecondaryForeground.rawValue: pick(["descriptionForeground", "pickerGroup.foreground"], fallback: .commandPaletteSecondaryForeground),
            SpectraUIColorRole.commandPaletteSelectionBackground.rawValue: pick(["quickInputList.focusBackground", "list.focusBackground"], fallback: .commandPaletteSelectionBackground),
            SpectraUIColorRole.commandPaletteSelectionForeground.rawValue: pick(["quickInputList.focusForeground", "list.focusForeground", "foreground"], fallback: .commandPaletteSelectionForeground),
            SpectraUIColorRole.inputBackground.rawValue: pick(["input.background", "quickInput.background"], fallback: .inputBackground),
            SpectraUIColorRole.inputForeground.rawValue: pick(["input.foreground", "quickInput.foreground", "foreground"], fallback: .inputForeground),
            SpectraUIColorRole.inputBorder.rawValue: pick(["input.border", "pickerGroup.border"], fallback: .inputBorder),
            SpectraUIColorRole.buttonBackground.rawValue: pick(["button.background", "badge.background"], fallback: .buttonBackground),
            SpectraUIColorRole.buttonForeground.rawValue: pick(["button.foreground", "foreground"], fallback: .buttonForeground),
            SpectraUIColorRole.buttonHoverBackground.rawValue: pick(["button.hoverBackground", "button.background"], fallback: .buttonHoverBackground),
            SpectraUIColorRole.gitAdded.rawValue: pick(["gitDecoration.addedResourceForeground"], fallback: .gitAdded),
            SpectraUIColorRole.gitModified.rawValue: pick(["gitDecoration.modifiedResourceForeground"], fallback: .gitModified),
            SpectraUIColorRole.gitDeleted.rawValue: pick(["gitDecoration.deletedResourceForeground"], fallback: .gitDeleted),
            SpectraUIColorRole.gitUntracked.rawValue: pick(["gitDecoration.untrackedResourceForeground", "descriptionForeground"], fallback: .gitUntracked),
            SpectraUIColorRole.gitConflict.rawValue: pick(["gitDecoration.conflictingResourceForeground", "errorForeground"], fallback: .gitConflict),
        ]
    }

    private static func inferredKind(from raw: String?, themeURL: URL, allowedRoot: URL, fallbackKind: SpectraUIThemeKind?) -> SpectraUIThemeKind {
        if let raw {
            return normalizedKind(from: raw)
        }
        if let manifestKind = manifestThemeKind(themeURL: themeURL, allowedRoot: allowedRoot) {
            return manifestKind
        }
        return fallbackKind ?? .dark
    }

    private static func manifestThemeKind(themeURL: URL, allowedRoot: URL) -> SpectraUIThemeKind? {
        let manifestURL = allowedRoot.appendingPathComponent("package.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(VSCodeExtensionManifest.self, from: data)
            let relativePath = normalizedManifestPath(themeURL.path.replacingOccurrences(of: allowedRoot.path + "/", with: ""))
            let matchedTheme = manifest.contributes?.themes?.first {
                normalizedManifestPath($0.path) == relativePath
            }
            guard let uiTheme = matchedTheme?.uiTheme else { return nil }
            return normalizedKind(from: uiTheme)
        } catch {
            print("[VSCodeThemeParser] Failed to read manifest theme metadata at \(manifestURL.path): \(error)")
            return nil
        }
    }

    private static func normalizedManifestPath(_ raw: String) -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("./") {
            path.removeFirst(2)
        }
        return path
    }

    private static func normalizedKind(from raw: String) -> SpectraUIThemeKind {
        switch raw.lowercased() {
        case "light", "vs", "hc-light": return .light
        default: return .dark
        }
    }

    private static func allowedRoot(for url: URL) -> URL {
        var current = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let fm = FileManager.default
        while current.path != "/" {
            if fm.fileExists(atPath: current.appendingPathComponent("package.json").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent == current { break }
            current = parent
        }
        return url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isDescendant(_ url: URL, of root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path == root.path || url.path.hasPrefix(rootPath)
    }

    private static func slugify(_ string: String) -> String {
        let lowered = string.lowercased().replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: " ", with: "-")
        let mapped = lowered.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
        return String(mapped).replacingOccurrences(of: "--+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func stripComments(from input: String) -> String {
        var result = ""
        var iterator = input.makeIterator()
        var inString = false
        var escaped = false
        var previous: Character?
        while let char = iterator.next() {
            if inString {
                result.append(char)
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
                previous = char
                continue
            }
            if char == "\"" {
                inString = true
                result.append(char)
                previous = char
                continue
            }
            if previous == "/" && char == "/" {
                result.removeLast()
                while let next = iterator.next() {
                    if next == "\n" {
                        result.append("\n")
                        previous = next
                        break
                    }
                }
                continue
            }
            if previous == "/" && char == "*" {
                result.removeLast()
                var maybeEnd: Character?
                while let next = iterator.next() {
                    if maybeEnd == "*" && next == "/" { break }
                    maybeEnd = next
                }
                previous = nil
                continue
            }
            result.append(char)
            previous = char
        }
        return result
    }
}
