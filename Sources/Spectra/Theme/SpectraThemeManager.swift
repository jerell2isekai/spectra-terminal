import AppKit
import Foundation

extension Notification.Name {
    static let spectraThemeDidChange = Notification.Name("SpectraThemeDidChange")
}

final class SpectraThemeManager {
    static let shared = SpectraThemeManager()

    private(set) var currentTheme: SpectraUITheme
    private(set) var previewTheme: SpectraUITheme?

    private var bundledThemes: [SpectraUITheme] = []
    private var installedThemes: [SpectraUITheme] = []

    private init() {
        let fallback = SpectraUITheme(
            id: "spectra-default-dark",
            title: "Spectra Default Dark",
            source: .bundled,
            kind: .dark,
            roleHexColors: SpectraUITheme.defaultHexColors(for: .dark),
            fileName: nil
        )
        self.currentTheme = fallback
        reloadCatalogs()
        reloadFromConfig()
    }

    var effectiveTheme: SpectraUITheme { previewTheme ?? currentTheme }

    func color(_ role: SpectraUIColorRole) -> NSColor {
        effectiveTheme.color(role)
    }

    func allUIThemes() -> [SpectraUITheme] {
        (bundledThemes + installedThemes).sorted { lhs, rhs in
            if lhs.source != rhs.source {
                return lhs.source.rawValue < rhs.source.rawValue
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func reloadCatalogs() {
        bundledThemes = loadBundledThemes()
        installedThemes = loadInstalledThemes()
    }

    func reloadFromConfig() {
        reloadCatalogs()
        let fallback = fallbackTheme(for: fallbackKindFromAppearanceMode())
        if !SpectraConfig.hasExplicitUIThemeSelection {
            currentTheme = fallback
        } else {
            let selectedID = SpectraConfig.uiThemeID
            let selectedSource = SpectraConfig.uiThemeSource
            if let resolved = resolveTheme(id: selectedID, source: selectedSource) {
                currentTheme = resolved
            } else {
                print("[SpectraThemeManager] Configured UI theme not found: \(selectedSource.rawValue)::\(selectedID). Falling back to \(fallback.id)")
                currentTheme = fallback
            }
        }
        NotificationCenter.default.post(name: .spectraThemeDidChange, object: self)
    }

    func preview(themeID: String, source: SpectraUIThemeSource) {
        previewTheme = resolveTheme(id: themeID, source: source)
        NotificationCenter.default.post(name: .spectraThemeDidChange, object: self)
    }

    func clearPreview() {
        guard previewTheme != nil else { return }
        previewTheme = nil
        NotificationCenter.default.post(name: .spectraThemeDidChange, object: self)
    }

    @discardableResult
    func importTheme(from url: URL, installedAt: String) throws -> SpectraUITheme {
        let parsed = try VSCodeThemeParser.parseTheme(at: url, source: .user)
        let record = try ThemeIndexedStore.installUserTheme(theme: parsed.theme, normalizedContent: parsed.normalizedContent, installedAt: installedAt)
        reloadCatalogs()
        if let installed = resolveTheme(id: record.id, source: .user) {
            return installed
        }
        return SpectraUITheme(
            id: record.id,
            title: parsed.theme.title,
            source: .user,
            kind: parsed.theme.kind,
            roleHexColors: parsed.theme.roleHexColors,
            fileName: record.fileName
        )
    }

    func configuredAppearanceMode() -> String {
        Self.normalizedAppearanceMode(SpectraConfig.uiAppearanceMode, themeKind: SpectraConfig.hasExplicitUIThemeSelection ? currentTheme.kind : nil)
    }

    func resolveAppKitAppearance() -> NSAppearance? {
        if let previewTheme {
            return previewTheme.kind == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        }
        switch configuredAppearanceMode() {
        case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua)
        default:
            guard SpectraConfig.hasExplicitUIThemeSelection else { return nil }
            return currentTheme.kind == .dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        }
    }

    static func normalizedAppearanceMode(_ requestedMode: String, themeKind: SpectraUIThemeKind?) -> String {
        guard let themeKind else { return requestedMode }
        guard requestedMode != "auto" else { return requestedMode }
        let themeAppearance = themeKind == .dark ? "dark" : "light"
        return requestedMode == themeAppearance ? requestedMode : "auto"
    }

    private func resolveTheme(id: String, source: SpectraUIThemeSource) -> SpectraUITheme? {
        allUIThemes().first { $0.id == id && $0.source == source }
    }

    private func fallbackTheme(for kind: SpectraUIThemeKind) -> SpectraUITheme {
        if kind == .light {
            return bundledThemes.first(where: { $0.id == "spectra-default-light" })
                ?? SpectraUITheme(id: "spectra-default-light", title: "Spectra Default Light", source: .bundled, kind: .light, roleHexColors: SpectraUITheme.defaultHexColors(for: .light), fileName: nil)
        }
        return bundledThemes.first(where: { $0.id == "spectra-default-dark" })
            ?? SpectraUITheme(id: "spectra-default-dark", title: "Spectra Default Dark", source: .bundled, kind: .dark, roleHexColors: SpectraUITheme.defaultHexColors(for: .dark), fileName: nil)
    }

    private func fallbackKindFromAppearanceMode() -> SpectraUIThemeKind {
        switch SpectraConfig.uiAppearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return currentSystemKind()
        }
    }

    private func currentSystemKind() -> SpectraUIThemeKind {
        let appearance = NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
    }

    private func loadBundledThemes() -> [SpectraUITheme] {
        guard let directory = Bundle.spectraResources.resourceURL?.appendingPathComponent("UIThemes", isDirectory: true) else {
            return []
        }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            return files
                .filter { $0.pathExtension.lowercased() == "json" }
                .compactMap { url in
                    do {
                        return try VSCodeThemeParser.parseTheme(at: url, source: .bundled).theme
                    } catch {
                        print("[SpectraThemeManager] Failed to load bundled UI theme at \(url.path): \(error)")
                        return nil
                    }
                }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        } catch {
            print("[SpectraThemeManager] Failed to enumerate bundled UI themes at \(directory.path): \(error)")
            return []
        }
    }

    private func loadInstalledThemes() -> [SpectraUITheme] {
        ThemeIndexedStore.loadRecords().compactMap { record in
            let url = ThemeIndexedStore.themeFileURL(for: record)
            do {
                let parsed = try VSCodeThemeParser.parseTheme(
                    at: url,
                    source: record.source,
                    fallbackTitle: record.title,
                    fallbackKind: record.kind
                ).theme
                return SpectraUITheme(
                    id: record.id,
                    title: record.title,
                    source: record.source,
                    kind: record.kind,
                    roleHexColors: parsed.roleHexColors,
                    fileName: record.fileName
                )
            } catch {
                print("[SpectraThemeManager] Failed to load installed UI theme at \(url.path): \(error)")
                return nil
            }
        }
    }
}
