import AppKit

/// Defines the interface for any content that can appear as a tab
/// within a `PaneTabController`.
///
/// Currently only terminal tabs conform to this protocol.
protocol TabContent: AnyObject {
    /// The view to display when this tab is active.
    var contentView: NSView { get }

    /// The title shown in the tab bar.
    var tabTitle: String { get }

    /// Optional icon displayed before the title in the tab bar.
    var tabIcon: NSImage? { get }

    /// The type of tab, used for serialization and type-specific behavior.
    var tabType: TabType { get }

    /// Called when the tab is being closed. Perform cleanup here.
    func detach()

    /// Make this tab's content the first responder.
    func focus()
}

/// Distinguishes tab types for serialization and conditional behavior.
enum TabType {
    case terminal
}
