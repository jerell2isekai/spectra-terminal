import Foundation
import GhosttyKit

/// Manages Spectra's config lifecycle: load from TOML, translate to ghostty format,
/// write generated ghostty config, and watch for file changes.
class ConfigManager {
    private(set) var config: SpectraConfig
    var onChange: ((SpectraConfig) -> Void)?

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceWork: DispatchWorkItem?
    private var suppressFileWatch = false

    /// Path to the auto-generated ghostty config (derived from Spectra TOML)
    private var ghosttyConfigURL: URL {
        SpectraConfig.configDir.appendingPathComponent(".ghostty-generated")
    }

    init() {
        self.config = SpectraConfig.load()
    }

    // MARK: - Ghostty Config Bridge

    /// Write a ghostty-format config file derived from the current Spectra config.
    @discardableResult
    func writeGhosttyConfig() -> String {
        let dir = SpectraConfig.configDir
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let content = config.toGhosttyConfig()
            try content.write(to: ghosttyConfigURL, atomically: true, encoding: .utf8)
        } catch {
            print("[ConfigManager] Failed to write ghostty config: \(error)")
        }
        return ghosttyConfigURL.path
    }

    /// Load Spectra config into a ghostty_config_t. Caller must free it when done.
    func createGhosttyConfig() -> ghostty_config_t? {
        guard let cfg = ghostty_config_new() else { return nil }

        let path = writeGhosttyConfig()
        path.withCString { cPath in
            ghostty_config_load_file(cfg, cPath)
        }
        ghostty_config_finalize(cfg)
        return cfg
    }

    // MARK: - Reload

    func reload() {
        config = SpectraConfig.load()
        onChange?(config)
    }

    /// Update config from Settings UI. Suppresses file watcher to prevent double-reload.
    func update(_ newConfig: SpectraConfig) {
        config = newConfig
        suppressFileWatch = true
        try? config.save()
        // Re-enable file watch after a short delay (past the debounce window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.suppressFileWatch = false
        }
        onChange?(config)
    }

    // MARK: - File Watching

    func startWatching() {
        stopWatching()

        let path = SpectraConfig.configFile.path
        if !FileManager.default.fileExists(atPath: path) {
            try? config.save()
        }

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
            // Cancel previous debounce to coalesce rapid events
            self.debounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.reload()
            }
            self.debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)

            // Re-watch after rename (editors like vim write-then-rename)
            if flags.contains(.rename) || flags.contains(.delete) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.startWatching()
                }
            }
        }
        source.setCancelHandler { [fd = fileDescriptor] in
            close(fd)
        }
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

    deinit {
        stopWatching()
    }
}
