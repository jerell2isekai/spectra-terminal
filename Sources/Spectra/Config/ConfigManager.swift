import Foundation
import GhosttyKit

/// Manages Spectra's config lifecycle: load ghostty-format config directly, watch for changes.
/// No TOML parsing or format translation needed — config is native ghostty format.
class ConfigManager {
    var onChange: (() -> Void)?

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceWork: DispatchWorkItem?
    private var suppressFileWatch = false

    init() {
        SpectraConfig.ensureConfigExists()
    }

    // MARK: - Ghostty Config

    /// Create a ghostty_config_t by loading Spectra's config file.
    /// Spectra-only keys (prefixed with `spectra-`) are stripped before loading
    /// since ghostty's parser doesn't recognize them.
    func createGhosttyConfig() -> ghostty_config_t? {
        guard let cfg = ghostty_config_new() else { return nil }

        let path = SpectraConfig.configFile.path
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            // Strip Spectra-only keys that ghostty doesn't recognize
            let filtered = content.components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("spectra-") }
                .joined(separator: "\n")
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("spectra-ghostty-\(ProcessInfo.processInfo.processIdentifier).conf")
            try? filtered.write(to: tmpURL, atomically: true, encoding: .utf8)
            tmpURL.path.withCString { cPath in
                ghostty_config_load_file(cfg, cPath)
            }
            try? FileManager.default.removeItem(at: tmpURL)
        } else {
            path.withCString { cPath in
                ghostty_config_load_file(cfg, cPath)
            }
        }

        ghostty_config_finalize(cfg)

        // Log any config diagnostics (parse errors or warnings)
        let diagCount = ghostty_config_diagnostics_count(cfg)
        if diagCount > 0 {
            for i in 0..<diagCount {
                let diag = ghostty_config_get_diagnostic(cfg, i)
                if let msg = diag.message {
                    print("[Config] diagnostic: \(String(cString: msg))")
                }
            }
        }

        return cfg
    }

    // MARK: - Reload

    func reload() {
        onChange?()
    }

    /// Write updates to config file and trigger reload. Suppresses file watcher.
    func writeAndReload(_ updates: [String: String]) {
        suppressFileWatch = true
        SpectraConfig.write(updates)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.suppressFileWatch = false
        }
        onChange?()
    }

    // MARK: - File Watching

    func startWatching() {
        stopWatching()

        let path = SpectraConfig.configFile.path
        SpectraConfig.ensureConfigExists()

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self, !self.suppressFileWatch else { return }
            let flags = source.data
            self.debounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.reload() }
            self.debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)

            if flags.contains(.rename) || flags.contains(.delete) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.startWatching()
                }
            }
        }
        source.setCancelHandler { [fd = fileDescriptor] in close(fd) }
        source.resume()
        fileWatcher = source
    }

    func stopWatching() {
        debounceWork?.cancel()
        debounceWork = nil
        fileWatcher?.cancel()
        fileWatcher = nil
        fileDescriptor = -1
    }

    deinit { stopWatching() }
}
