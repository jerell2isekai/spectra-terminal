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

    /// Create a ghostty_config_t by directly loading Spectra's config file.
    /// No translation needed — the file IS in ghostty format.
    func createGhosttyConfig() -> ghostty_config_t? {
        guard let cfg = ghostty_config_new() else { return nil }

        let path = SpectraConfig.configFile.path
        path.withCString { cPath in
            ghostty_config_load_file(cfg, cPath)
        }
        ghostty_config_finalize(cfg)
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
