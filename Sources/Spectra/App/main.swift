import AppKit
import GhosttyKit

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
