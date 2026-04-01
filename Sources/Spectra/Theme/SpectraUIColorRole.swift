import AppKit

enum SpectraUIColorRole: String, CaseIterable, Codable {
    case accent
    case separator

    case sidebarBackground
    case sidebarForeground
    case sidebarSecondaryForeground
    case sidebarTertiaryForeground

    case activityBarBackground
    case activityBarForeground
    case activityBarInactiveForeground
    case activityBarBadgeBackground
    case activityBarBadgeForeground

    case tabBarBackground
    case tabActiveBackground
    case tabActiveForeground
    case tabInactiveBackground
    case tabInactiveForeground
    case tabInactiveCloseForeground

    case overlayBackground
    case overlayForeground
    case overlaySecondaryForeground

    case commandPaletteBackground
    case commandPaletteForeground
    case commandPaletteSecondaryForeground
    case commandPaletteSelectionBackground
    case commandPaletteSelectionForeground

    case inputBackground
    case inputForeground
    case inputBorder
    case buttonBackground
    case buttonForeground
    case buttonHoverBackground

    case gitAdded
    case gitModified
    case gitDeleted
    case gitUntracked
    case gitConflict
}
