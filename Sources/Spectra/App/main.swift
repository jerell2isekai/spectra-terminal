import AppKit
import Foundation
import GhosttyKit

// Set up Spectra's own resources for libghostty before initialization.
// libghostty uses GHOSTTY_RESOURCES_DIR to locate terminfo, shell integration,
// and themes. Without this, Spectra depends on Ghostty.app being installed.
if ProcessInfo.processInfo.environment["GHOSTTY_RESOURCES_DIR"] == nil {
    // For .app bundles: Bundle.main.resourcePath = Contents/Resources/
    // For SPM debug builds: look for the resource bundle next to the executable
    let resourcesGhostty: String? = {
        // .app bundle: Contents/Resources/ghostty
        if let bundlePath = Bundle.main.resourcePath {
            let candidate = (bundlePath as NSString).appendingPathComponent("ghostty")
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        // SPM build: Spectra_Spectra.bundle/ghostty alongside the executable
        let exeURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let spmBundle = exeURL.deletingLastPathComponent()
            .appendingPathComponent("Spectra_Spectra.bundle/ghostty")
        if FileManager.default.fileExists(atPath: spmBundle.path) {
            return spmBundle.path
        }
        return nil
    }()
    if let dir = resourcesGhostty {
        setenv("GHOSTTY_RESOURCES_DIR", dir, 1)
        // TERMINFO is sibling to ghostty/ in the resources dir
        let terminfo = (dir as NSString).deletingLastPathComponent + "/terminfo"
        if FileManager.default.fileExists(atPath: terminfo) {
            setenv("TERMINFO", terminfo, 1)
        }
    } else {
        print("[Spectra] warning: bundled ghostty resources not found; "
              + "TERM/shell-integration may not work without Ghostty.app installed")
    }
}

// Initialize libghostty global state before anything else.
let ghosttyOk = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
guard ghosttyOk == GHOSTTY_SUCCESS else {
    fatalError("ghostty_init failed with code \(ghosttyOk)")
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
