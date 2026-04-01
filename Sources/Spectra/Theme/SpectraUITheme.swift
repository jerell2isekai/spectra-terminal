import AppKit
import Foundation

enum SpectraUIThemeSource: String, Codable, CaseIterable {
    case bundled
    case user
    case github
}

enum SpectraUIThemeKind: String, Codable {
    case light
    case dark
}

struct SpectraUITheme: Codable, Hashable {
    let id: String
    let title: String
    let source: SpectraUIThemeSource
    let kind: SpectraUIThemeKind
    let roleHexColors: [String: String]
    let fileName: String?

    func color(_ role: SpectraUIColorRole) -> NSColor {
        let hex = roleHexColors[role.rawValue]
            ?? Self.defaultHexColors(for: kind)[role.rawValue]
            ?? "#FF00FF"
        return Self.parseHexColor(hex) ?? .systemPink
    }

    var previewRoles: [SpectraUIColorRole] {
        [.sidebarBackground, .activityBarBackground, .tabActiveBackground, .accent, .overlayBackground]
    }

    var sourceBadge: String {
        switch source {
        case .bundled: return "Bundled"
        case .user: return "User"
        case .github: return "GitHub"
        }
    }

    var typeBadge: String {
        kind == .dark ? "Dark" : "Light"
    }

    static func defaultHexColors(for kind: SpectraUIThemeKind) -> [String: String] {
        switch kind {
        case .dark:
            return [
                SpectraUIColorRole.accent.rawValue: "#2F81F7",
                SpectraUIColorRole.separator.rawValue: "#30363D",
                SpectraUIColorRole.sidebarBackground.rawValue: "#161B22",
                SpectraUIColorRole.sidebarForeground.rawValue: "#C9D1D9",
                SpectraUIColorRole.sidebarSecondaryForeground.rawValue: "#8B949E",
                SpectraUIColorRole.sidebarTertiaryForeground.rawValue: "#6E7681",
                SpectraUIColorRole.activityBarBackground.rawValue: "#0D1117",
                SpectraUIColorRole.activityBarForeground.rawValue: "#E6EDF3",
                SpectraUIColorRole.activityBarInactiveForeground.rawValue: "#7D8590",
                SpectraUIColorRole.activityBarBadgeBackground.rawValue: "#2F81F7",
                SpectraUIColorRole.activityBarBadgeForeground.rawValue: "#FFFFFF",
                SpectraUIColorRole.tabBarBackground.rawValue: "#0D1117",
                SpectraUIColorRole.tabActiveBackground.rawValue: "#161B22",
                SpectraUIColorRole.tabActiveForeground.rawValue: "#E6EDF3",
                SpectraUIColorRole.tabInactiveBackground.rawValue: "#0D1117",
                SpectraUIColorRole.tabInactiveForeground.rawValue: "#8B949E",
                SpectraUIColorRole.tabInactiveCloseForeground.rawValue: "#6E7681",
                SpectraUIColorRole.overlayBackground.rawValue: "#161B22",
                SpectraUIColorRole.overlayForeground.rawValue: "#E6EDF3",
                SpectraUIColorRole.overlaySecondaryForeground.rawValue: "#8B949E",
                SpectraUIColorRole.commandPaletteBackground.rawValue: "#161B22",
                SpectraUIColorRole.commandPaletteForeground.rawValue: "#E6EDF3",
                SpectraUIColorRole.commandPaletteSecondaryForeground.rawValue: "#8B949E",
                SpectraUIColorRole.commandPaletteSelectionBackground.rawValue: "#1F6FEB33",
                SpectraUIColorRole.commandPaletteSelectionForeground.rawValue: "#E6EDF3",
                SpectraUIColorRole.inputBackground.rawValue: "#0D1117",
                SpectraUIColorRole.inputForeground.rawValue: "#E6EDF3",
                SpectraUIColorRole.inputBorder.rawValue: "#30363D",
                SpectraUIColorRole.buttonBackground.rawValue: "#238636",
                SpectraUIColorRole.buttonForeground.rawValue: "#FFFFFF",
                SpectraUIColorRole.buttonHoverBackground.rawValue: "#2EA043",
                SpectraUIColorRole.gitAdded.rawValue: "#3FB950",
                SpectraUIColorRole.gitModified.rawValue: "#D29922",
                SpectraUIColorRole.gitDeleted.rawValue: "#F85149",
                SpectraUIColorRole.gitUntracked.rawValue: "#8B949E",
                SpectraUIColorRole.gitConflict.rawValue: "#DB6D28",
            ]
        case .light:
            return [
                SpectraUIColorRole.accent.rawValue: "#0969DA",
                SpectraUIColorRole.separator.rawValue: "#D0D7DE",
                SpectraUIColorRole.sidebarBackground.rawValue: "#FFFFFF",
                SpectraUIColorRole.sidebarForeground.rawValue: "#1F2328",
                SpectraUIColorRole.sidebarSecondaryForeground.rawValue: "#59636E",
                SpectraUIColorRole.sidebarTertiaryForeground.rawValue: "#6E7781",
                SpectraUIColorRole.activityBarBackground.rawValue: "#F6F8FA",
                SpectraUIColorRole.activityBarForeground.rawValue: "#1F2328",
                SpectraUIColorRole.activityBarInactiveForeground.rawValue: "#6E7781",
                SpectraUIColorRole.activityBarBadgeBackground.rawValue: "#0969DA",
                SpectraUIColorRole.activityBarBadgeForeground.rawValue: "#FFFFFF",
                SpectraUIColorRole.tabBarBackground.rawValue: "#F6F8FA",
                SpectraUIColorRole.tabActiveBackground.rawValue: "#FFFFFF",
                SpectraUIColorRole.tabActiveForeground.rawValue: "#1F2328",
                SpectraUIColorRole.tabInactiveBackground.rawValue: "#F6F8FA",
                SpectraUIColorRole.tabInactiveForeground.rawValue: "#59636E",
                SpectraUIColorRole.tabInactiveCloseForeground.rawValue: "#6E7781",
                SpectraUIColorRole.overlayBackground.rawValue: "#FFFFFF",
                SpectraUIColorRole.overlayForeground.rawValue: "#1F2328",
                SpectraUIColorRole.overlaySecondaryForeground.rawValue: "#59636E",
                SpectraUIColorRole.commandPaletteBackground.rawValue: "#FFFFFF",
                SpectraUIColorRole.commandPaletteForeground.rawValue: "#1F2328",
                SpectraUIColorRole.commandPaletteSecondaryForeground.rawValue: "#59636E",
                SpectraUIColorRole.commandPaletteSelectionBackground.rawValue: "#DDF4FF",
                SpectraUIColorRole.commandPaletteSelectionForeground.rawValue: "#1F2328",
                SpectraUIColorRole.inputBackground.rawValue: "#FFFFFF",
                SpectraUIColorRole.inputForeground.rawValue: "#1F2328",
                SpectraUIColorRole.inputBorder.rawValue: "#D0D7DE",
                SpectraUIColorRole.buttonBackground.rawValue: "#1F883D",
                SpectraUIColorRole.buttonForeground.rawValue: "#FFFFFF",
                SpectraUIColorRole.buttonHoverBackground.rawValue: "#1A7F37",
                SpectraUIColorRole.gitAdded.rawValue: "#1A7F37",
                SpectraUIColorRole.gitModified.rawValue: "#9A6700",
                SpectraUIColorRole.gitDeleted.rawValue: "#CF222E",
                SpectraUIColorRole.gitUntracked.rawValue: "#6E7781",
                SpectraUIColorRole.gitConflict.rawValue: "#BC4C00",
            ]
        }
    }

    static func parseHexColor(_ raw: String) -> NSColor? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard hex.count == 6 || hex.count == 8,
              let value = UInt64(hex, radix: 16) else { return nil }
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
}
